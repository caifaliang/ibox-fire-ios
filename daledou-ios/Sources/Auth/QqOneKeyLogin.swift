import Foundation
import UIKit

/// QQ 一键登录 — 饭点 QQ_ONE_KEY 行为规格落地（非源码搬运）。
///
/// 竞品路径：清 Cookie → 打开 phonepk → 腾讯跳 authorize→style=35 →
/// 用户点页内「一键登录」→ 拦截 `wtloginmqq://ptlogin/qlogin?p=` →
/// 原生打开 `wtloginmqq://ptlogin/qlogin?p=<已编码jump>`（**不带** schemacallback）→
/// QQ 确认后 https 回跳（clientuin/clientkey/keyindex）写 Cookie。
enum QqOneKeyLogin {
    static let callbackScheme = "daledoulogin"
    static let callbackURLString = "daledoulogin://"
    static let callbackSchemeAlt = "com.daledou.ioslogin"

    private(set) static var awaitingReturn = false
    private(set) static var lastOpenedPEncoded: String?
    private(set) static var lastOpenedAt: Date?

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

    static func isXloginPage(_ url: URL?) -> Bool {
        guard let u = url, let host = u.host?.lowercased() else { return false }
        return host.contains("ptlogin2.qq.com") && u.path.lowercased().contains("xlogin")
    }

    // MARK: - Jump 校验（对齐饭点 V1.m.k）

    /// 出站 jump：ssl.ptlogin2/jump + 互联参数，尚无 clientuin（给 p= 用）
    static func isValidOutboundJump(_ raw: String) -> Bool {
        guard let parsed = parseJump(raw) else { return false }
        guard parsed.clientuin == nil, parsed.clientkey == nil, parsed.keyindex == nil else {
            return false
        }
        return true
    }

    /// 回壳 jump：同上参数 + clientuin/clientkey/keyindex
    static func isValidReturnJump(_ url: URL) -> Bool {
        guard let parsed = parseJump(url.absoluteString) else { return false }
        guard let uin = parsed.clientuin, let key = parsed.clientkey, let idx = parsed.keyindex else {
            return false
        }
        guard uin.range(of: #"^[1-9][0-9]{4,19}$"#, options: .regularExpression) != nil else {
            return false
        }
        guard idx.range(of: #"^[0-9]{1,3}$"#, options: .regularExpression) != nil else {
            return false
        }
        return !key.isEmpty && key.count <= 1024
    }

    private struct JumpParts {
        var clientuin: String?
        var clientkey: String?
        var keyindex: String?
    }

    private static func parseJump(_ raw: String) -> JumpParts? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s) ?? URL(string: s.removingPercentEncoding ?? s) else {
            return nil
        }
        guard (url.scheme ?? "").lowercased() == "https",
              (url.host ?? "").lowercased() == "ssl.ptlogin2.qq.com",
              url.path == "/jump" else {
            return nil
        }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        func v(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        guard v("pt_report") == "1",
              v("pt_aid") == "716027609",
              v("daid") == "383",
              v("style") == "35",
              v("pt_3rd_aid") == LoginURLs.qqAppId else {
            return nil
        }
        guard let u1 = v("u1"), let u1url = URL(string: u1),
              (u1url.scheme ?? "").lowercased() == "https",
              (u1url.host ?? "").lowercased() == "connect.qq.com" else {
            return nil
        }
        let path = u1url.path
        if !path.isEmpty, path != "/" { return nil }
        if u1url.query != nil || u1url.fragment != nil { return nil }
        return JumpParts(
            clientuin: v("clientuin"),
            clientkey: v("clientkey"),
            keyindex: v("keyindex")
        )
    }

    // MARK: - 从 wtlogin URL 取 p=

    /// 饭点 `V1.m.h`：仅允许 query 键 p / schemacallback；返回 **原始编码** 的 p 值
    static func encodedPJump(fromWtlogin url: URL) -> String? {
        guard isWtloginScheme(url.scheme) else { return nil }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // 手工拆 rawQuery，保留 p 的已编码形态（饭点用 substring 不二次 decode 再 encode）
        guard let rawQuery = comps.percentEncodedQuery ?? comps.query else { return nil }
        var pEncoded: String?
        var keys = Set<String>()
        for part in rawQuery.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = String(pair[0]).removingPercentEncoding ?? String(pair[0])
            keys.insert(name)
            if name == "p" {
                pEncoded = String(pair[1])
            }
        }
        guard keys.isSubset(of: ["p", "schemacallback"]), let enc = pEncoded, !enc.isEmpty else {
            return nil
        }
        let jump = enc.removingPercentEncoding ?? enc
        guard isValidOutboundJump(jump) else { return nil }
        return enc
    }

    /// 饭点：`wtloginmqq://ptlogin/qlogin?p=` + 已编码 jump，**不加** schemacallback
    @discardableResult
    static func openWithEncodedP(_ pEncoded: String) -> Bool {
        let enc = pEncoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enc.isEmpty else { return false }
        let jump = enc.removingPercentEncoding ?? enc
        guard isValidOutboundJump(jump) else { return false }

        if lastOpenedPEncoded == enc,
           let t = lastOpenedAt,
           Date().timeIntervalSince(t) < 1.5 {
            return true
        }

        let s = "wtloginmqq://ptlogin/qlogin?p=\(enc)"
        guard let launch = URL(string: s) ?? (NSURL(string: s) as URL?) else { return false }

        lastOpenedPEncoded = enc
        lastOpenedAt = Date()
        awaitingReturn = true

        var candidates = [launch]
        if var c = URLComponents(url: launch, resolvingAgainstBaseURL: false) {
            c.scheme = "wtloginmqq3"
            if let u = c.url { candidates.insert(u, at: 0) }
        }
        for u in candidates where UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
            return true
        }
        UIApplication.shared.open(launch, options: [:], completionHandler: nil)
        return true
    }

    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        guard let enc = encodedPJump(fromWtlogin: raw) else { return false }
        return openWithEncodedP(enc)
    }

    /// schemacallback 体里若带 https 则返回（饭点也可走 https returnRoute）
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
        if body.hasPrefix("(null)") { body = String(body.dropFirst(6)) }
        if body.hasPrefix("?") || body.isEmpty { return nil }
        if body.hasPrefix("http://") || body.hasPrefix("https://") {
            return URL(string: body)
        }
        if body.contains(".") {
            return URL(string: "https://" + body)
        }
        return nil
    }

    static func markReturned() { awaitingReturn = false }

    static func clearPending() {
        awaitingReturn = false
        lastOpenedPEncoded = nil
        lastOpenedAt = nil
    }
}
