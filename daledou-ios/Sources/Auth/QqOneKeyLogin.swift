import Foundation
import UIKit

/// QQ App 一键登录（对齐安卓 `LoginHelper.ONE_CLICK_WT` + 竞品 `QqOneKeyLoginBridge`）。
/// 流程：壳内 authorize → 唤起 `wtloginmqq*`（带 schemacallback）→ QQ 确认 → 回跳壳 → WebView 收 Cookie。
enum QqOneKeyLogin {
    /// 回壳 Scheme（须在 Info.plist 注册）
    static let callbackScheme = "daledouapp"
    static let callbackURLString = "daledouapp://"

    /// 最近一次唤起 QQ 时携带的 jump / authorize URL，回壳后用它继续写会话
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

    /// 强制 schemacallback 指向本 App，避免 QQ 登完停在企鹅页。
    static func ensureSchemacallback(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "schemacallback" }
        items.append(URLQueryItem(name: "schemacallback", value: callbackURLString))
        comps.queryItems = items
        return comps.url ?? url
    }

    /// 从 wtlogin URL 抠出 jump / qrcode，供回壳后 WebView 继续走。
    static func extractContinueURL(from wtlogin: URL) -> URL? {
        guard let comps = URLComponents(url: wtlogin, resolvingAgainstBaseURL: false) else { return nil }
        for name in ["p", "qrcode", "url"] {
            if let raw = comps.queryItems?.first(where: { $0.name == name })?.value?
                .removingPercentEncoding,
               raw.hasPrefix("http"),
               let u = URL(string: raw) {
                return u
            }
        }
        return nil
    }

    /// 唤起系统 QQ；成功则记下 pendingJump，等 onOpenURL。
    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        let withCb = ensureSchemacallback(raw)
        pendingJumpURL = extractContinueURL(from: withCb)
            ?? URL(string: LoginURLs.oneClickAuthorize)

        var candidates = [withCb]
        if var c = URLComponents(url: withCb, resolvingAgainstBaseURL: false) {
            let scheme = (c.scheme ?? "").lowercased()
            if scheme == "wtloginmqq" || scheme == "wtloginmqq2" {
                c.scheme = "wtloginmqq3"
                if let u = c.url { candidates.insert(u, at: 0) }
            } else if scheme == "wtloginmqq3" {
                c.scheme = "wtloginmqq"
                if let u = c.url { candidates.append(u) }
            }
        }

        awaitingReturn = true
        for u in candidates where UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
            return true
        }
        // canOpenURL 偶发 false：仍尝试 open 首选 URL
        UIApplication.shared.open(withCb, options: [:], completionHandler: nil)
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
