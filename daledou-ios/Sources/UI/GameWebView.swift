import SwiftUI
import UIKit
import WebKit

struct GameWebView: UIViewRepresentable {
    @ObservedObject var vm: AppViewModel
    /// 退出时递增，触发清 Cookie + 重载
    var clearEpoch: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        // 禁止 JS 乱开新窗口到系统浏览器
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        // 避免部分跳转被当成「用 Safari 打开」
        if #available(iOS 16.4, *) {
            wv.isInspectable = true
        }
        context.coordinator.webView = wv

        Task { @MainActor in
            let cookie = SessionStore.shared.cookieHeader
            if !cookie.isEmpty {
                await CookieBridge.inject(cookieHeader: cookie, into: wv)
            }
            let start = LoginURLs.shellStartUrl(cookie: cookie)
            if let u = URL(string: start) {
                wv.load(URLRequest(url: u))
            }
        }
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.vm = vm

        if context.coordinator.lastClearEpoch != clearEpoch {
            context.coordinator.lastClearEpoch = clearEpoch
            let next = vm.pendingURL
            Task { @MainActor in
                await CookieBridge.clearAll(from: webView)
                if let u = next {
                    webView.load(URLRequest(url: u))
                    vm.pendingURL = nil
                } else if let u = URL(string: LoginURLs.xloginHome) {
                    webView.load(URLRequest(url: u))
                }
            }
            return
        }

        if let u = vm.pendingURL {
            webView.load(URLRequest(url: u))
            DispatchQueue.main.async { vm.pendingURL = nil }
        }

        if context.coordinator.lastReloadToken != vm.webReloadToken {
            context.coordinator.lastReloadToken = vm.webReloadToken
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var vm: AppViewModel
        weak var webView: WKWebView?
        var lastReloadToken = 0
        var lastClearEpoch = 0
        private var captureTask: Task<Void, Never>?

        /// 拦截唤端 / 外开，强制留在壳内
        private let stayInShellJS = """
        (function(){
          if (window.__dldStay) return;
          window.__dldStay = 1;
          function keep(u){
            try {
              if (!u) return false;
              var s = String(u);
              if (/^(wtlogin|mqq|tencent)/i.test(s)) {
                /* 交给原生 decidePolicy 处理，这里阻止默认 */
                return true;
              }
              if (/^https?:/i.test(s)) {
                location.href = s;
                return true;
              }
            } catch(e) {}
            return false;
          }
          var _open = window.open;
          window.open = function(u){
            if (keep(u)) return null;
            try { return _open ? _open.apply(window, arguments) : null; } catch(e) { return null; }
          };
          document.addEventListener('click', function(ev){
            var a = ev.target && ev.target.closest ? ev.target.closest('a') : null;
            if (!a || !a.href) return;
            if (/^(wtlogin|mqq|tencent)/i.test(a.href)) {
              ev.preventDefault();
              ev.stopPropagation();
              /* 触发导航让原生拦截 */
              location.href = a.href;
            } else if (a.target === '_blank' && /^https?:/i.test(a.href)) {
              ev.preventDefault();
              location.href = a.href;
            }
          }, true);
        })();
        """

        init(vm: AppViewModel) {
            self.vm = vm
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url
            Task { @MainActor in
                vm.currentURLString = url?.absoluteString ?? ""
            }
            webView.evaluateJavaScript(stayInShellJS, completionHandler: nil)
            scheduleCookieCapture(webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = (url.scheme ?? "").lowercased()

            if scheme == "daledouapp" {
                Task { @MainActor in vm.handleOpenURL(url) }
                decisionHandler(.cancel)
                return
            }

            // 关键：页内「一键登录」会跳 wtloginmqq → QQ → 系统浏览器。
            // iOS 无法当默认浏览器接 jump，故拦截唤端，改在壳内继续 https 登录链。
            if LoginURLs.isQqWakeScheme(scheme) {
                let fallback = URL(string: LoginURLs.ledouPtlogin)!
                let stay = LoginURLs.httpsPayload(fromQqScheme: url) ?? fallback
                Task { @MainActor in
                    vm.statusText = "已拦截唤起 QQ，改在壳内继续登录"
                }
                webView.load(URLRequest(url: stay))
                decisionHandler(.cancel)
                return
            }

            if scheme == "http" || scheme == "https" {
                // 用户点击的链接：强制在本 WebView 加载，避免 Universal Link / 外开 Safari
                if navigationAction.navigationType == .linkActivated {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }

            // 其它未知 scheme：不交给系统（否则容易蹦浏览器）
            Task { @MainActor in
                vm.statusText = "已拦截外部跳转：\(scheme)"
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                let scheme = (url.scheme ?? "").lowercased()
                if LoginURLs.isQqWakeScheme(scheme) {
                    let stay = LoginURLs.httpsPayload(fromQqScheme: url)
                        ?? URL(string: LoginURLs.ledouPtlogin)!
                    webView.load(URLRequest(url: stay))
                } else if scheme == "http" || scheme == "https" {
                    webView.load(URLRequest(url: url))
                }
            }
            return nil
        }

        private func scheduleCookieCapture(_ webView: WKWebView) {
            captureTask?.cancel()
            captureTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                let header = await CookieBridge.readCookieHeader(from: webView)
                if LoginURLs.hasRealSkey(header) {
                    vm.onCookiesCaptured(header)
                }
            }
        }
    }
}
