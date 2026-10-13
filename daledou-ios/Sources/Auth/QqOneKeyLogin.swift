import Foundation
import UIKit

/// QQ App 一键登录（对齐竞品回壳 + 页内原始 wtlogin 参数）。
/// - 回壳：`schemacallback=daledoulogin://`（勿用 daledouapp，iOS 易进 Safari）
/// - 载荷：保留页内原始 `p=` 或 `qrcode=`，**禁止**互相改名（改名 → QQ「登录授权失败」）
enum QqOneKeyLogin {
    static let callbackScheme = "daledoulogin"
    static let callbackURLString = "daledoulogin://"
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

    /// 从 wtlogin 取出 https jump（供回壳后 WebView 继续）。
    static func extractContinueURL(from wtlogin: URL) -> URL? {
        guard let comps = URLComponents(url: wtlogin, resolvingAgainstBaseURL: false) else { return nil }
        for name in ["p", "qrcode", "url"] {
            guard let raw = comps.queryItems?.first(where: { $0.name == name })?.value else { continue }
            let decoded = raw.removingPercentEncoding ?? raw
            if decoded.hasPrefix("http"), let u = URL(string: decoded) { return u }
        }
        return nil
    }

    /// 只改 scheme + schemacallback；完整保留 `p` / `qrcode` 及其它参数。
    static func buildLaunchURL(from raw: URL) -> URL? {
        guard var comps = URLComponents(url: raw, resolvingAgainstBaseURL: false) else { return nil }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path
        // 非 qlogin 的 mqq 链接：仍只换 callback，避免误伤
        if host == "ptlogin" || path.contains("qlogin") || comps.queryItems?.contains(where: {
            $0.name == "p" || $0.name == "qrcode"
        }) == true {
            comps.scheme = "wtloginmqq3"
            if comps.host == nil || comps.host?.isEmpty == true {
                comps.host = "ptlogin"
            }
            if comps.path.isEmpty { comps.path = "/qlogin" }
        }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "schemacallback" }
        items.append(URLQueryItem(name: "schemacallback", value: callbackURLString))
        comps.queryItems = items
        return comps.url
    }

    /// 解析 QQ schemacallback 回跳 → WebView 可打开的 https jump。
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
        if body.hasPrefix("(null)") {
            body = String(body.dropFirst(6))
        }
        if body.hasPrefix("?") || body.isEmpty {
            return mergeClientParams(into: pendingJumpURL ?? LoginURLs.oneClickJumpURL, from: url)
        }
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

    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        let launch = buildLaunchURL(from: raw) ?? raw
        pendingJumpURL = extractContinueURL(from: raw)
            ?? extractContinueURL(from: launch)
            ?? LoginURLs.oneClickJumpURL

        awaitingReturn = true
        var candidates: [URL] = [launch]
        if var c = URLComponents(url: launch, resolvingAgainstBaseURL: false) {
            let s = (c.scheme ?? "").lowercased()
            if s == "wtloginmqq3" {
                c.scheme = "wtloginmqq"
                if let u = c.url { candidates.append(u) }
            } else if s == "wtloginmqq" || s == "wtloginmqq2" {
                c.scheme = "wtloginmqq3"
                if let u = c.url { candidates.insert(u, at: 0) }
            }
        }
        for u in candidates where UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
            return true
        }
        UIApplication.shared.open(launch, options: [:], completionHandler: nil)
        return true
    }

    static func markReturned() { awaitingReturn = false }

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
