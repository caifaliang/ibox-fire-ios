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
        context.coordinator.vm.gameWebView = wv

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
        vm.gameWebView = webView
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

        // Cookie 注入优先于单独 pendingURL，避免只 load 不带会话
        if context.coordinator.lastCookieInject != vm.cookieInjectToken {
            context.coordinator.lastCookieInject = vm.cookieInjectToken
            let header = SessionStore.shared.cookieHeader
            let next = vm.pendingURL ?? URL(string: LoginURLs.ledouEntry)
            vm.pendingURL = nil
            context.coordinator.applyUA(webView, desktop: false)
            Task { @MainActor in
                if !header.isEmpty {
                    await CookieBridge.inject(cookieHeader: header, into: webView)
                }
                // 稍等 cookie 落盘再跳转
                try? await Task.sleep(nanoseconds: 150_000_000)
                if let u = next {
                    webView.load(URLRequest(url: u))
                }
            }
            return
        }

        // 官方动画期间：游戏页改 about:blank，释放 WebContent 内存给 Ruffle
        if context.coordinator.wasSuspended != vm.suspendGameWebForReplay {
            context.coordinator.wasSuspended = vm.suspendGameWebForReplay
            if vm.suspendGameWebForReplay {
                webView.stopLoading()
                webView.load(URLRequest(url: URL(string: "about:blank")!))
                return
            }
        }

        if vm.suspendGameWebForReplay {
            return
        }

        if let u = vm.pendingURL {
            context.coordinator.applyUA(webView, desktop: vm.preferDesktopUA)
            let dest = u
            vm.pendingURL = nil
            webView.load(URLRequest(url: dest))
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
        var wasSuspended = false
        var lastCookieInject = 0
        var defaultUA: String?
        private var captureTask: Task<Void, Never>?
        private var lastContinueURL = ""
        private var lastHandledCode = ""
        private var lastStuckRecoverAt: TimeInterval = 0

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
            // 已登录却仍停在 QQ「一键登录」页 → 强制进 phonepk
            webView.evaluateJavaScript(LoginURLs.qqLoginProbeJS) { [weak self] result, _ in
                guard let self else { return }
                let flag = (result as? String) ?? ""
                Task { @MainActor in
                    guard self.vm.session.isLoggedIn, flag == "qq" else { return }
                    let now = Date().timeIntervalSince1970
                    guard now - self.lastStuckRecoverAt > 2.5 else { return }
                    self.lastStuckRecoverAt = now
                    self.vm.recoverIfStuckOnQqLoginPage()
                }
            }
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

            // about:blank 等：QQ 跳转链常见，必须放行，否则与登录状态文案死循环闪烁
            if scheme == "about" || scheme.isEmpty {
                decisionHandler(.allow)
                return
            }

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
                // 扫码落地 index.php?code=…：只提示一次，进游戏后由 Cookie 捕获改成「已登录」
                if vm.loginMode == .scan,
                   LoginURLs.isOauthLanding(url),
                   LoginURLs.oauthCode(from: url) != nil,
                   !vm.session.isLoggedIn {
                    Task { @MainActor in
                        if !vm.session.isLoggedIn {
                            vm.statusText = "扫码成功，正在写入会话…"
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

            // 其它未知 scheme：静默取消，不刷状态栏（避免与「已登录」闪烁）
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
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                // 已登录且空闲：不再反复 capture → openGameHome，避免闪烁/打断游戏
                if vm.session.isLoggedIn, vm.loginMode == .idle {
                    return
                }
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
                let url = webView.url
                let shouldWait = vm.loginMode == .scan
                    || LoginURLs.isGameHost(url)
                    || LoginURLs.isOauthLanding(url)
                let header: String
                if shouldWait {
                    header = await CookieBridge.waitForSkey(from: webView)
                } else {
                    header = await CookieBridge.readCookieHeader(from: webView)
                }
                if LoginURLs.hasRealSkey(header) {
                    vm.onCookiesCaptured(header)
                } else if LoginURLs.isGameHost(url), !vm.session.isLoggedIn {
                    vm.statusText = "已进游戏页，但未读到 skey。可试 Cookie 登陆备份"
                }
            }
        }
    }
}
