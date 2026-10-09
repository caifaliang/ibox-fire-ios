import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    let session = SessionStore.shared

    @Published var statusText = ""
    @Published var showMenu = false
    /// 驱动 WebView 导航（非 nil 时加载）
    @Published var pendingURL: URL?
    @Published var webReloadToken = 0
    /// 递增后 WebView 清空 Cookie（退出登录）
    @Published var clearWebEpoch = 0
    @Published var currentURLString = ""
    @Published var titleHint = "大乐斗 MVP"
    @Published var qqLabel = ""

    func bootstrap() {
        let start = LoginURLs.shellStartUrl(cookie: session.cookieHeader)
        pendingURL = URL(string: start)
        refreshStatus()
    }

    func refreshStatus() {
        qqLabel = session.qq
        if session.isLoggedIn {
            let q = qqLabel.isEmpty ? "?" : qqLabel
            statusText = "已登录 QQ \(q)"
            titleHint = "大乐斗"
        } else {
            statusText = "未登录 · 请用菜单登录"
            titleHint = "大乐斗 · 登录"
        }
    }

    func openInAppLogin() {
        pendingURL = URL(string: LoginURLs.xloginHome)
        statusText = "壳内登录中…"
    }

    func openPasswordLogin() {
        pendingURL = URL(string: LoginURLs.ledouPtlogin)
        statusText = "密码登录中…"
    }

    func openScanLogin() {
        pendingURL = URL(string: LoginURLs.scanLedou)
        statusText = "扫码登录中…（可用另一台设备扫）"
    }

    func openGameHome() {
        pendingURL = URL(string: LoginURLs.ledouEntry)
    }

    func reload() {
        webReloadToken &+= 1
    }

    /// 尝试一键唤 QQ；失败则回退壳内登录页
    func tryOneClickWakeQQ() {
        statusText = "正在唤起 QQ…"
        guard let url = URL(string: LoginURLs.oneClickWt) else {
            openInAppLogin()
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    self.statusText = "已唤起 QQ，授权后应回 App（daledouapp://）"
                } else {
                    self.statusText = "唤起 QQ 失败，改用壳内登录"
                    self.openInAppLogin()
                }
            }
        }
    }

    /// `daledouapp://` 回调：在壳内打开 jump
    func handleOpenURL(_ url: URL) {
        if url.scheme?.lowercased() == "daledouapp" {
            if let jump = LoginURLs.oneClickJumpUrl(), let u = URL(string: jump) {
                statusText = "收到 QQ 回调，加载 jump…"
                pendingURL = u
            } else {
                statusText = "收到回调，打开游戏首页"
                openGameHome()
            }
            return
        }
        // 少数情况 QQ 可能直接带回 https jump
        if url.host?.contains("ptlogin2.qq.com") == true {
            statusText = "加载授权 jump…"
            pendingURL = url
        }
    }

    func onCookiesCaptured(_ header: String) {
        guard LoginURLs.hasRealSkey(header) else { return }
        session.save(cookieHeader: header)
        refreshStatus()
        statusText = "登录成功 · Cookie 已保存"
        // 进游戏首页
        if let cur = URL(string: currentURLString), !LoginURLs.isGameHost(cur) {
            openGameHome()
        }
    }

    func logout() {
        session.clear()
        clearWebEpoch &+= 1
        pendingURL = URL(string: LoginURLs.xloginHome)
        refreshStatus()
        statusText = "已退出"
    }
}
