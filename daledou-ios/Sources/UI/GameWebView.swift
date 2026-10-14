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
        // E2：documentStart 钩住页内拼出的 wtlogin，对照官方 schemacallback/字段
        cfg.userContentController.add(context.coordinator, name: "dldWtloginProbe")
        let probe = WKUserScript(
            source: Coordinator.wtloginProbeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        cfg.userContentController.addUserScript(probe)
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
                // 禁止用 dld.qzapp 作 baseURL：会被误判 isGameHost →「已进游戏页但未读到 skey」
                wv.loadHTMLString(LoginURLs.waitingHTML, baseURL: URL(string: "about:blank"))
            }
        }
        return wv
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 被 RootView 拆掉时尽快释放 WebContent（对齐开战让内存给 Ruffle）
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "dldWtloginProbe")
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
                        baseURL: URL(string: "about:blank")
                    )
                }
                // clear 异步期间可能已写入更新的 pendingURL（xlogin），优先用最新
                let loadURL = vm.pendingURL ?? next
                if let u = loadURL {
                    vm.pendingURL = nil
                    context.coordinator.applyUA(webView, desktop: vm.preferDesktopUA)
                    webView.load(URLRequest(url: u))
                }
            }
            return
        }

        if vm.loadWaitingPage {
            vm.loadWaitingPage = false
            webView.loadHTMLString(
                LoginURLs.waitingHTML,
                baseURL: URL(string: "about:blank")
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var vm: AppViewModel
        weak var webView: WKWebView?
        var lastReloadToken = 0
        var lastClearEpoch = 0
        var lastCookieInject = 0
        var defaultUA: String?
        private var captureTask: Task<Void, Never>?
        private var lastContinueURL = ""
        private var lastHandledCode = ""
        private var lastStuckRecoverAt: TimeInterval = 0

        /// E2：尽早钩住页内拼装的 wtlogin（对照官方 cb/字段）
        static let wtloginProbeJS = """
        (function(){
          if (window.__dldWtProbe) return; window.__dldWtProbe=1;
          function report(u, how){
            try {
              var s = String(u||'');
              if (!/^(wtlogin|mqq)/i.test(s)) return;
              var h = window.webkit && webkit.messageHandlers && webkit.messageHandlers.dldWtloginProbe;
              if (h) h.postMessage({how: String(how||''), url: s.substring(0, 2500)});
            } catch (e) {}
          }
          try {
            var _open = window.open;
            window.open = function(u){
              report(u, 'open');
              return _open ? _open.apply(this, arguments) : null;
            };
          } catch (e) {}
          try {
            var _assign = Location.prototype.assign;
            Location.prototype.assign = function(u){ report(u,'assign'); return _assign.call(this, u); };
            var _replace = Location.prototype.replace;
            Location.prototype.replace = function(u){ report(u,'replace'); return _replace.call(this, u); };
          } catch (e) {}
          try {
            var desc = Object.getOwnPropertyDescriptor(Location.prototype, 'href');
            if (desc && desc.set) {
              var rawSet = desc.set;
              Object.defineProperty(Location.prototype, 'href', {
                configurable: true,
                enumerable: desc.enumerable,
                get: desc.get,
                set: function(v){ report(v,'href'); return rawSet.call(this, v); }
              });
            }
          } catch (e) {}
        })();
        """

        /// 把 _blank / window.open 留在壳内；仅放行 qrcode= 的 wtlogin（p= → 授权失败）
        private let stayJS = """
        (function(){
          if (window.__dldStay4) return; window.__dldStay4=1;
          window.open=function(u){
            try{
              var s=String(u||'');
              if(/^(wtlogin|mqq)/i.test(s)){
                try {
                  var h = window.webkit && webkit.messageHandlers && webkit.messageHandlers.dldWtloginProbe;
                  if (h) h.postMessage({how:'stay_open', url:s.substring(0,2500)});
                } catch(e0){}
                if(/[?&]p=/i.test(s) && !/[?&]qrcode=/i.test(s)){ return null; }
                location.href=s; return null;
              }
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

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "dldWtloginProbe" else { return }
            let how: String
            let raw: String
            if let dict = message.body as? [String: Any] {
                how = (dict["how"] as? String) ?? "js"
                raw = (dict["url"] as? String) ?? ""
            } else if let s = message.body as? String {
                how = "js"
                raw = s
            } else {
                return
            }
            guard !raw.isEmpty else { return }
            AppViewModel.logWtloginRawProbe(source: "page_\(how)", raw: raw)
        }

        func applyUA(_ webView: WKWebView, desktop: Bool) {
            // 一键必须手机 UA：桌面 UA 会把 authorize 赶到无「一键登录」的扫码框
            if vm.loginMode == .oneKey {
                webView.customUserAgent = LoginURLs.iphoneUA
            } else {
                webView.customUserAgent = desktop ? LoginURLs.desktopUA : defaultUA
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in vm.onNavigated(to: webView.url) }
            webView.evaluateJavaScript(stayJS, completionHandler: nil)
            scheduleCookieCapture(webView)
            if vm.loginMode == .oneKey {
                if LoginURLs.isConnectMarketing(webView.url) {
                    // 等待/回壳收尾中忽略营销页；勿终态
                    if vm.oneKeyPhase == .waitingQQConfirm
                        || vm.oneKeyPhase == .loadingGame
                        || vm.oneKeyPhase == .syncingCookies {
                        AppViewModel.logOneKey("webview_marketing", "ignored_phase=\(vm.oneKeyPhase.rawValue)")
                    } else {
                        AppViewModel.logOneKey("webview_marketing", AppViewModel.sanitizeURLLog(webView.url))
                        vm.markOneKeyUnsupportedQuickLogin()
                    }
                } else if QqOneKeyLogin.isXloginPage(webView.url) {
                    vm.attachOneKeyFetcher(to: webView)
                }
            }
            webView.evaluateJavaScript(LoginURLs.qqLoginProbeJS) { [weak self] result, _ in
                guard let self else { return }
                let flag = (result as? String) ?? ""
                Task { @MainActor in
                    let now = Date().timeIntervalSince1970
                    guard now - self.lastStuckRecoverAt > 2.5 else { return }
                    // 原生一键进行中：忽略页内「qq」探测，避免误报终态
                    if flag == "qq", self.vm.loginMode == .oneKey, !self.vm.session.isLoggedIn {
                        self.lastStuckRecoverAt = now
                        AppViewModel.logOneKey("webview_qq_probe", "ignored_during_native")
                        return
                    }
                    guard self.vm.session.isLoggedIn, flag == "qq" else { return }
                    self.lastStuckRecoverAt = now
                    self.vm.recoverIfStuckOnQqLoginPage()
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

            // ② wtlogin：一键主路径已原生拉起；若网页仍发 scheme，只转发 qrcode=，拒绝 p=
            if QqOneKeyLogin.isWtloginScheme(scheme) {
                decisionHandler(.cancel)
                Task { @MainActor in
                    AppViewModel.logWtloginURLProbe(url, source: "nav")
                    AppViewModel.logOneKey("wtlogin_nav", AppViewModel.sanitizeURLLog(url))
                    if let ticket = QqOneKeyLogin.qrcodeTicket(fromWtlogin: url) {
                        _ = QqOneKeyLogin.openWithQrAuthorization(ticket, force: true)
                        self.vm.oneKeyFetcherMarkOpened()
                    } else {
                        AppViewModel.logOneKey("wtlogin_blocked", "no_qrcode_or_p")
                    }
                }
                return
            }

            if scheme == "http" || scheme == "https" {
                if vm.loginMode == .oneKey, LoginURLs.isConnectMarketing(url) {
                    // 收尾阶段：取消导航，由 onNavigated 拉回 xlogin
                    if vm.oneKeyPhase == .waitingQQConfirm
                        || vm.oneKeyPhase == .loadingGame
                        || vm.oneKeyPhase == .syncingCookies {
                        decisionHandler(.cancel)
                        Task { @MainActor in
                            AppViewModel.logOneKey("nav_marketing", "cancel_keep_phase")
                            self.vm.onNavigated(to: url)
                        }
                        return
                    }
                    decisionHandler(.cancel)
                    Task { @MainActor in
                        AppViewModel.logOneKey("nav_marketing", AppViewModel.sanitizeURLLog(url))
                        self.vm.markOneKeyUnsupportedQuickLogin()
                    }
                    return
                }
                // 一键：拦空 jump（授权失败页）
                if vm.loginMode == .oneKey,
                   (url.host ?? "").lowercased().contains("ptlogin2.qq.com"),
                   url.path.lowercased().contains("jump") {
                    decisionHandler(.cancel)
                    Task { @MainActor in
                        AppViewModel.logOneKey("nav_jump_blocked", AppViewModel.sanitizeURLLog(url))
                    }
                    return
                }
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

            // 其它非 http(s)：尝试系统打开并记日志（H1 证伪用）
            decisionHandler(.cancel)
            Task { @MainActor in
                AppViewModel.logOneKey("non_http_scheme", scheme)
                UIApplication.shared.open(url, options: [:]) { ok in
                    AppViewModel.logOneKey("open_scheme", "\(scheme) ok=\(ok)")
                }
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
            if QqOneKeyLogin.isWtloginScheme(scheme) {
                AppViewModel.logWtloginURLProbe(url, source: "create")
                AppViewModel.logOneKey("create_wtlogin", AppViewModel.sanitizeURLLog(url))
                if let ticket = QqOneKeyLogin.qrcodeTicket(fromWtlogin: url) {
                    _ = QqOneKeyLogin.openWithQrAuthorization(ticket, force: true)
                    Task { @MainActor in self.vm.oneKeyFetcherMarkOpened() }
                }
                return nil
            }
            if scheme == "http" || scheme == "https" {
                webView.load(URLRequest(url: url))
            } else {
                AppViewModel.logOneKey("create_non_http", scheme)
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
                // 扫码确认后的 continue；一键走 qrcode 回壳，不在此拼 jump
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
                let shouldWait = vm.loginMode == .scan || vm.loginMode == .oneKey
                    || LoginURLs.isGameHost(url)
                    || LoginURLs.isOauthLanding(url)
                let header: String
                if shouldWait {
                    header = await CookieBridge.waitForSkey(from: webView)
                } else {
                    header = await CookieBridge.readCookieHeader(from: webView)
                }
                if LoginURLs.hasGameSession(header) {
                    vm.onCookiesCaptured(header)
                } else if LoginURLs.isInGameShell(url), !vm.session.isLoggedIn {
                    // 仅 phonepk 真游戏壳；勿把 waitingHTML（曾误用 dld baseURL）当成已进游戏
                    await vm.syncSessionFromWebView(reason: "capture_game_shell")
                    if !vm.session.isLoggedIn, vm.loginMode == .idle || vm.loginMode == .oneKey {
                        vm.statusText = "已进游戏页，但未读到会话 Cookie。可试 Cookie"
                    }
                }
            }
        }
    }
}
