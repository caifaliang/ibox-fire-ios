import SwiftUI
import UIKit
import WebKit

struct GameWebView: UIViewRepresentable {
    @ObservedObject var vm: AppViewModel
    var clearEpoch: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 16.4, *) {
            wv.isInspectable = true
        }
        context.coordinator.webView = wv
        context.coordinator.defaultUA = wv.value(forKey: "userAgent") as? String

        Task { @MainActor in
            let cookie = SessionStore.shared.cookieHeader
            if !cookie.isEmpty {
                await CookieBridge.inject(cookieHeader: cookie, into: wv)
                if let u = URL(string: LoginURLs.ledouEntry) {
                    wv.load(URLRequest(url: u))
                }
            } else {
                wv.loadHTMLString(LoginURLs.waitingHTML, baseURL: URL(string: "https://dld.qzapp.z.qq.com/"))
            }
        }
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.vm = vm
        context.coordinator.applyUA(webView, desktop: vm.preferDesktopUA)

        if context.coordinator.lastClearEpoch != clearEpoch {
            context.coordinator.lastClearEpoch = clearEpoch
            let next = vm.pendingURL
            let waiting = vm.loadWaitingPage
            Task { @MainActor in
                await CookieBridge.clearAll(from: webView)
                if waiting {
                    vm.loadWaitingPage = false
                    webView.loadHTMLString(
                        LoginURLs.waitingHTML,
                        baseURL: URL(string: "https://dld.qzapp.z.qq.com/")
                    )
                }
                if let u = next {
                    context.coordinator.applyUA(webView, desktop: vm.preferDesktopUA)
                    webView.load(URLRequest(url: u))
                    vm.pendingURL = nil
                }
            }
            return
        }

        if vm.loadWaitingPage {
            vm.loadWaitingPage = false
            webView.loadHTMLString(
                LoginURLs.waitingHTML,
                baseURL: URL(string: "https://dld.qzapp.z.qq.com/")
            )
        }

        if let u = vm.pendingURL {
            context.coordinator.applyUA(webView, desktop: vm.preferDesktopUA)
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
        var defaultUA: String?
        private var captureTask: Task<Void, Never>?
        private var lastContinueURL = ""

        private let blankTargetJS = """
        (function(){
          if (window.__dldBlank) return; window.__dldBlank=1;
          var _open=window.open;
          window.open=function(u){
            try{ if(u && /^https?:/i.test(String(u))){ location.href=String(u); return null; } }catch(e){}
            return null;
          };
          document.addEventListener('click',function(ev){
            var a=ev.target&&ev.target.closest&&ev.target.closest('a');
            if(!a||!a.href)return;
            if(a.target==='_blank' && /^https?:/i.test(a.href)){
              ev.preventDefault(); location.href=a.href;
            }
          },true);
        })();
        """

        init(vm: AppViewModel) {
            self.vm = vm
        }

        func applyUA(_ webView: WKWebView, desktop: Bool) {
            if desktop {
                webView.customUserAgent = LoginURLs.desktopUA
            } else {
                webView.customUserAgent = defaultUA
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url
            Task { @MainActor in
                vm.onNavigated(to: url)
            }
            webView.evaluateJavaScript(blankTargetJS, completionHandler: nil)
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

            if LoginURLs.isQqWakeScheme(scheme) {
                // 一键流程：交给系统 QQ（schemacallback 指望回 App）
                if vm.allowQqWake || vm.loginMode == .oneClick {
                    UIApplication.shared.open(url, options: [:]) { ok in
                        Task { @MainActor in
                            if ok {
                                self.vm.statusText = "已唤起 QQ，请授权后等待回到本 App"
                            } else {
                                self.vm.statusText = "唤起 QQ 失败，请改用扫码登陆"
                            }
                        }
                    }
                    decisionHandler(.cancel)
                    return
                }
                // 扫码流程：禁止跳 QQ / 互联营销页，留在扫码页
                Task { @MainActor in
                    vm.statusText = "扫码模式已拦截唤起 QQ，请直接扫页面二维码"
                }
                decisionHandler(.cancel)
                return
            }

            if scheme == "http" || scheme == "https" {
                if navigationAction.navigationType == .linkActivated {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            let scheme = (url.scheme ?? "").lowercased()
            if LoginURLs.isQqWakeScheme(scheme) {
                if vm.allowQqWake || vm.loginMode == .oneClick {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                return nil
            }
            if scheme == "http" || scheme == "https" {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func scheduleCookieCapture(_ webView: WKWebView) {
            captureTask?.cancel()
            captureTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                // 扫码 continueAuthorize 防抖
                if vm.loginMode == .scan,
                   let s = webView.url?.absoluteString,
                   let cont = LoginURLs.continueAuthorizeUrl(xloginUrl: s),
                   cont != lastContinueURL,
                   let u = URL(string: cont) {
                    lastContinueURL = cont
                    vm.statusText = "扫码已确认，继续授权…"
                    webView.load(URLRequest(url: u))
                    return
                }
                let header = await CookieBridge.readCookieHeader(from: webView)
                if LoginURLs.hasRealSkey(header) {
                    vm.onCookiesCaptured(header)
                }
            }
        }
    }
}
