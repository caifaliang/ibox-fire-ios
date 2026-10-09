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
        // 持久 Cookie，利于授权后会话留在壳内
        cfg.websiteDataStore = .default()
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

        if context.coordinator.lastCookieInject != vm.cookieInjectToken {
            context.coordinator.lastCookieInject = vm.cookieInjectToken
            let header = SessionStore.shared.cookieHeader
            let next = vm.pendingURL ?? URL(string: LoginURLs.ledouEntry)
            Task { @MainActor in
                if !header.isEmpty {
                    await CookieBridge.inject(cookieHeader: header, into: webView)
                }
                if let u = next {
                    webView.load(URLRequest(url: u))
                    vm.pendingURL = nil
                }
            }
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
        var lastCookieInject = 0
        var defaultUA: String?
        private var captureTask: Task<Void, Never>?
        private var lastContinueURL = ""
        private var lastHandledCode = ""

        /// 把 _blank / window.open 留在壳内；不处理 mqq（交给原生拦截）
        private let stayJS = """
        (function(){
          if (window.__dldStay2) return; window.__dldStay2=1;
          window.open=function(u){
            try{
              var s=String(u||'');
              if(/^(wtlogin|mqq)/i.test(s)){ location.href=s; return null; }
              if(/^https?:/i.test(s)){ location.href=s; return null; }
            }catch(e){}
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

        init(vm: AppViewModel) { self.vm = vm }

        func applyUA(_ webView: WKWebView, desktop: Bool) {
            webView.customUserAgent = desktop ? LoginURLs.desktopUA : defaultUA
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in vm.onNavigated(to: webView.url) }
            webView.evaluateJavaScript(stayJS, completionHandler: nil)
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

            // ① 自定义 Scheme：拦截 code，绝不交给系统浏览器
            if LoginURLs.isCallbackScheme(scheme) || scheme == "daledouapp" {
                decisionHandler(.cancel)
                if let code = LoginURLs.oauthCode(from: url), code != lastHandledCode,
                   let finish = LoginURLs.finishWithCode(code) {
                    lastHandledCode = code
                    Task { @MainActor in
                        vm.statusText = "已拦截 Scheme 回调 code，壳内写会话…"
                        vm.pendingURL = finish
                    }
                } else {
                    Task { @MainActor in vm.handleOpenURL(url) }
                }
                return
            }

            // ② wtlogin / mqq：禁止唤起 QQ / 外跳（上一版失败根因）
            if scheme.hasPrefix("wtlogin") || scheme.hasPrefix("mqq") || scheme == "tencent" {
                decisionHandler(.cancel)
                Task { @MainActor in
                    vm.statusText = "已阻止跳转 QQ/浏览器，请在当前页完成授权或改用扫码"
                }
                return
            }

            if scheme == "http" || scheme == "https" {
                // https 回调带 code：留在 WebView 加载（会写 Cookie）
                if let code = LoginURLs.oauthCode(from: url), LoginURLs.isOauthLanding(url) || LoginURLs.isGameHost(url) {
                    if code != lastHandledCode {
                        lastHandledCode = code
                        Task { @MainActor in
                            vm.statusText = "授权回调中，等待游戏 Cookie…"
                        }
                    }
                }
                if navigationAction.navigationType == .linkActivated {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }

            // 其它 scheme 一律拦下，防止蹦浏览器
            decisionHandler(.cancel)
            Task { @MainActor in
                vm.statusText = "已拦截外部跳转：\(scheme)"
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            let scheme = (url.scheme ?? "").lowercased()
            if scheme.hasPrefix("wtlogin") || scheme.hasPrefix("mqq") {
                Task { @MainActor in
                    vm.statusText = "已阻止新窗口唤起 QQ"
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
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
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
                } else if vm.loginMode == .oneClick,
                          let u = webView.url,
                          LoginURLs.isGameHost(u) || LoginURLs.isOauthLanding(u) {
                    // 再等一轮跳转写 Cookie
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    let h2 = await CookieBridge.readCookieHeader(from: webView)
                    if LoginURLs.hasRealSkey(h2) {
                        vm.onCookiesCaptured(h2)
                    }
                }
            }
        }
    }
}
