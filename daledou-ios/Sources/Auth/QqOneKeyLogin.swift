import Foundation
import UIKit

/// QQ App 一键登录（对齐竞品 FandianAssistant `QqOneKeyLoginBridge`）。
/// iOS 必须用 `wtloginmqq3?qrcode=…&schemacallback=daledoulogin://`；
/// 安卓同款 `p=` + `daledouapp://` 在 iOS 上会让 QQ 把 jump 丢给 Safari。
enum QqOneKeyLogin {
    /// 竞品回壳 Scheme（Info.plist 已注册）
    static let callbackScheme = "daledoulogin"
    static let callbackURLString = "daledoulogin://"
    /// 竞品备用
    static let callbackSchemeAlt = "com.daledou.ioslogin"

    private(set) static var pendingJumpURL: URL?
    private(set) static var awaitingReturn = false

    static func isWtloginScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased(), !s.isEmpty else { return false }
        return s.hasPrefix("wtlogin") || s.hasPrefix("mqq")
    }

    static func isOurCallback(_ url: URL) -> Bool {
        let s = (url.scheme ?? "").lowercased()
        return s == callbackScheme
            || s == callbackSchemeAlt
            || s == "daledouapp"
            || s == LoginURLs.tencentScheme.lowercased()
            || s.hasPrefix("tencent")
    }

    /// 从页内 / 静态 wtlogin 取出要继续的 https jump（`qrcode` 或 `p`）。
    static func extractContinueURL(from wtlogin: URL) -> URL? {
        guard let comps = URLComponents(url: wtlogin, resolvingAgainstBaseURL: false) else { return nil }
        for name in ["qrcode", "p", "url"] {
            guard let raw = comps.queryItems?.first(where: { $0.name == name })?.value else { continue }
            let decoded = raw.removingPercentEncoding ?? raw
            if decoded.hasPrefix("http"), let u = URL(string: decoded) { return u }
        }
        return nil
    }

    /// 重建为竞品格式：`wtloginmqq3://ptlogin/qlogin?qrcode=…&schemacallback=daledoulogin://`
    static func buildLaunchURL(from raw: URL) -> URL? {
        guard let jump = extractContinueURL(from: raw) else { return nil }
        var launch = URLComponents()
        launch.scheme = "wtloginmqq3"
        launch.host = "ptlogin"
        launch.path = "/qlogin"
        // qrcode / schemacallback 交给 URLQueryItem 编码（勿二次手工 encode）
        launch.queryItems = [
            URLQueryItem(name: "qrcode", value: jump.absoluteString),
            URLQueryItem(name: "schemacallback", value: callbackURLString),
        ]
        return launch.url
    }

    /// 解析 QQ 经 schemacallback 回跳的 URL → 可在 WebView 打开的 https jump。
    /// 竞品形态：`daledoulogin://ssl.ptlogin2.qq.com/jump?…&clientuin=…`
    /// 或 `daledoulogin://?clientuin=…&clientkey=…`（拼到 pending jump）。
    static func continueURL(fromCallback url: URL) -> URL? {
        let abs = url.absoluteString
        let prefixes = [
            "\(callbackScheme)://",
            "\(callbackSchemeAlt)://",
            "daledouapp://",
            "\(LoginURLs.tencentScheme)://",
        ]
        var rest: String?
        for p in prefixes {
            if abs.lowercased().hasPrefix(p.lowercased()) {
                rest = String(abs.dropFirst(p.count))
                break
            }
        }
        guard var body = rest else { return nil }

        if body.hasPrefix("http://") || body.hasPrefix("https://") {
            return URL(string: body)
        }
        // `(null)?clientuin=…` → 把 query 并进 pending jump
        if body.hasPrefix("(null)") {
            body = String(body.dropFirst(6))
        }
        if body.hasPrefix("?") || body.isEmpty {
            return mergeClientParams(into: pendingJumpURL ?? LoginURLs.oneClickJumpURL, from: url)
        }
        // `ssl.ptlogin2.qq.com/jump?…`
        if body.contains(".") {
            return URL(string: "https://" + body)
        }
        return mergeClientParams(into: pendingJumpURL ?? LoginURLs.oneClickJumpURL, from: url)
    }

    private static func mergeClientParams(into base: URL?, from callback: URL) -> URL? {
        guard var comps = base.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return base
        }
        var items = comps.queryItems ?? []
        let cbItems = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["clientuin", "clientkey", "keyindex"] {
            if let v = cbItems.first(where: { $0.name == name })?.value, !v.isEmpty {
                items.removeAll { $0.name == name }
                items.append(URLQueryItem(name: name, value: v))
            }
        }
        // 也从 absoluteString 的 query 段抠（scheme 回跳偶发只有 path）
        if let q = callback.query, !q.isEmpty {
            for pair in q.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2, ["clientuin", "clientkey", "keyindex"].contains(kv[0]) else { continue }
                items.removeAll { $0.name == kv[0] }
                items.append(URLQueryItem(name: kv[0], value: kv[1].removingPercentEncoding ?? kv[1]))
            }
        }
        comps.queryItems = items
        return comps.url ?? base
    }

    /// 唤起系统 QQ；记下 pending jump，等 `daledoulogin://`。
    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        let launch = buildLaunchURL(from: raw) ?? raw
        pendingJumpURL = extractContinueURL(from: raw)
            ?? extractContinueURL(from: launch)
            ?? LoginURLs.oneClickJumpURL

        awaitingReturn = true
        var candidates: [URL] = [launch]
        // 少数机型只认 wtloginmqq（无 3）
        if var c = URLComponents(url: launch, resolvingAgainstBaseURL: false),
           (c.scheme ?? "").lowercased() == "wtloginmqq3" {
            c.scheme = "wtloginmqq"
            if let u = c.url { candidates.append(u) }
        }
        for u in candidates where UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
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
