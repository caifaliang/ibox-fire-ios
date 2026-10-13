import Foundation
import UIKit

/// QQ App 一键登录（对齐 Android `ONE_CLICK_WT` + 竞品 wtlogin 解析）。
/// 流程：xlogin 页 / 直接 wtlogin → QQ 确认 → `daledouapp://` 回壳 → WebView 打开 jump 写 Cookie。
enum QqOneKeyLogin {
    static let callbackScheme = "daledouapp"
    static let callbackURLString = "daledouapp://"

    private(set) static var pendingJumpURL: URL?
    private(set) static var awaitingReturn = false

    static func isWtloginScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased(), !s.isEmpty else { return false }
        return s.hasPrefix("wtlogin") || s.hasPrefix("mqq")
    }

    static func isOurCallback(_ url: URL) -> Bool {
        let s = (url.scheme ?? "").lowercased()
        return s == callbackScheme
            || s == "daledoulogin"
            || s == "com.daledou.ioslogin"
            || s == LoginURLs.tencentScheme.lowercased()
            || s.hasPrefix("tencent")
    }

    /// 从 wtlogin 里取 `p`（ssl.ptlogin2 jump），供回壳后继续。
    static func jumpURL(fromP p: String) -> URL? {
        let decoded = p.removingPercentEncoding ?? p
        guard decoded.hasPrefix("http") else { return nil }
        return URL(string: decoded)
    }

    /// 重建 launch URL：只保留 `p` + `schemacallback`（对齐竞品，避免改坏页内参数）。
    static func buildLaunchURL(from raw: URL) -> URL? {
        guard let comps = URLComponents(url: raw, resolvingAgainstBaseURL: false),
              let p = comps.queryItems?.first(where: { $0.name == "p" })?.value,
              !p.isEmpty else { return nil }
        var launch = URLComponents()
        launch.scheme = "wtloginmqq"
        launch.host = "ptlogin"
        launch.path = "/qlogin"
        launch.queryItems = [
            URLQueryItem(name: "p", value: p),
            URLQueryItem(name: "schemacallback", value: callbackURLString),
        ]
        return launch.url
    }

    /// 优先直接唤 QQ（Android `wakeQqPtLogin`）；失败则 false，由调用方打开 xlogin 页。
    @discardableResult
    static func wakeDirect() -> Bool {
        guard let raw = URL(string: LoginURLs.oneClickWtLaunch) else { return false }
        return openInQQ(raw)
    }

    /// 唤起系统 QQ；记下 pending jump，等 `daledouapp://` 或手动回壳。
    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        let launch = buildLaunchURL(from: raw) ?? raw
        if let p = URLComponents(url: launch, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "p" })?.value {
            pendingJumpURL = jumpURL(fromP: p) ?? LoginURLs.oneClickJumpURL
        } else {
            pendingJumpURL = LoginURLs.oneClickJumpURL
        }

        awaitingReturn = true
        if UIApplication.shared.canOpenURL(launch) {
            UIApplication.shared.open(launch, options: [:], completionHandler: nil)
            return true
        }
        UIApplication.shared.open(launch, options: [:], completionHandler: nil)
        return true
    }

    static func markReturned() {
        awaitingReturn = false
    }

    static func takePendingJump() -> URL? {
        let u = pendingJumpURL
        pendingJumpURL = nil
        return u
    }

    static func clearPending() {
        pendingJumpURL = nil
        awaitingReturn = false
    }
}
