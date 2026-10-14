import Foundation
import SwiftUI
import WebKit

@MainActor
final class AppViewModel: ObservableObject {
    let session = SessionStore.shared
    /// 游戏壳 WebView，取 petpk Act 时合并其 Cookie（对齐 Android CookieManager）
    weak var gameWebView: WKWebView?

    @Published var statusText = ""
    @Published var showMenu = false
    @Published var showCookieSheet = false
    @Published var cookieDraft = ""
    @Published var cookieError = ""
    @Published var pendingURL: URL?
    @Published var loadWaitingPage = false
    @Published var webReloadToken = 0
    @Published var clearWebEpoch = 0
    /// 递增后：把 SessionStore Cookie 注入 WebView 再进游戏
    @Published var cookieInjectToken = 0
    @Published var currentURLString = ""
    @Published var titleHint = "大乐斗 MVP"
    @Published var qqLabel = ""
    @Published var loginMode: LoginMode = .idle
    @Published var preferDesktopUA = false
    /// 一键登录状态机（WebView xlogin 取票，对齐竞品）
    @Published private(set) var oneKeyPhase: OneKeyAuthPhase = .idle
    private var nativeQqLogin: NativeQqLogin?
    private var oneKeyFetcher: OneKeyTicketFetcher?
    private var oneKeyStartURLLog = ""
    private var oneKeyReturnBusy = false
    private var oneKeyRecoverAttempted = false
    private var oneKeyWebResumeBusy = false

    // 官方动画（viewfight）
    @Published var showViewFightFab = false
    @Published var viewFightLoading = false
    @Published var showReplay = false
    @Published var replayAct = ""
    @Published var replayId = ""
    /// 开战时卸掉游戏页，把内存让给 Ruffle（对齐 APK 独立 :ruffle 进程）
    @Published var suspendGameWebForReplay = false
    private var lastViewFightUrl: String?
    private var resumeGameURL: URL?

    func bootstrap() {
        if session.isLoggedIn {
            preferDesktopUA = false
            // 仅 skey 冷启动 inject；OpenID 会话冷启动无法还原 WK 原生态，走等待页让用户再一键
            if LoginURLs.hasRealSkey(session.cookieHeader) {
                cookieInjectToken &+= 1
                pendingURL = URL(string: LoginURLs.ledouEntry)
            } else {
                Self.logOneKey("bootstrap", "openid_only_need_relogin")
                loadWaitingPage = true
                statusText = "上次为 OpenID 会话，请再点「一键登录」"
            }
        } else {
            loadWaitingPage = true
        }
        refreshStatus()
    }

    func refreshStatus() {
        qqLabel = session.qq
        if session.isLoggedIn {
            let q = qqLabel.isEmpty ? "?" : qqLabel
            statusText = "已登录 QQ \(q)"
            titleHint = "大乐斗"
        } else {
            statusText = "未登录 · 一键登录 / 扫码 / Cookie"
            titleHint = "大乐斗 · 登录"
        }
    }

    /// 一键登录：先加载 style=35 xlogin → 页内取票+polling → 拉 QQ（竞品路径）。
    func openOneKeyLogin() {
        loginMode = .oneKey
        preferDesktopUA = false
        didEnterGameFromCapture = false
        QqOneKeyLogin.clearPending()
        session.clear()
        stopAllOneKey()
        oneKeyReturnBusy = false
        oneKeyRecoverAttempted = false
        oneKeyWebResumeBusy = false
        oneKeyPhase = .preflight
        Self.logOneKey("start", "webview_xlogin")
        statusText = "一键登录：打开授权页…"
        loadWaitingPage = false
        // 等拿到 xlogin 再 clear+load，避免 clear 异步把随后写入的 pendingURL 清掉

        oneKeyPhase = .fetchingTicket
        Task { @MainActor in
            let xlogin = await LoginURLs.resolveLiveXloginURL()
            guard loginMode == .oneKey else { return }
            clearWebEpoch &+= 1
            if let xlogin {
                oneKeyStartURLLog = Self.sanitizeURLLog(xlogin)
                Self.logOneKey("load_xlogin", oneKeyStartURLLog)
                statusText = "一键登录：授权页取票中…"
                pendingURL = xlogin
            } else {
                // 兜底：走 authorize（可能落到营销页则终态）
                Self.logOneKey("load_xlogin", "fallback_authorize")
                pendingURL = URL(string: LoginURLs.oneKeyLogin)
            }
        }
    }

    func attachOneKeyFetcher(to webView: WKWebView) {
        guard loginMode == .oneKey else { return }
        guard oneKeyPhase == .fetchingTicket || oneKeyPhase == .waitingQQConfirm else { return }
        guard QqOneKeyLogin.isXloginPage(webView.url) else { return }
        if oneKeyFetcher != nil { return }
        oneKeyPhase = .fetchingTicket
        Self.logOneKey("fetcher_start", Self.sanitizeURLLog(webView.url))
        let fetcher = OneKeyTicketFetcher(webView: webView) { [weak self] event in
            self?.handleFetcherEvent(event)
        }
        oneKeyFetcher = fetcher
        fetcher.start()
    }

    func oneKeyFetcherMarkOpened() {
        if oneKeyPhase == .fetchingTicket {
            oneKeyPhase = .waitingQQConfirm
        }
        oneKeyFetcher?.markOpenedQQ()
    }

    func stopOneKeyFetcher() {
        stopAllOneKey()
    }

    private func stopAllOneKey() {
        oneKeyFetcher?.cancel()
        oneKeyFetcher = nil
        nativeQqLogin?.cancel()
        nativeQqLogin = nil
    }

    private func stopNativeOneKey() {
        stopAllOneKey()
    }

    private func handleFetcherEvent(_ event: OneKeyTicketFetcher.Event) {
        switch event {
        case .status(let s):
            statusText = s
        case .openedQQ:
            oneKeyPhase = .waitingQQConfirm
            statusText = "QQ：倒计时→继续→同意→马上回 App（过期提示可忽略）"
        case .leftAuthPage:
            // 若已打开 QQ，可能是授权跳转；否则停取票
            if oneKeyPhase == .waitingQQConfirm {
                Self.logOneKey("left_xlogin", "after_qq_open")
            } else {
                stopAllOneKey()
                oneKeyPhase = .fetchingTicket
            }
        case .ticketFailed:
            failOneKey("取票失败，请用扫码或 Cookie 登录")
        case .cannotOpenQQ:
            failOneKey("无法打开 QQ，请确认已安装后用扫码或 Cookie")
        case .timeout:
            failOneKey("一键登录超时，请用扫码或 Cookie 登录")
        case .loginLikelyDone:
            // 离开 xlogin 多半在走 OAuth 跳转；禁止立刻 phonepk 掐掉 index.php?code=
            oneKeyPhase = .loadingGame
            statusText = "授权跳转中，等待写入 Cookie…"
            Task { @MainActor in
                await waitForOauthCookiesThenEnter(reason: "left_xlogin")
            }
        }
    }

    /// connect「亿万用户」：主路径不应再出现；若仍命中只记日志+终态，不循环
    func markOneKeyUnsupportedQuickLogin(reason: String = "当前环境不支持 QQ 快速登录") {
        guard loginMode == .oneKey else { return }
        if oneKeyPhase == .waitingQQConfirm || oneKeyPhase == .syncingCookies || oneKeyPhase == .loadingGame {
            Self.logOneKey("marketing_ignored", reason)
            return
        }
        if oneKeyPhase == .unsupportedQuickLogin || oneKeyPhase == .failed { return }
        stopAllOneKey()
        oneKeyPhase = .unsupportedQuickLogin
        Self.logOneKey("unsupported_quick_login", reason)
        statusText = "\(reason)。请用「扫码登陆」或「Cookie」"
        loginMode = .idle
    }

    func bounceOneKeyToLiveXlogin(reason: String = "离开营销页") {
        markOneKeyUnsupportedQuickLogin(reason: "一键登录不可用（\(reason)）")
    }

    func bounceOneKeyToPhonepk(reason: String = "离开营销页") {
        markOneKeyUnsupportedQuickLogin(reason: "一键登录不可用（\(reason)）")
    }

    private func handleNativeOneKeyEvent(_ event: NativeQqLogin.Event) {
        switch event {
        case .status(let s):
            statusText = s
            // 原生错过 code=0 时会提示页内续票
            if s.contains("页内续票") {
                Task { @MainActor in await resumeOneKeyInWebView() }
            }
        case .openedQQ:
            oneKeyPhase = .waitingQQConfirm
            // 禁止在此加载 xlogin：页内会重新 ptqrshow，把 QQ 里正在授权的票作废 →「二维码已过期」
            statusText = "QQ：等倒计时→继续→同意，然后立刻返回"
            Task { @MainActor in await seedOneKeyCookiesOnly() }
        case .succeeded(let cookies):
            let cookiesCopy = cookies
            stopNativeOneKey()
            Task { @MainActor in
                await applyNativeCookiesAndEnterGame(cookiesCopy)
            }
        case .failed(let message):
            failOneKey(message)
        }
    }

    /// 只注入 Cookie，不打开 xlogin（避免页内重新取票作废当前 QQ 授权）
    private func seedOneKeyCookiesOnly() async {
        guard let native = nativeQqLogin, let wv = gameWebView else { return }
        let cookies = native.ticketCookies
        guard !cookies.isEmpty else { return }
        Self.logOneKey(
            "web_backup",
            "cookies_only names=\(cookies.map(\.name).sorted().joined(separator: ","))"
        )
        await CookieBridge.restore(cookies, into: wv)
    }

    /// 回壳：在 xlogin 上执行 resume（polling + qlogin_submit）
    private func resumeOneKeyInWebView() async {
        guard !oneKeyWebResumeBusy else { return }
        oneKeyWebResumeBusy = true
        defer { oneKeyWebResumeBusy = false }
        guard let wv = gameWebView else { return }
        if let native = nativeQqLogin, !native.ticketCookies.isEmpty {
            await CookieBridge.restore(native.ticketCookies, into: wv)
        }
        if let xlogin = nativeQqLogin?.backupXloginURL,
           !QqOneKeyLogin.isXloginPage(wv.url) {
            pendingURL = xlogin
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        guard QqOneKeyLogin.isXloginPage(wv.url) || nativeQqLogin?.backupXloginURL != nil else {
            Self.logOneKey("web_resume", "not_on_xlogin")
            return
        }
        statusText = "页内续票中…"
        Self.logOneKey("web_resume", "js")
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            wv.evaluateJavaScript(QqOneKeyLogin.jsResumeAfterQQ) { _, _ in
                cont.resume()
            }
        }
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            wv.evaluateJavaScript(QqOneKeyLogin.jsKeepPolling) { _, _ in
                cont.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let header = await CookieBridge.waitForSkey(from: wv, attempts: 10, gapMs: 400)
        if LoginURLs.hasGameSession(header) {
            oneKeyPhase = .succeeded
            onCookiesCaptured(header)
            return
        }
        // 再走 authorize 尾段
        pendingURL = URL(string: LoginURLs.oneKeyLogin)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let h2 = await CookieBridge.waitForSkey(from: wv, attempts: 8, gapMs: 400)
        if LoginURLs.hasGameSession(h2) {
            oneKeyPhase = .succeeded
            onCookiesCaptured(h2)
        }
    }

    private func applyNativeCookiesAndEnterGame(_ cookies: [HTTPCookie]) async {
        oneKeyPhase = .syncingCookies
        statusText = "正在同步 Cookie…"
        Self.logOneKey(
            "sync_cookies",
            "names=" + cookies.map(\.name).sorted().joined(separator: ",")
        )
        let header = cookies
            .map { "\($0.name)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
        if let wv = gameWebView {
            await CookieBridge.restore(cookies, into: wv)
            // 再按粘贴路径写 .qq.com，保证 authorize/phonepk 能带上
            await CookieBridge.inject(cookieHeader: header, into: wv)
        }
        if LoginURLs.hasGameSession(header) {
            session.save(cookieHeader: header)
        }

        oneKeyPhase = .loadingGame
        statusText = "正在完成授权并进入游戏…"
        preferDesktopUA = false
        // 先走 authorize 尾段，让游戏站点种会话；再兜底 phonepk
        pendingURL = URL(string: LoginURLs.oneKeyLogin)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard loginMode == .oneKey, !session.isLoggedIn else {
            if session.isLoggedIn { oneKeyPhase = .succeeded }
            return
        }
        if let wv = gameWebView {
            let h = await CookieBridge.waitForSkey(from: wv, attempts: 8, gapMs: 400)
            if LoginURLs.hasGameSession(h) {
                oneKeyPhase = .succeeded
                onCookiesCaptured(h)
                return
            }
        }
        pendingURL = URL(string: LoginURLs.ledouEntry)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard loginMode == .oneKey, !session.isLoggedIn else {
            if session.isLoggedIn { oneKeyPhase = .succeeded }
            return
        }
        if let wv = gameWebView {
            let h = await CookieBridge.waitForSkey(from: wv, attempts: 8, gapMs: 400)
            if LoginURLs.hasGameSession(h) {
                oneKeyPhase = .succeeded
                onCookiesCaptured(h)
                return
            }
        }
        failOneKey("未建立游戏会话，请用扫码或 Cookie 登录")
    }

    private func failOneKey(_ message: String) {
        stopAllOneKey()
        oneKeyPhase = .failed
        statusText = message
        loginMode = .idle
        Self.logOneKey("failed", message)
    }

    /// 脱敏导航日志：仅 host + path（无 query/Cookie）
    static func sanitizeURLLog(_ url: URL?) -> String {
        guard let u = url else { return "(nil)" }
        let host = u.host ?? ""
        let path = u.path
        return "\(host)\(path)"
    }

    static func logOneKey(_ event: String, _ detail: String) {
        #if DEBUG
        print("[OneKey] \(event) \(detail)")
        #endif
        // Release 也写一行短状态，便于真机侧载排查（不含密钥）
        NSLog("[OneKey] %@ %@", event, detail)
        // 落盘 Documents，文件 App / iTunes 可取 onekey_last.txt
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(event) \(detail)\n"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("onekey_last.txt")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// GameWebView 主框架导航时调用（脱敏）
    func noteOneKeyNavigation(to url: URL?) {
        guard loginMode == .oneKey || oneKeyPhase != .idle else { return }
        Self.logOneKey("nav", Self.sanitizeURLLog(url))
    }

    /// 扫码登陆（壳内展示二维码，与一键分流）
    func openScanLogin() {
        loginMode = .scan
        preferDesktopUA = true
        stopNativeOneKey()
        oneKeyPhase = .idle
        QqOneKeyLogin.clearPending()
        session.clear()
        clearWebEpoch &+= 1
        statusText = "扫码登陆中…用手机 QQ 扫页面二维码"
        pendingURL = URL(string: LoginURLs.scanLedou)
    }

    func openCookieLoginSheet() {
        cookieDraft = session.cookieHeader
        cookieError = ""
        showCookieSheet = true
    }

    /// 粘贴 Cookie（须含 skey），写入 Keychain + WebView
    func applyPastedCookie() {
        let header = Self.normalizeCookieHeader(cookieDraft)
        guard LoginURLs.hasRealSkey(header) else {
            cookieError = "无效：未找到 skey。请粘贴完整 Cookie（至少含 skey=…）"
            statusText = "Cookie 无效"
            return
        }
        cookieError = ""
        session.save(cookieHeader: header)
        loginMode = .idle
        preferDesktopUA = false
        showCookieSheet = false
        cookieInjectToken &+= 1
        pendingURL = URL(string: LoginURLs.ledouEntry)
        refreshStatus()
        statusText = "Cookie 已写入，进入游戏…"
    }

    func openGameHome() {
        forceEnterGame()
    }

    func reload() {
        webReloadToken &+= 1
    }

    func handleOpenURL(_ url: URL) {
        guard QqOneKeyLogin.isOurCallback(url) || LoginURLs.isCallbackScheme(url.scheme) else { return }
        Self.logOneKey("callback", url.scheme ?? "?")
        if let code = LoginURLs.oauthCode(from: url),
           let finish = LoginURLs.finishWithCode(code) {
            QqOneKeyLogin.markReturned()
            loginMode = .oneKey
            oneKeyPhase = .loadingGame
            preferDesktopUA = false
            statusText = "已从 QQ 返回（code），正在写入会话…"
            pendingURL = finish
            return
        }
        QqOneKeyLogin.markReturned()
        loginMode = .oneKey
        if let https = QqOneKeyLogin.continueURL(fromCallback: url),
           (https.scheme == "http" || https.scheme == "https"),
           !https.path.lowercased().contains("jump") {
            oneKeyPhase = .loadingGame
            statusText = "已从 QQ 返回，正在完成授权…"
            pendingURL = https
            return
        }
        statusText = "已回 App，正在确认授权…"
        oneKeyFetcher?.resumeAfterQQ()
        finishOneKeyAfterQQReturn()
    }

    /// 回壳：页内 resume + 读 skey（竞品需手动刷新，这里自动化）
    func onAppBecameActive() {
        guard !session.isLoggedIn else { return }
        let oneKeyPending = loginMode == .oneKey
            || oneKeyPhase == .waitingQQConfirm
            || oneKeyPhase == .loadingGame
            || QqOneKeyLogin.awaitingReturn
            || QqOneKeyLogin.launchedQrcode != nil
        guard oneKeyPending else { return }
        // 回到前台时确保仍按一键收尾
        if loginMode != .oneKey { loginMode = .oneKey }
        oneKeyFetcher?.resumeAfterQQ()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !session.isLoggedIn else { return }
            finishOneKeyAfterQQReturn()
        }
    }

    private func finishOneKeyAfterQQReturn() {
        guard !oneKeyReturnBusy else { return }
        if oneKeyPhase == .succeeded, session.isLoggedIn { return }
        oneKeyReturnBusy = true
        QqOneKeyLogin.markReturned()
        oneKeyPhase = .loadingGame
        statusText = "已回 App，等待授权落 Cookie…（过期提示可忽略）"
        Self.logOneKey("recover", "webview_resume phase=\(oneKeyPhase.rawValue)")
        oneKeyFetcher?.resumeAfterQQ()
        Task { @MainActor in
            defer { oneKeyReturnBusy = false }
            if let wv = gameWebView {
                _ = await evalJS(QqOneKeyLogin.jsFreezeQr, in: wv)
                _ = await evalJS(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
                _ = await evalJS(QqOneKeyLogin.jsKeepPolling, in: wv)
            }
            // 关键：先等 OAuth（index.php?code=）自己跑完种 skey，再进 phonepk
            await waitForOauthCookiesThenEnter(reason: "return_from_qq")
        }
    }

    /// 回壳：先 resume 几秒让 OAuth 落 Cookie；仍无 skey 再进 phonepk（fd61 能进游戏，fd62 空等会卡死）。
    private func waitForOauthCookiesThenEnter(reason: String) async {
        Self.logOneKey("oauth_wait", reason)
        preferDesktopUA = false
        statusText = "等待登录 Cookie…（可点左上角回 App）"

        // 阶段 A：约 5s 只 resume，不打断可能的 index.php?code=
        for i in 0..<5 {
            if session.isLoggedIn { return }
            if let wv = gameWebView {
                if i == 0 || i == 4 {
                    let diag = await CookieBridge.cookieNameDomainLog(from: wv)
                    Self.logOneKey("oauth_cookies", "t=\(i) \(diag)")
                }
                if QqOneKeyLogin.isXloginPage(wv.url) {
                    _ = await evalJS(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
                    _ = await evalJS(QqOneKeyLogin.jsKeepPolling, in: wv)
                }
            }
            await syncSessionFromWebView(reason: "oauth_poll_\(i)")
            if session.isLoggedIn { return }
            // 已在 phonepk：继续采 Cookie，勿再改 URL
            if LoginURLs.isInGameShell(URL(string: currentURLString)) {
                break
            }
            // 已在 oauth 落地页：再多等一会
            if LoginURLs.isOauthLanding(URL(string: currentURLString)) {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await syncSessionFromWebView(reason: "oauth_landing_\(i)")
                if session.isLoggedIn { return }
                continue
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        if session.isLoggedIn { return }

        // 阶段 B：推进游戏首页（用户手动回 App 后的可用路径）
        Self.logOneKey("oauth_wait", "push_phonepk")
        statusText = "正在进入游戏…"
        if !LoginURLs.isInGameShell(URL(string: currentURLString)) {
            pendingURL = URL(string: LoginURLs.ledouEntry)
        }
        for i in 0..<12 {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await syncSessionFromWebView(reason: "phonepk_poll_\(i)")
            if session.isLoggedIn { return }
            if let wv = gameWebView, QqOneKeyLogin.isXloginPage(wv.url) {
                _ = await evalJS(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
            }
        }
        if !session.isLoggedIn {
            let names: String
            if let wv = gameWebView {
                names = await CookieBridge.cookieNameDomainLog(from: wv)
            } else {
                names = "(no-wv)"
            }
            Self.logOneKey("oauth_fail", "names=\(names)")
            // 保持 oneKey，便于用户再点菜单；勿假装 idle 成功
            statusText = "未读到 skey（\(cookieNamesShort(names))）。可扫码或 Cookie"
        }
    }

    private func cookieNamesShort(_ diag: String) -> String {
        let names = diag.split(separator: ",").prefix(8).joined(separator: ",")
        return names.isEmpty ? "无" : names
    }

    private func evalJS(_ script: String, in webView: WKWebView) async -> Any? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: result)
            }
        }
    }

    func onNavigated(to url: URL?) {
        currentURLString = url?.absoluteString ?? ""
        noteOneKeyNavigation(to: url)

        if loginMode == .scan,
           let s = url?.absoluteString,
           let cont = LoginURLs.continueAuthorizeUrl(xloginUrl: s),
           let u = URL(string: cont) {
            statusText = "扫码已确认，继续授权…"
            pendingURL = u
            return
        }

        if LoginURLs.isConnectMarketing(url) {
            if loginMode == .oneKey {
                markOneKeyUnsupportedQuickLogin(reason: "当前应用不支持 QQ 快速登录")
                return
            }
            if loginMode == .scan {
                statusText = "误入 QQ 互联首页，请重新扫码登陆"
                pendingURL = URL(string: LoginURLs.scanLedou)
                return
            }
        }

        if loginMode == .oneKey || oneKeyPhase == .loadingGame || oneKeyPhase == .waitingQQConfirm {
            if LoginURLs.isOauthLanding(url) {
                statusText = "正在完成授权回调…"
                Self.logOneKey("nav_oauth", Self.sanitizeURLLog(url))
                // 让 index.php?code= 自己跑完，勿在此改 pendingURL
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await syncSessionFromWebView(reason: "nav_oauth_landing")
                }
            }
        }

        if LoginURLs.isInGameShell(url) {
            if !session.isLoggedIn {
                Task { @MainActor in await syncSessionFromWebView(reason: "nav_game_shell") }
            } else {
                let q = qqLabel.isEmpty ? (session.qq.isEmpty ? "?" : session.qq) : qqLabel
                statusText = "已登录 QQ \(q)"
                titleHint = "大乐斗"
                preferDesktopUA = false
                loginMode = .idle
                oneKeyPhase = .succeeded
            }
        }

        updateViewFightFab(for: currentURLString)
    }

    /// 从 WKWebView Cookie 补写 SessionStore（一键回壳后常见「进了游戏但未 isLoggedIn」）
    func syncSessionFromWebView(reason: String) async {
        guard let wv = gameWebView else { return }
        let header = await CookieBridge.readCookieHeader(from: wv)
        let diag = await CookieBridge.cookieNameDomainLog(from: wv)
        if LoginURLs.hasGameSession(header) {
            let kind = LoginURLs.hasRealSkey(header) ? "skey" : "openid"
            Self.logOneKey("sync_session", "\(reason) ok kind=\(kind) names=\(cookieNames(header))")
            onCookiesCaptured(header)
            return
        }
        // 有 newuin 但缺 openId/skey：只记日志，不误报「已进游戏」
        if let qq = LoginURLs.extractQq(header), !qq.isEmpty {
            Self.logOneKey("sync_session", "\(reason) uin_only qq=\(qq) diag=\(diag)")
        } else {
            Self.logOneKey("sync_session", "\(reason) miss diag=\(diag)")
        }
    }

    private func cookieNames(_ header: String) -> String {
        header.split(separator: ";")
            .compactMap { pair -> String? in
                let p = pair.trimmingCharacters(in: .whitespaces)
                guard let eq = p.firstIndex(of: "=") else { return nil }
                return String(p[..<eq])
            }
            .sorted()
            .joined(separator: ",")
    }

    private func updateViewFightFab(for urlString: String) {
        if LoginURLs.isViewFightUrl(urlString) {
            lastViewFightUrl = urlString
            showViewFightFab = true
        } else {
            // 离开战报页则隐藏（拼接页暂不做）
            showViewFightFab = false
        }
    }

    /// 乐斗过程页 → 取 Act → 打开官方动画
    func openOfficialAnimation() {
        let page = lastViewFightUrl ?? currentURLString
        guard LoginURLs.isViewFightUrl(page) else {
            statusText = "请先打开「查看乐斗过程」"
            return
        }
        guard !viewFightLoading else { return }
        viewFightLoading = true
        statusText = "正在获取战斗数据…"
        Task { @MainActor in
            // 一键后可能 WebView 已有会话而 SessionStore 未写：先补同步
            if !session.isLoggedIn {
                await syncSessionFromWebView(reason: "official_anim")
            }
            var cookie = session.cookieHeader
            if let wv = gameWebView {
                let web = await CookieBridge.readCookieHeader(from: wv)
                cookie = Self.mergeCookieHeaders(cookie, web)
                if LoginURLs.hasGameSession(cookie) {
                    session.save(cookieHeader: cookie)
                    if !session.isLoggedIn {
                        onCookiesCaptured(cookie)
                    }
                }
            }
            guard LoginURLs.hasGameSession(cookie) else {
                viewFightLoading = false
                statusText = "请先登录再看官方动画"
                Self.logOneKey("anim_no_skey", "names=\(cookieNames(cookie))")
                return
            }
            // 无 skey 时 Act 拉取可能失败，仍用 OpenID Cookie 试一次
            if !LoginURLs.hasRealSkey(cookie) {
                Self.logOneKey("anim_openid", "names=\(cookieNames(cookie))")
            }
            let result = await FightActFetcher.fetch(pageUrl: page, cookieHeader: cookie)
            if result.act.isEmpty {
                viewFightLoading = false
                statusText = "打开动画失败: \(result.errMsg)"
                return
            }
            replayAct = result.act
            replayId = FightActFetcher.replayId(from: page)
            // 对齐 Android：开战前预取官方专精 JSON（武器/专精面板）
            WeaponSpeReplayCache.captureFromAct(result.act)
            let rid = replayId
            let cookieForSpe = cookie
            Task.detached(priority: .utility) {
                await WeaponSpeReplayCache.prefetchOfficial(replayId: rid, cookieHeader: cookieForSpe)
            }
            // 先拆游戏页，再下载/ZWS→FWS：预解压峰值(~70MB)不要和游戏 WebContent 叠峰
            statusText = "释放游戏页内存…"
            resumeGameURL = gameWebView?.url
            if let wv = gameWebView {
                wv.stopLoading()
                wv.navigationDelegate = nil
                wv.uiDelegate = nil
            }
            gameWebView = nil
            suspendGameWebForReplay = true
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            URLCache.shared.removeAllCachedResponses()

            let preferMm = ActionPackPrefetch.preferMm(from: result.act)
            do {
                try await ActionPackPrefetch.ensure(preferMm: preferMm) { msg in
                    self.statusText = msg
                }
            } catch {
                statusText = "动作包下载失败，仍尝试播放: \(error.localizedDescription)"
            }
            // 专精预取再给一点时间（与动作包并行）
            statusText = "同步武器专精…"
            let speDiag = await WeaponSpeReplayCache.prefetchOfficial(replayId: rid, cookieHeader: cookieForSpe)
            viewFightLoading = false
            statusText = WeaponSpeReplayCache.hasOfficialSpecialize()
                ? "已取到战斗数据+专精，打开官方动画"
                : "已取到战斗数据（专精\(speDiag)），打开官方动画"
            showReplay = true
        }
    }

    func onReplayDismissed() {
        showReplay = false
        // fd26：必须 destroy 动画 WebContent，再重建游戏页。
        // 若只 park 暖挂，双 WebContent 叠峰 → jetsam → 直接回桌面。
        statusText = "释放动画内存…"
        RuffleWarmHolder.shared.destroy()
        let resume = resumeGameURL ?? (session.isLoggedIn ? URL(string: LoginURLs.ledouEntry) : nil)
        resumeGameURL = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            statusText = "正在返回游戏…"
            pendingURL = resume
            suspendGameWebForReplay = false
            try? await Task.sleep(nanoseconds: 800_000_000)
            if statusText == "正在返回游戏…" {
                statusText = ""
            }
        }
    }

    /// 合并两段 Cookie，后者同名覆盖前者
    static func mergeCookieHeaders(_ a: String, _ b: String) -> String {
        var map: [String: String] = [:]
        for raw in [a, b] {
            for part in raw.split(separator: ";") {
                let s = part.trimmingCharacters(in: .whitespaces)
                guard let eq = s.firstIndex(of: "=") else { continue }
                let name = String(s[..<eq])
                let val = String(s[s.index(after: eq)...])
                guard !name.isEmpty, !val.isEmpty else { continue }
                map[name] = val
            }
        }
        return map.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
    }

    /// 本次启动是否已因捕获 Cookie 跳进过游戏（防反复 pendingURL）
    private var didEnterGameFromCapture = false

    func onCookiesCaptured(_ header: String) {
        guard LoginURLs.hasGameSession(header) else { return }
        session.save(cookieHeader: header)
        loginMode = .idle
        oneKeyPhase = .succeeded
        preferDesktopUA = false
        if let extracted = LoginURLs.extractQq(header), !extracted.isEmpty {
            qqLabel = extracted
        }
        let showQq = qqLabel.isEmpty ? "?" : qqLabel
        titleHint = "大乐斗"
        let hasSkey = LoginURLs.hasRealSkey(header)
        let kindHint = hasSkey ? "" : "（OpenID）"
        let inShell = LoginURLs.isInGameShell(URL(string: currentURLString))
        // 已在 phonepk：只落库，禁止 reinject/reload（会冲掉 WK 原生 OAuth Cookie → 页内「未登录」）
        if inShell {
            didEnterGameFromCapture = true
            statusText = "已登录 QQ \(showQq)\(kindHint)"
            Self.logOneKey("enter_game", "already_shell kind=\(hasSkey ? "skey" : "openid")")
            return
        }
        guard !didEnterGameFromCapture else {
            statusText = "已登录 QQ \(showQq)\(kindHint)"
            return
        }
        didEnterGameFromCapture = true
        statusText = "已登录 QQ \(showQq)\(kindHint) · 正在进入游戏…"
        if hasSkey {
            // 粘贴/扫码 skey：需要 inject 再进壳
            forceEnterGame()
        } else {
            // OpenID：保留 WebView 已有 Cookie，只跳 phonepk，勿 cookieInject
            Self.logOneKey("enter_game", "soft_phonepk openid")
            pendingURL = URL(string: LoginURLs.ledouEntry)
        }
    }

    /// 注入 Cookie 并强制打开手机端首页（扫码 / skey 粘贴后用）
    func forceEnterGame() {
        preferDesktopUA = false
        loginMode = .idle
        statusText = "正在进入游戏…"
        cookieInjectToken &+= 1
        pendingURL = URL(string: LoginURLs.ledouEntry)
    }

    /// 页面探测仍是 QQ 登录页，但本地已有 Cookie → 再推一次进游戏
    func recoverIfStuckOnQqLoginPage() {
        guard session.isLoggedIn else { return }
        if LoginURLs.isInGameShell(URL(string: currentURLString)) { return }
        statusText = "检测到仍在 QQ 登录页，强制进入游戏…"
        forceEnterGame()
    }

    func logout() {
        stopNativeOneKey()
        oneKeyPhase = .idle
        oneKeyRecoverAttempted = false
        QqOneKeyLogin.clearPending()
        session.clear()
        loginMode = .idle
        preferDesktopUA = false
        cookieDraft = ""
        didEnterGameFromCapture = false
        showViewFightFab = false
        showReplay = false
        viewFightLoading = false
        lastViewFightUrl = nil
        clearWebEpoch &+= 1
        loadWaitingPage = true
        pendingURL = nil
        refreshStatus()
        statusText = "已退出"
    }

    /// 支持 `a=1; b=2`、换行、`Cookie: ` 前缀
    static func normalizeCookieHeader(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("cookie:") {
            s = String(s.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\n", with: "; ")
        s = s.replacingOccurrences(of: "\t", with: " ")
        while s.contains("; ;") { s = s.replacingOccurrences(of: "; ;", with: "; ") }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
