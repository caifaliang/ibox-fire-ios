import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let session = SessionStore.shared

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
            statusText = "未登录 · 扫码登陆 / Cookie 登陆"
            titleHint = "大乐斗 · 登录"
        }
    }

    /// 扫码登陆（主路径）
    func openScanLogin() {
        loginMode = .scan
        preferDesktopUA = true
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
        // 扫码流程可能走到自定义 scheme；尽量进游戏
        if url.scheme?.lowercased() == "daledouapp" || LoginURLs.isCallbackScheme(url.scheme) {
            if session.isLoggedIn {
                openGameHome()
            } else {
                statusText = "收到回调但无会话，请扫码或粘贴 Cookie"
            }
        }
    }

    func onNavigated(to url: URL?) {
        currentURLString = url?.absoluteString ?? ""

        if loginMode == .scan, let s = url?.absoluteString,
           let cont = LoginURLs.continueAuthorizeUrl(xloginUrl: s),
           let u = URL(string: cont) {
            statusText = "扫码已确认，继续授权…"
            pendingURL = u
            return
        }

        if LoginURLs.isConnectMarketing(url), loginMode == .scan {
            statusText = "误入 QQ 互联首页，请重新扫码登陆"
            pendingURL = URL(string: LoginURLs.scanLedou)
            return
        }

        // 已进 phonepk 首页：把「正在进入…」改成正式已登录
        if session.isLoggedIn, LoginURLs.isInGameShell(url) {
            let q = qqLabel.isEmpty ? (session.qq.isEmpty ? "?" : session.qq) : qqLabel
            statusText = "已登录 QQ \(q)"
            titleHint = "大乐斗"
            preferDesktopUA = false
            loginMode = .idle
        }
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
        session.clear()
        loginMode = .idle
        preferDesktopUA = false
        cookieDraft = ""
        didEnterGameFromCapture = false
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
