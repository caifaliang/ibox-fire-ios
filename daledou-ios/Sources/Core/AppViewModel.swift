import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    let session = SessionStore.shared

    @Published var statusText = ""
    @Published var showMenu = false
    @Published var pendingURL: URL?
    /// 加载本地 HTML 占位（about 或 data 不便时用此标记）
    @Published var loadWaitingPage = false
    @Published var webReloadToken = 0
    @Published var clearWebEpoch = 0
    @Published var currentURLString = ""
    @Published var titleHint = "大乐斗 MVP"
    @Published var qqLabel = ""
    @Published var loginMode: LoginMode = .idle
    /// 扫码时使用桌面 UA；其它时候用系统默认
    @Published var preferDesktopUA = false
    /// 一键流程中：允许 WebView 把 wtlogin 交给系统 QQ
    @Published var allowQqWake = false

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

    /// 一键登陆：真唤 QQ + schemacallback=daledouapp://
    func openOneClickLogin() {
        loginMode = .oneClick
        allowQqWake = true
        preferDesktopUA = false
        session.clear()
        clearWebEpoch &+= 1
        loadWaitingPage = true
        statusText = "正在唤起 QQ 一键登陆…授权后应自动回 App"

        guard let url = URL(string: LoginURLs.oneClickWt) else {
            statusText = "一键链接无效"
            allowQqWake = false
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    self.statusText = "已打开 QQ，请在 QQ 内确认授权；完成后应回到本 App"
                } else {
                    self.allowQqWake = false
                    self.loginMode = .idle
                    self.statusText = "唤起 QQ 失败（未安装或系统拦截）。请改用扫码登陆"
                }
            }
        }
    }

    /// 扫码登陆：壳内 graph.qq.com（桌面 UA）
    func openScanLogin() {
        loginMode = .scan
        allowQqWake = false
        preferDesktopUA = true
        session.clear()
        clearWebEpoch &+= 1
        statusText = "扫码登陆中…用手机 QQ 扫页面二维码"
        // clear 完成后再导航：由 clearEpoch 路径带 pendingURL
        pendingURL = URL(string: LoginURLs.scanLedou)
    }

    func openGameHome() {
        loginMode = .idle
        allowQqWake = false
        preferDesktopUA = false
        pendingURL = URL(string: LoginURLs.ledouEntry)
    }

    func reload() {
        webReloadToken &+= 1
    }

    /// `daledouapp://`：QQ 授权回调 → 壳内打开 jump
    func handleOpenURL(_ url: URL) {
        if url.scheme?.lowercased() == "daledouapp" {
            allowQqWake = false
            preferDesktopUA = false
            if let jump = LoginURLs.oneClickJumpUrl(), let u = URL(string: jump) {
                statusText = "收到 QQ 回调，壳内完成登录…"
                loginMode = .oneClick
                pendingURL = u
            } else {
                statusText = "收到回调，进入游戏"
                openGameHome()
            }
            return
        }
        if (url.host ?? "").contains("ptlogin2.qq.com") {
            allowQqWake = false
            statusText = "壳内加载授权页…"
            pendingURL = url
        }
    }

    func onNavigated(to url: URL?) {
        currentURLString = url?.absoluteString ?? ""
        // 扫码：xlogin + pt_skey_valid=1 → 继续 jump
        if loginMode == .scan, let s = url?.absoluteString,
           let cont = LoginURLs.continueAuthorizeUrl(xloginUrl: s),
           let u = URL(string: cont) {
            statusText = "扫码已确认，继续授权…"
            pendingURL = u
            return
        }
        // 误落到互联营销首页：提示改扫码
        if LoginURLs.isConnectMarketing(url), loginMode == .oneClick {
            statusText = "一键未回到 App（落到 QQ 互联页）。请改用「扫码登陆」"
            allowQqWake = false
        }
    }

    func onCookiesCaptured(_ header: String) {
        guard LoginURLs.hasRealSkey(header) else { return }
        session.save(cookieHeader: header)
        loginMode = .idle
        allowQqWake = false
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
        allowQqWake = false
        preferDesktopUA = false
        clearWebEpoch &+= 1
        loadWaitingPage = true
        pendingURL = nil
        refreshStatus()
        statusText = "已退出"
    }
}
