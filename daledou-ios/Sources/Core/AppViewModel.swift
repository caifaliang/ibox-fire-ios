import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let session = SessionStore.shared

    @Published var statusText = ""
    @Published var showMenu = false
    @Published var pendingURL: URL?
    @Published var loadWaitingPage = false
    @Published var webReloadToken = 0
    @Published var clearWebEpoch = 0
    @Published var currentURLString = ""
    @Published var titleHint = "大乐斗 MVP"
    @Published var qqLabel = ""
    @Published var loginMode: LoginMode = .idle
    /// 扫码用桌面 UA；一键用系统移动 UA（壳内 authorize）
    @Published var preferDesktopUA = false

    func bootstrap() {
        if session.isLoggedIn {
            preferDesktopUA = false
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
            statusText = "未登录 · 菜单：一键登陆 / 扫码登陆"
            titleHint = "大乐斗 · 登录"
        }
    }

    /// 一键登陆：壳内 WKWebView 加载 QQ 互联 authorize（不唤 QQ、不跳 Safari）
    func openOneClickLogin() {
        loginMode = .oneClick
        preferDesktopUA = false
        session.clear()
        clearWebEpoch &+= 1
        statusText = "壳内一键授权中…全程不离开 App"
        pendingURL = URL(string: LoginURLs.oneClickAuthorize)
    }

    /// 扫码登陆：壳内二维码 + 桌面 UA
    func openScanLogin() {
        loginMode = .scan
        preferDesktopUA = true
        session.clear()
        clearWebEpoch &+= 1
        statusText = "扫码登陆中…用手机 QQ 扫页面二维码"
        pendingURL = URL(string: LoginURLs.scanLedou)
    }

    func openGameHome() {
        loginMode = .idle
        preferDesktopUA = false
        pendingURL = URL(string: LoginURLs.ledouEntry)
    }

    func reload() {
        webReloadToken &+= 1
    }

    /// 自定义 Scheme 回调：tencent{appid}:// 或 daledouapp://
    func handleOpenURL(_ url: URL) {
        if let code = LoginURLs.oauthCode(from: url), let finish = LoginURLs.finishWithCode(code) {
            statusText = "已拦截授权 code，壳内完成登录…"
            preferDesktopUA = false
            pendingURL = finish
            return
        }
        if url.scheme?.lowercased() == "daledouapp" || LoginURLs.isCallbackScheme(url.scheme) {
            statusText = "收到回调，进入游戏首页"
            openGameHome()
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

        // 一键：authorize 完成后 https 回调到 index.php?code=
        if loginMode == .oneClick, let u = url, let code = LoginURLs.oauthCode(from: u) {
            statusText = "授权成功，写入游戏会话…"
            // 继续允许当前页加载；若已是 finish URL 则等 Cookie
            if !u.absoluteString.contains("dld.qzapp.z.qq.com") {
                if let finish = LoginURLs.finishWithCode(code) {
                    pendingURL = finish
                }
            }
        }

        if LoginURLs.isConnectMarketing(url) {
            statusText = "误入 QQ 互联首页，请重新点「一键登陆」或改用扫码"
            if loginMode == .oneClick {
                pendingURL = URL(string: LoginURLs.oneClickAuthorize)
            }
        }
    }

    func onCookiesCaptured(_ header: String) {
        guard LoginURLs.hasRealSkey(header) else { return }
        session.save(cookieHeader: header)
        loginMode = .idle
        preferDesktopUA = false
        refreshStatus()
        statusText = "登录成功 · Cookie 已保存"
        if let cur = URL(string: currentURLString), !LoginURLs.isGameHost(cur) {
            openGameHome()
        }
    }

    func logout() {
        session.clear()
        loginMode = .idle
        preferDesktopUA = false
        clearWebEpoch &+= 1
        loadWaitingPage = true
        pendingURL = nil
        refreshStatus()
        statusText = "已退出"
    }
}
