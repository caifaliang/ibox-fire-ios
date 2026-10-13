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
            // 开战归来：优先 pendingURL（战报页），勿一律进首页/等待页（用户体感「回桌面」）
            let resume = vm.pendingURL
            vm.pendingURL = nil
            if !cookie.isEmpty {
                await CookieBridge.inject(cookieHeader: cookie, into: wv)
                let dest = resume ?? URL(string: LoginURLs.ledouEntry)
                if let dest {
                    context.coordinator.applyUA(wv, desktop: false)
                    wv.load(URLRequest(url: dest))
                }
            } else if let resume {
                context.coordinator.applyUA(wv, desktop: vm.preferDesktopUA)
                wv.load(URLRequest(url: resume))
            } else {
                wv.loadHTMLString(LoginURLs.waitingHTML, baseURL: URL(string: "https://dld.qzapp.z.qq.com/"))
            }
        }
        return wv
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 被 RootView 拆掉时尽快释放 WebContent（对齐开战让内存给 Ruffle）
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        if coordinator.vm.gameWebView === uiView {
            coordinator.vm.gameWebView = nil
        }
        coordinator.webView = nil
        uiView.load(URLRequest(url: URL(string: "about:blank")!))
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

        // 开战时 RootView 会拆掉本 View；此处不再 about:blank（拆树才真正杀 WebContent）
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
        var lastCookieInject = 0
        var defaultUA: String?
        private var captureTask: Task<Void, Never>?
        private var oneKeyQrTask: Task<Void, Never>?
        private var lastContinueURL = ""
        private var lastHandledCode = ""
        private var lastStuckRecoverAt: TimeInterval = 0

        /// 把 _blank / window.open 留在壳内；wtlogin 交给原生拦截
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
            // 一键：graph → 抠 iframe xlogin（新鲜 h5sig）→ ptqrshow → 跳 QQ；禁止黑屏遮罩卡死
            if vm.loginMode == .oneKey {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.driveOneKey(from: webView)
                }
            }
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

        /// graph/oauth 落地 → 顶层打开 xlogin → pipeline 跳 QQ
        private func driveOneKey(from webView: WKWebView) async {
            guard vm.loginMode == .oneKey, !vm.session.isLoggedIn else { return }
            let url = webView.url

            // 误入无 Cookie 的 index.php：别报「缺 skey」，拉回 authorize
            if let url, LoginURLs.isOauthLanding(url), LoginURLs.oauthCode(from: url) == nil {
                vm.statusText = "一键登录：重新进入授权…"
                vm.pendingURL = URL(string: LoginURLs.oneKeyLogin)
                return
            }

            if QqOneKeyLogin.isXloginPage(url) {
                vm.statusText = "一键登录：生成授权并跳转 QQ…"
                startOneKeyQrPipeline(webView, forceRefresh: QqOneKeyLogin.qrLikelyExpired)
                return
            }

            if QqOneKeyLogin.isGraphOAuthPage(url) {
                vm.statusText = "一键登录：定位登录框…"
                if let target = await evalJS(QqOneKeyLogin.jsFindLoginTarget, in: webView) as? String,
                   !target.isEmpty {
                    if QqOneKeyLogin.isWtloginScheme(URL(string: target)?.scheme) {
                        if let u = URL(string: target) {
                            let cookies = await CookieBridge.snapshotQQCookies(from: webView)
                            QqOneKeyLogin.rememberAuthorization(loginURL: webView.url, cookies: cookies)
                            _ = QqOneKeyLogin.openInQQ(u)
                            vm.statusText = "已跳转 QQ，可在 QQ 内切换账号后确认…"
                        }
                        return
                    }
                    if let u = URL(string: target), u.host?.contains("ptlogin") == true {
                        vm.statusText = "一键登录：打开登录页并跳转 QQ…"
                        webView.load(URLRequest(url: u))
                        return
                    }
                }
                _ = await evalJS(QqOneKeyLogin.jsClickOneKeyButton, in: webView)
                // 仍停在 graph：继续 pipeline（等跳到 xlogin）；同时稍后重试找 iframe
                startOneKeyQrPipeline(webView, forceRefresh: false)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard vm.loginMode == .oneKey, !vm.session.isLoggedIn else { return }
                if QqOneKeyLogin.isGraphOAuthPage(webView.url),
                   let target = await evalJS(QqOneKeyLogin.jsFindLoginTarget, in: webView) as? String,
                   let u = URL(string: target), u.host?.contains("ptlogin") == true {
                    webView.load(URLRequest(url: u))
                }
                return
            }

            // 其它页也跑 pipeline，万一已是隐藏 xlogin
            startOneKeyQrPipeline(webView, forceRefresh: false)
        }

        /// ptqrshow → wtloginmqq3?qrcode=… → 跳转 QQ（确认前不 submit，到期换新码）
        private func startOneKeyQrPipeline(_ webView: WKWebView, forceRefresh: Bool = false) {
            oneKeyQrTask?.cancel()
            oneKeyQrTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                if forceRefresh {
                    QqOneKeyLogin.clearLaunchStamp()
                    _ = await self.evalJS(QqOneKeyLogin.jsResetQr, in: webView)
                }
                self.vm.statusText = "一键登录：正在生成授权并跳转 QQ…"
                var lastOpenedQr = ""
                for round in 0..<90 {
                    guard !Task.isCancelled, self.vm.loginMode == .oneKey, !self.vm.session.isLoggedIn else { return }

                    let needNew = lastOpenedQr.isEmpty || QqOneKeyLogin.qrLikelyExpired
                    if needNew && (round == 0 || round % 3 == 0 || QqOneKeyLogin.qrLikelyExpired) {
                        if QqOneKeyLogin.qrLikelyExpired {
                            _ = await self.evalJS(QqOneKeyLogin.jsResetQr, in: webView)
                            QqOneKeyLogin.clearLaunchStamp()
                            lastOpenedQr = ""
                            self.vm.statusText = "授权将过期，换新码并重新跳转 QQ…"
                        }
                        _ = await self.evalJS(QqOneKeyLogin.jsRequestQr, in: webView) as? String
                    }

                    try? await Task.sleep(nanoseconds: 350_000_000)

                    guard let raw = await self.evalJS(QqOneKeyLogin.jsPollStatus, in: webView) as? String,
                          let data = raw.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let status = obj["status"] as? String else { continue }

                    if status == "failed" {
                        _ = await self.evalJS(QqOneKeyLogin.jsResetQr, in: webView)
                        QqOneKeyLogin.clearLaunchStamp()
                        lastOpenedQr = ""
                        self.vm.statusText = "授权准备失败，重试中…"
                        continue
                    }

                    if status == "ready", let qr = obj["url"] as? String, !qr.isEmpty {
                        // 同一授权串未过期：只 polling（含已在 QQ / 已回壳），勿反复 open、勿开 p= jump
                        if qr == lastOpenedQr, !QqOneKeyLogin.qrLikelyExpired {
                            _ = await self.evalJS(QqOneKeyLogin.jsKeepPolling, in: webView)
                            continue
                        }
                        lastOpenedQr = qr
                        let cookies = await CookieBridge.snapshotQQCookies(from: webView)
                        QqOneKeyLogin.rememberAuthorization(loginURL: webView.url, cookies: cookies)
                        let ok = QqOneKeyLogin.openWithQrAuthorization(qr, force: true)
                        self.vm.statusText = ok
                            ? "已跳转 QQ，可在 QQ 内切换账号后确认…"
                            : "无法打开 QQ，请确认已安装手机 QQ"
                    }
                }
            }
        }

        private func evalJS(_ script: String, in webView: WKWebView) async -> Any? {
            await withCheckedContinuation { cont in
                webView.evaluateJavaScript(script) { result, _ in
                    cont.resume(returning: result)
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

            // ② wtlogin / mqq：页内 p= 会授权失败 → 改走 qrcode 跳转 QQ；其它放行唤起
            if QqOneKeyLogin.isWtloginScheme(scheme) {
                decisionHandler(.cancel)
                if QqOneKeyLogin.isBrokenPageOneClick(url) {
                    Task { @MainActor in
                        self.vm.loginMode = .oneKey
                        self.vm.statusText = "正在跳转 QQ…"
                        if let wv = self.webView {
                            self.startOneKeyQrPipeline(wv, forceRefresh: true)
                        }
                    }
                    return
                }
                Task { @MainActor in
                    if let wv = self.webView {
                        let cookies = await CookieBridge.snapshotQQCookies(from: wv)
                        QqOneKeyLogin.rememberAuthorization(loginURL: wv.url, cookies: cookies)
                    }
                    let ok = QqOneKeyLogin.openInQQ(url)
                    self.vm.loginMode = .oneKey
                    self.vm.statusText = ok ? "已打开 QQ，可在 QQ 内切换账号后确认…" : "无法打开 QQ，请确认已安装"
                }
                return
            }

            if scheme == "http" || scheme == "https" {
                // 一键：仅允许扫码确认后的 jump（openlogin 含 pt_skey_valid=1）；拦 Android 静态 p=（valid=0 →「授权失败」）
                if vm.loginMode == .oneKey,
                   (url.host ?? "").lowercased().contains("ptlogin2.qq.com"),
                   url.path.lowercased().contains("jump") {
                    let raw = url.absoluteString
                    let decoded = raw.removingPercentEncoding ?? raw
                    let skeyOk = decoded.contains("pt_skey_valid=1")
                    if !skeyOk {
                        decisionHandler(.cancel)
                        Task { @MainActor in
                            self.vm.statusText = "已拦下失败授权页，留在登录页完成确认…"
                            if let wv = self.webView, QqOneKeyLogin.isXloginPage(wv.url) {
                                wv.evaluateJavaScript(QqOneKeyLogin.jsResumeAfterQQ, completionHandler: nil)
                            } else {
                                self.vm.pendingURL = URL(string: LoginURLs.oneKeyLogin)
                            }
                        }
                        return
                    }
                }
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
            if QqOneKeyLogin.isWtloginScheme(scheme) {
                if QqOneKeyLogin.isBrokenPageOneClick(url) {
                    Task { @MainActor in
                        self.vm.loginMode = .oneKey
                        if let wv = self.webView {
                            self.startOneKeyQrPipeline(wv, forceRefresh: true)
                        }
                    }
                } else {
                    _ = QqOneKeyLogin.openInQQ(url)
                    Task { @MainActor in
                        self.vm.loginMode = .oneKey
                        self.vm.statusText = "已打开 QQ，请确认登录…"
                    }
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
                if vm.loginMode == .scan || vm.loginMode == .oneKey,
                   let s = webView.url?.absoluteString,
                   let cont = LoginURLs.continueAuthorizeUrl(xloginUrl: s),
                   cont != lastContinueURL,
                   let u = URL(string: cont) {
                    lastContinueURL = cont
                    vm.statusText = vm.loginMode == .scan ? "扫码已确认，继续授权…" : "一键已确认，继续授权…"
                    webView.load(URLRequest(url: u))
                    return
                }
                let url = webView.url
                let shouldWait = vm.loginMode == .scan || vm.loginMode == .oneKey
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
                } else if LoginURLs.isGameHost(url), !vm.session.isLoggedIn,
                          vm.loginMode == .idle {
                    // 一键/扫码进行中勿刷这条（会误导成「已进游戏」且盖住跳转 QQ 状态）
                    vm.statusText = "已进游戏页，但未读到 skey。可试 Cookie 登陆备份"
                }
            }
        }
    }
}
