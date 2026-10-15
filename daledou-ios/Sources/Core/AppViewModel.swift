import Foundation
import SwiftUI
import UIKit
import WebKit

@MainActor
final class AppViewModel: ObservableObject {
    let session = SessionStore.shared
    /// 游戏壳 WebView，取 petpk Act 时合并其 Cookie（对齐 Android CookieManager）
    weak var gameWebView: WKWebView?

    @Published var statusText = ""
    @Published var showMenu = false
    @Published var showCookieSheet = false
    /// 根壳四席 Tab：0首页 1日志 2记录 3我的（对齐 AppRootScaffold）
    @Published var shellTab = 0
    @Published var showShellMenu = false
    @Published var showAbout = false
    @Published var showHuoYue = false
    @Published var showLingJiang = false
    @Published var showDaiWan = false
    /// 悬浮钮「代玩-记录」
    @Published var showDaiWanRecord = false
    /// 后台监听页：kuangdong / jiebiao / liangcao / wending / fuchou_wending / open_kd
    @Published var showListenFeature = false
    @Published var listenFeatureId = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    /// 页加载中：顶栏刷新位转圈（对齐 APK，无全屏/顶栏进度条）
    @Published var pageLoading = false
    /// 后台开关 UI（Worker 未接，仅落盘）
    @Published var backgroundEnabled: Bool = UserDefaults.standard.bool(forKey: "daledou.shell.bg_enabled") {
        didSet { UserDefaults.standard.set(backgroundEnabled, forKey: "daledou.shell.bg_enabled") }
    }
    @Published var backgroundIntervalSec: Int = {
        let v = UserDefaults.standard.integer(forKey: "daledou.shell.bg_interval")
        return v > 0 ? v : 10
    }()

    var shellDisplayName: String {
        if session.isLoggedIn {
            let q = qqLabel.isEmpty ? session.qq : qqLabel
            return q.isEmpty ? "已登陆" : "QQ \(q)"
        }
        return "未登陆"
    }

    var shellVipLabel: String {
        session.isLoggedIn ? "会员状态：待接 APK" : ""
    }
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
    /// 单飞：避免 left_xlogin 与 return_from_qq 并发 wait/push_phonepk 互抢
    private var oauthWaitGeneration = 0

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

    private var foregroundObserversInstalled = false
    /// RootView.onAppear 会在回前台时再触发；只允许真正冷启动跑一次
    private var didBootstrap = false

    func bootstrap() {
        installForegroundObservers()
        // 回 QQ/前台导致 onAppear 重入时禁止再走「杀进程恢复」——会冲掉进行中的一键
        if didBootstrap {
            Self.logOneKey("bootstrap", "skip_reappear mode=\(loginMode.rawValue) phase=\(oneKeyPhase.rawValue)")
            return
        }
        didBootstrap = true
        BackgroundListenRunner.shared.restoreFromStore()

        // 进程在 QQ 期间被杀：用落盘的 qrsig 恢复一键，等用户回 App 再收尾
        if QqOneKeyLogin.persistedAwaitingReturn {
            let cookies = QqOneKeyLogin.loadPersistedCookies()
            let hasQrsig = cookies.contains { $0.name.lowercased() == "qrsig" && !$0.value.isEmpty }
            if hasQrsig {
                Self.logOneKey("bootstrap", "qq_kill_restore n=\(cookies.count)")
                loginMode = .oneKey
                oneKeyPhase = .waitingQQConfirm
                preferDesktopUA = false
                statusText = "授权可能已完成：请从 QQ 点左上角 ◀ 回大乐斗（勿再点同意）"
                let loginURL = QqOneKeyLogin.persistedLoginURL
                QqOneKeyLogin.markRestoredAwaitingReturn(cookies: cookies, loginURL: loginURL)
                Task { @MainActor in
                    if let saved = loginURL {
                        pendingURL = saved
                    } else if let x = await LoginURLs.resolveLiveXloginURL() {
                        pendingURL = x
                    }
                    for _ in 0..<25 {
                        if let wv = gameWebView {
                            await CookieBridge.restore(cookies, into: wv)
                            OneKeyCheckSigCompleter.startBackgroundHarvest(from: wv)
                            Self.logOneKey("bootstrap", "restore_cookies_ok")
                            break
                        }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                refreshStatus()
                return
            }
            Self.logOneKey("bootstrap", "qq_kill_need_retry no_qrsig")
            QqOneKeyLogin.clearPersistedLaunchSession()
            loadWaitingPage = true
            statusText = "上次一键被中断，请重新点「一键登录」"
            refreshStatus()
            return
        }

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

    /// UIKit 前台通知：比 scenePhase 更稳（QQ 回壳常漏 scene onChange）
    func installForegroundObservers() {
        guard !foregroundObserversInstalled else { return }
        foregroundObserversInstalled = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onAppBecameActive() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onAppBecameActive() }
        }
        Self.logOneKey("observers", "foreground_installed")
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
        OneKeyCheckSigCompleter.clearPending()
        session.clear()
        stopAllOneKey()
        oneKeyReturnBusy = false
        oneKeyRecoverAttempted = false
        oneKeyWebResumeBusy = false
        oauthWaitGeneration &+= 1
        oneKeyPhase = .preflight
        Self.resetOneKeyLogFile()
        OneKeyReturnNotifier.resetSession()
        OneKeyReturnNotifier.requestPermissionIfNeeded()
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        Self.logOneKey("start", "webview_xlogin build=\(build)")
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

    /// 顶栏提示条样式：等 QQ 回壳用醒目色
    enum OneKeyBannerKind {
        case none, info, warn, progress, success, danger
    }

    var oneKeyBannerKind: OneKeyBannerKind {
        guard loginMode == .oneKey || oneKeyPhase == .waitingQQConfirm else {
            if oneKeyPhase == .failed || oneKeyPhase == .unsupportedQuickLogin { return .danger }
            return .none
        }
        switch oneKeyPhase {
        case .waitingQQConfirm:
            return .warn
        case .fetchingTicket, .preflight, .syncingCookies, .loadingGame:
            return .progress
        case .succeeded:
            return .success
        case .failed, .unsupportedQuickLogin:
            return .danger
        case .idle:
            return .none
        }
    }

    func attachOneKeyFetcher(to webView: WKWebView) {
        guard loginMode == .oneKey else { return }
        // 仅取票阶段挂 Fetcher。waitingQQConfirm（含杀进程恢复）禁止再挂，否则会再次 open QQ → 闪退
        guard oneKeyPhase == .fetchingTicket else { return }
        guard QqOneKeyLogin.isXloginPage(webView.url) else { return }
        if oneKeyFetcher != nil { return }
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
        OneKeyCheckSigCompleter.clearPending()
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
            statusText = "已打开 QQ：点一次「同意」后，立刻点左上角 ◀ 回大乐斗（勿反复点同意）"
            // 进程常被杀，poll 来不及：先预约本地通知催返回
            OneKeyReturnNotifier.scheduleReturnRemindersAfterOpenQQ()
            // 同意瞬间收 skey（回壳再 poll 多为 65）
            if let wv = gameWebView {
                OneKeyCheckSigCompleter.startBackgroundHarvest(from: wv)
            }
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
            // 离开 xlogin 多半在走 OAuth；若已在回壳收尾则勿再开第二路 wait
            oneKeyPhase = .loadingGame
            statusText = "授权跳转中，等待写入 Cookie…"
            if oneKeyReturnBusy {
                Self.logOneKey("left_xlogin", "skip_wait_return_busy")
                return
            }
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
            statusText = "已打开 QQ：点一次「同意」后立刻点左上角 ◀ 返回（勿反复点同意）"
            OneKeyReturnNotifier.scheduleReturnRemindersAfterOpenQQ()
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
    nonisolated static func sanitizeURLLog(_ url: URL?) -> String {
        guard let u = url else { return "(nil)" }
        let host = u.host ?? ""
        let path = u.path
        return "\(host)\(path)"
    }

    /// E2：记录页/导航里完整 wtlogin query 结构（不含 qrcode 明文）
    nonisolated static func logWtloginURLProbe(_ url: URL, source: String) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let keys = items.map(\.name).sorted().joined(separator: ",")
        let cb = items.first(where: { $0.name.lowercased() == "schemacallback" })?.value ?? "(none)"
        let hasQr = items.contains { $0.name.lowercased() == "qrcode" }
        let hasP = items.contains { $0.name.lowercased() == "p" }
        let extra = items
            .filter {
                let n = $0.name.lowercased()
                return n != "qrcode" && n != "p" && n != "schemacallback"
            }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let extraClip = extra.count > 180 ? String(extra.prefix(180)) + "…" : extra
        logOneKey(
            "wtlogin_probe",
            "src=\(source) scheme=\(url.scheme ?? "?") keys=[\(keys)] cb=\(cb) qr=\(hasQr) p=\(hasP) extra=\(extraClip)"
        )
    }

    /// E2：从 JS message 收到的原始 wtlogin 串
    nonisolated static func logWtloginRawProbe(source: String, raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s) ?? (NSURL(string: s) as URL?) else {
            logOneKey("wtlogin_probe", "src=\(source) parse_fail len=\(s.count) head=\(s.prefix(80))")
            return
        }
        logWtloginURLProbe(u, source: source)
    }

    /// 允许从 open completion / 非 MainActor 探针线程写日志
    nonisolated static func logOneKey(_ event: String, _ detail: String) {
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

    /// 每次一键开始清空旧日志，避免误读历史
    nonisolated static func resetOneKeyLogFile() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("onekey_last.txt")
        try? "".write(to: url, atomically: true, encoding: .utf8)
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

    func updateShellNav(canBack: Bool, canForward: Bool) {
        canGoBack = canBack
        canGoForward = canForward
    }

    func shellGoBack() {
        gameWebView?.goBack()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let wv = self.gameWebView else { return }
            self.updateShellNav(canBack: wv.canGoBack, canForward: wv.canGoForward)
        }
    }

    func shellGoForward() {
        gameWebView?.goForward()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let wv = self.gameWebView else { return }
            self.updateShellNav(canBack: wv.canGoBack, canForward: wv.canGoForward)
        }
    }

    /// 功能中心 / 我的：已接直接跑；未接只提示（不开空壳页）
    func openFeature(id: String) {
        switch id {
        case "one_login":
            shellTab = 0
            openOneKeyLogin()
        case "scan_login":
            shellTab = 0
            openScanLogin()
        case "logout":
            logout()
        case "exit_app":
            statusText = "请用系统手势划掉 App（iOS 无强制退出）"
        case "qunxia_luxiang":
            shellTab = 0
            openOfficialAnimation()
        case "about":
            showAbout = true
        case "huoyue":
            showHuoYue = true
        case "lingjiang":
            showLingJiang = true
        case "daiwan":
            showDaiWan = true
        case "daiwan_ui":
            showDaiWanRecord = true
        case "kuangdong", "jiebiao", "liangcao", "wending",
             "fuchou_wending", "open_kd", "change_guard", "paiqian":
            listenFeatureId = id
            showListenFeature = true
        case "join_qq_group":
            joinQqGroup(uin: "675796462")
        default:
            let label = FeatureCatalog.item(id: id)?.label ?? id
            statusText = "「\(label)」按 APK 待完整接入"
            TaskLogStore.shared.append("菜单", "待接：\(label)")
        }
    }

    func joinQqGroup(uin: String) {
        // 对齐 APK ExternalBrowser.joinQqGroup
        let urls = [
            "mqqapi://card/show_pslcard?src_type=internal&version=1&uin=\(uin)&card_type=group&source=external",
            "https://qm.qq.com/cgi-bin/qm/qr?k=&jump_from=webapi&authKey=&group_code=\(uin)",
        ]
        for s in urls {
            if let u = URL(string: s), UIApplication.shared.canOpenURL(u) {
                UIApplication.shared.open(u)
                statusText = "正在打开 QQ 群 \(uin)"
                return
            }
        }
        if let u = URL(string: "https://jq.qq.com/?_wv=1027&k=&group_code=\(uin)") {
            UIApplication.shared.open(u)
            statusText = "打开加群页 \(uin)"
        }
    }

    /// 顶栏打开链接：仅腾讯相关域
    @discardableResult
    func openShellURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var s = trimmed
        if s.hasPrefix("//") { s = "https:" + s }
        if !s.contains("://"), s.contains("cgi-bin") || s.hasPrefix("qpet") {
            s = "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?" + s
                .replacingOccurrences(of: "^.*phonepk\\?", with: "", options: .regularExpression)
        }
        guard let url = URL(string: s), let host = url.host?.lowercased() else { return false }
        let ok = host.hasSuffix(".qq.com") || host == "qq.com"
            || host.hasSuffix(".tencent.com") || host == "tencent.com"
        guard ok else { return false }
        preferDesktopUA = false
        shellTab = 0
        pendingURL = url
        statusText = "已打开 \(host)"
        return true
    }

    /// Exp A：最近一次回壳是否来自 schemacallback（onOpenURL）
    private var lastReturnViaCallback = false

    func handleOpenURL(_ url: URL) {
        // 先记一切非 http(s) 的打开，避免漏判「QQ 回跳了但 scheme 未登记」
        let sch = (url.scheme ?? "?").lowercased()
        if sch != "http", sch != "https" {
            Self.logOneKey(
                "open_url",
                "scheme=\(sch) host=\(url.host ?? "") path=\(url.path) q=\(url.query?.prefix(80) ?? "")"
            )
        }
        guard QqOneKeyLogin.isOurCallback(url) || LoginURLs.isCallbackScheme(url.scheme) else { return }
        lastReturnViaCallback = true
        Self.logOneKey("callback", "HIT scheme=\(sch) via=schemacallback")
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
        let oneKeyPending = loginMode == .oneKey
            || oneKeyPhase == .waitingQQConfirm
            || oneKeyPhase == .loadingGame
            || QqOneKeyLogin.awaitingReturn
            || QqOneKeyLogin.persistedAwaitingReturn
            || QqOneKeyLogin.launchedQrcode != nil
        let via: String
        if lastReturnViaCallback {
            via = "callback"
            lastReturnViaCallback = false
        } else {
            via = "manual_or_system"
        }
        let sinceOpen: String = {
            guard let t = QqOneKeyLogin.launchedAt else { return "na" }
            return String(format: "%.1fs", Date().timeIntervalSince(t))
        }()
        Self.logOneKey(
            "became_active",
            "via=\(via) since_qq=\(sinceOpen) pending=\(oneKeyPending) mode=\(loginMode.rawValue) phase=\(oneKeyPhase.rawValue) loggedIn=\(session.isLoggedIn)"
        )
        guard !session.isLoggedIn else { return }
        guard oneKeyPending else { return }
        // 回到前台时确保仍按一键收尾
        if loginMode != .oneKey { loginMode = .oneKey }
        // 仍在等 QQ：保持 waitingQQConfirm，让 finish 去 resume+harvest；勿过早标 loadingGame
        if oneKeyPhase == .idle || oneKeyPhase == .fetchingTicket {
            oneKeyPhase = .loadingGame
        }
        oneKeyFetcher?.resumeAfterQQ()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !session.isLoggedIn else { return }
            // 若还在 xlogin 且刚回前台，给页内 polling / check_sig 多留一会
            finishOneKeyAfterQQReturn()
        }
    }

    private func finishOneKeyAfterQQReturn() {
        guard !oneKeyReturnBusy else { return }
        if oneKeyPhase == .succeeded, session.isLoggedIn { return }
        oneKeyReturnBusy = true
        QqOneKeyLogin.markReturned()
        oneKeyPhase = .loadingGame
        statusText = "已回 App，正在确认登录…"
        OneKeyReturnNotifier.resetSession()
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

    /// 回壳：先 resume 等 OAuth；仅一代 wait 可 push phonepk（防 left_xlogin∩return 双开）。
    private func waitForOauthCookiesThenEnter(reason: String) async {
        oauthWaitGeneration &+= 1
        let gen = oauthWaitGeneration
        Self.logOneKey("oauth_wait", "\(reason) gen=\(gen)")
        preferDesktopUA = false
        statusText = "等待登录 Cookie…（可点左上角回 App）"

        // 优先：后台已收 / 再跟 check_sig 收 skey（OpenID 不够进玩法）
        if let wv = gameWebView {
            var harvested = OneKeyCheckSigCompleter.takePendingSkeyCookies()
            if harvested.isEmpty {
                harvested = await OneKeyCheckSigCompleter.tryHarvestSkey(from: wv)
            }
            if !harvested.isEmpty {
                await CookieBridge.restore(harvested, into: wv)
                // 再读全量 Cookie 写入 SessionStore
                let header = await CookieBridge.readCookieHeader(from: wv)
                if LoginURLs.hasGameSession(header) {
                    onCookiesCaptured(header)
                }
                await syncSessionFromWebView(reason: "check_sig_merge")
                if session.isLoggedIn, LoginURLs.hasRealSkey(session.cookieHeader) {
                    Self.logOneKey("oauth_wait", "skey_via_check_sig")
                    if !LoginURLs.isInGameShell(URL(string: currentURLString)) {
                        pendingURL = URL(string: LoginURLs.ledouEntry)
                    }
                    return
                }
            }
        }

        // 阶段 A：约 6s 只 resume / 采 Cookie，不打断 index.php?code=
        for i in 0..<6 {
            guard gen == oauthWaitGeneration else {
                Self.logOneKey("oauth_wait", "cancel_A gen=\(gen)")
                return
            }
            if session.isLoggedIn { return }
            if let wv = gameWebView {
                if i == 0 || i == 5 {
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
            if LoginURLs.isInGameShell(URL(string: currentURLString)) {
                await syncSessionFromWebView(reason: "oauth_shell_\(i)")
                if session.isLoggedIn { return }
                break
            }
            if LoginURLs.isOauthLanding(URL(string: currentURLString)) {
                // 多等一会儿让 index.php Set-Cookie 落完，勿急着 phonepk
                for j in 0..<4 {
                    guard gen == oauthWaitGeneration else { return }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    await syncSessionFromWebView(reason: "oauth_landing_\(i)_\(j)")
                    if session.isLoggedIn { return }
                }
                continue
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard gen == oauthWaitGeneration else {
            Self.logOneKey("oauth_wait", "cancel_pre_B gen=\(gen)")
            return
        }
        if session.isLoggedIn { return }

        // 阶段 B：软进 phonepk（不 inject）
        Self.logOneKey("oauth_wait", "push_phonepk gen=\(gen)")
        statusText = "正在进入游戏…"
        if !LoginURLs.isInGameShell(URL(string: currentURLString)) {
            pendingURL = URL(string: LoginURLs.ledouEntry)
        }
        for i in 0..<12 {
            guard gen == oauthWaitGeneration else {
                Self.logOneKey("oauth_wait", "cancel_B gen=\(gen)")
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await syncSessionFromWebView(reason: "phonepk_poll_\(i)")
            if session.isLoggedIn { return }
            if let wv = gameWebView, QqOneKeyLogin.isXloginPage(wv.url) {
                _ = await evalJS(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
            }
        }
        guard gen == oauthWaitGeneration else { return }
        if !session.isLoggedIn {
            let names: String
            if let wv = gameWebView {
                names = await CookieBridge.cookieNameDomainLog(from: wv)
            } else {
                names = "(no-wv)"
            }
            Self.logOneKey("oauth_fail", "names=\(names)")
            statusText = "未读到登录会话（\(cookieNamesShort(names))）。可扫码或 Cookie"
            // 勿停在「亿万用户」营销页
            if LoginURLs.isConnectMarketing(URL(string: currentURLString))
                || (currentURLString.contains("graph.qq.com") && !session.isLoggedIn) {
                loadWaitingPage = true
                pendingURL = nil
            }
            QqOneKeyLogin.persistedAwaitingReturn = false
            loginMode = .idle
            oneKeyPhase = .failed
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
                // 回壳收尾中误入营销页：拉回 live xlogin，勿直接终态
                if oneKeyPhase == .waitingQQConfirm
                    || oneKeyPhase == .loadingGame
                    || oneKeyPhase == .syncingCookies {
                    Self.logOneKey("nav_marketing", "bounce_phonepk phase=\(oneKeyPhase.rawValue)")
                    // 勿改回 fetchingTicket（会再次拉 QQ）；软进游戏壳等 Cookie
                    pendingURL = URL(string: LoginURLs.ledouEntry)
                    return
                }
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
            // 页内若仍写「未登录」，说明 Cookie 不够，勿假装成功
            if let wv = gameWebView {
                Task { @MainActor in
                    let text = (await evalJS(
                        "(document.body&&document.body.innerText||'').slice(0,200)",
                        in: wv
                    ) as? String) ?? ""
                    if text.contains("未登录") || text.contains("请先登录") {
                        Self.logOneKey("enter_game", "shell_but_page_nologin")
                        statusText = "游戏页仍显示未登录，请再试一键或 Cookie"
                        oneKeyPhase = .failed
                        loginMode = .oneKey
                        return
                    }
                    statusText = "已登录 QQ \(showQq)\(kindHint)"
                    Self.logOneKey("enter_game", "already_shell kind=\(hasSkey ? "skey" : "openid")")
                }
            } else {
                statusText = "已登录 QQ \(showQq)\(kindHint)"
                Self.logOneKey("enter_game", "already_shell kind=\(hasSkey ? "skey" : "openid")")
            }
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

    func applyCookieHeader(_ header: String, status: String) {
        let normalized = Self.normalizeCookieHeader(header)
        guard LoginURLs.hasGameSession(normalized) else {
            statusText = "会话无效"
            return
        }
        stopAllOneKey()
        oneKeyPhase = .idle
        loginMode = .idle
        preferDesktopUA = false
        session.save(cookieHeader: normalized)
        cookieInjectToken &+= 1
        pendingURL = URL(string: LoginURLs.ledouEntry)
        refreshStatus()
        statusText = status
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
