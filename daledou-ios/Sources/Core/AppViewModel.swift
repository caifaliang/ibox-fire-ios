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
    private var oneKeyFetcher: OneKeyTicketFetcher?

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
            cookieInjectToken &+= 1
            pendingURL = URL(string: LoginURLs.ledouEntry)
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

    /// 防 connect 营销页死循环回跳
    private var lastOneKeyBounceAt: TimeInterval = 0
    /// 防回壳自动刷新重入
    private var oneKeyReturnBusy = false

    /// 一键登录：清 Cookie → **authorize/style=35**（勿停在 connect 营销页）→ qrcode 跳 QQ。
    /// 图上「亿万用户」+「不支持QQ快速登录」= connect 营销页点按钮；必须离开该页。
    func openOneKeyLogin() {
        loginMode = .oneKey
        preferDesktopUA = false
        didEnterGameFromCapture = false
        QqOneKeyLogin.clearPending()
        session.clear()
        oneKeyFetcher?.cancel()
        oneKeyFetcher = nil
        lastOneKeyBounceAt = 0
        oneKeyReturnBusy = false
        statusText = "一键登录：清理并打开登录页…"
        clearWebEpoch &+= 1
        // 直接 authorize，比 phonepk 更稳落到 style=35；避开 connect「亿万用户」
        pendingURL = URL(string: LoginURLs.oneKeyLogin)
        Task { @MainActor in
            if let live = await LoginURLs.resolveLiveXloginURL() {
                guard loginMode == .oneKey, !session.isLoggedIn else { return }
                pendingURL = live
            }
        }
    }

    func attachOneKeyFetcher(to webView: WKWebView) {
        guard loginMode == .oneKey else { return }
        guard QqOneKeyLogin.isXloginPage(webView.url) else { return }
        // 已在跑则不重挂；离开 xlogin 后会 cancel
        if oneKeyFetcher != nil { return }
        let fetcher = OneKeyTicketFetcher(webView: webView) { [weak self] event in
            self?.handleOneKeyEvent(event)
        }
        oneKeyFetcher = fetcher
        fetcher.start()
    }

    func oneKeyFetcherMarkOpened() {
        oneKeyFetcher?.markOpenedQQ()
    }

    func stopOneKeyFetcher() {
        oneKeyFetcher?.cancel()
        oneKeyFetcher = nil
    }

    /// 误入 connect「亿万用户」/取票失败：拉到新鲜 style=35，禁止再刷 phonepk（会又进营销页）
    func bounceOneKeyToLiveXlogin(reason: String = "离开营销页") {
        guard loginMode == .oneKey else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastOneKeyBounceAt > 2.5 else { return }
        lastOneKeyBounceAt = now
        stopOneKeyFetcher()
        statusText = "一键登录：\(reason)…"
        Task { @MainActor in
            guard loginMode == .oneKey else { return }
            if let live = await LoginURLs.resolveLiveXloginURL() {
                pendingURL = live
            } else {
                pendingURL = URL(string: LoginURLs.oneKeyLogin)
            }
        }
    }

    /// 兼容旧名
    func bounceOneKeyToPhonepk(reason: String = "离开营销页") {
        bounceOneKeyToLiveXlogin(reason: reason)
    }

    private func handleOneKeyEvent(_ event: OneKeyTicketFetcher.Event) {
        switch event {
        case .status(let s):
            statusText = s
        case .openedQQ:
            statusText = "已跳转 QQ，请点「同意」…"
        case .failed(let msg):
            statusText = msg
            // 持续取票失败多半已离开 xlogin（如掉进 connect）→ 拉回真登录页
            if msg.contains("取票失败") || msg.contains("离开登录页") {
                bounceOneKeyToLiveXlogin(reason: msg)
            }
        }
    }

    /// 扫码登陆（壳内展示二维码，与一键分流）
    func openScanLogin() {
        loginMode = .scan
        preferDesktopUA = true
        oneKeyFetcher?.cancel()
        oneKeyFetcher = nil
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
        if let code = LoginURLs.oauthCode(from: url),
           let finish = LoginURLs.finishWithCode(code) {
            QqOneKeyLogin.markReturned()
            loginMode = .oneKey
            preferDesktopUA = false
            statusText = "已从 QQ 返回（code），正在写入会话…"
            pendingURL = finish
            return
        }
        QqOneKeyLogin.markReturned()
        loginMode = .oneKey
        statusText = "已从 QQ 返回，正在完成授权…"
        if let https = QqOneKeyLogin.continueURL(fromCallback: url),
           (https.scheme == "http" || https.scheme == "https"),
           !https.path.lowercased().contains("jump") {
            pendingURL = https
            return
        }
        finishOneKeyAfterQQReturn()
    }

    /// 竞品需手动回 App + 刷新；我们自动：restore → resume → 刷新 phonepk 取 Cookie
    func onAppBecameActive() {
        guard loginMode == .oneKey, !session.isLoggedIn else { return }
        // 尚未跳过 QQ 时不要刷新，否则会打断取票
        guard QqOneKeyLogin.awaitingReturn || QqOneKeyLogin.launchedQrcode != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard loginMode == .oneKey, !session.isLoggedIn else { return }
            finishOneKeyAfterQQReturn()
        }
    }

    private func finishOneKeyAfterQQReturn() {
        guard !oneKeyReturnBusy else { return }
        oneKeyReturnBusy = true
        QqOneKeyLogin.markReturned()
        oneKeyFetcher?.resumeAfterQQ()
        if let wv = gameWebView, QqOneKeyLogin.isXloginPage(wv.url) {
            wv.evaluateJavaScript(QqOneKeyLogin.jsResumeAfterQQ, completionHandler: nil)
            wv.evaluateJavaScript(QqOneKeyLogin.jsKeepPolling, completionHandler: nil)
        }
        statusText = "已回 App，自动刷新获取 Cookie…"
        Task { @MainActor in
            defer { oneKeyReturnBusy = false }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard loginMode == .oneKey, !session.isLoggedIn else { return }
            if let wv = gameWebView {
                let header = await CookieBridge.waitForSkey(from: wv, attempts: 8, gapMs: 400)
                if LoginURLs.hasRealSkey(header) {
                    onCookiesCaptured(header)
                    return
                }
            }
            // 对齐竞品「手动刷新」：强制进 phonepk 再读 Cookie
            preferDesktopUA = false
            pendingURL = URL(string: LoginURLs.ledouEntry)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard loginMode == .oneKey, !session.isLoggedIn else { return }
            if let wv = gameWebView {
                let header = await CookieBridge.waitForSkey(from: wv, attempts: 10, gapMs: 400)
                if LoginURLs.hasRealSkey(header) {
                    onCookiesCaptured(header)
                } else {
                    statusText = "未读到 Cookie，请点菜单刷新或再试一键登录"
                }
            }
        }
    }

    func onNavigated(to url: URL?) {
        currentURLString = url?.absoluteString ?? ""

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
                bounceOneKeyToPhonepk(reason: "离开营销页")
                return
            }
            if loginMode == .scan {
                statusText = "误入 QQ 互联首页，请重新扫码登陆"
                pendingURL = URL(string: LoginURLs.scanLedou)
                return
            }
        }

        // 已进 phonepk 首页：把「正在进入…」改成正式已登录
        if session.isLoggedIn, LoginURLs.isInGameShell(url) {
            let q = qqLabel.isEmpty ? (session.qq.isEmpty ? "?" : session.qq) : qqLabel
            statusText = "已登录 QQ \(q)"
            titleHint = "大乐斗"
            preferDesktopUA = false
            loginMode = .idle
        }

        updateViewFightFab(for: currentURLString)
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
        guard session.isLoggedIn else {
            statusText = "请先登录再看官方动画"
            return
        }
        guard !viewFightLoading else { return }
        viewFightLoading = true
        statusText = "正在获取战斗数据…"
        Task {
            var cookie = session.cookieHeader
            if let wv = gameWebView {
                let web = await CookieBridge.readCookieHeader(from: wv)
                cookie = Self.mergeCookieHeaders(cookie, web)
                if LoginURLs.hasRealSkey(cookie) {
                    session.save(cookieHeader: cookie)
                }
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
        guard LoginURLs.hasRealSkey(header) else { return }
        session.save(cookieHeader: header)
        loginMode = .idle
        preferDesktopUA = false
        if let extracted = LoginURLs.extractQq(header), !extracted.isEmpty {
            qqLabel = extracted
        }
        let showQq = qqLabel.isEmpty ? "?" : qqLabel
        titleHint = "大乐斗"
        // 注意：index.php?code= 也在 dld.qzapp 上，不能当成已进游戏而跳过跳转
        if !didEnterGameFromCapture || !LoginURLs.isInGameShell(URL(string: currentURLString)) {
            didEnterGameFromCapture = true
            statusText = "已登录 QQ \(showQq) · 正在进入游戏…"
            forceEnterGame()
        } else {
            statusText = "已登录 QQ \(showQq) · Cookie 已保存"
        }
    }

    /// 注入 Cookie 并强制打开手机端首页（扫码后卡在 QQ 一键页时用）
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
        oneKeyFetcher?.cancel()
        oneKeyFetcher = nil
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
