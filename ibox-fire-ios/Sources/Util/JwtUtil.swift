import Foundation
import CryptoKit

enum JwtUtil {
    static func normalize(_ token: String) -> String {
        var t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("bearer ") {
            t = String(t.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t.filter { !$0.isWhitespace }
    }

    static func bearer(_ token: String) -> String {
        "Bearer \(normalize(token))"
    }

    private static func payload(_ token: String) -> [String: Any]? {
        let t = normalize(token)
        let parts = t.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var p = String(parts[1])
        while p.count % 4 != 0 { p += "=" }
        guard let data = Data(base64Encoded: p, options: [.ignoreUnknownCharacters])
                ?? Data(base64URLEncoded: p) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func uid(_ token: String) -> Int64? {
        guard let obj = payload(token) else { return nil }
        if let n = obj["userId"] as? NSNumber { return n.int64Value }
        if let s = obj["userId"] as? String { return Int64(s) }
        return nil
    }

    static func exp(_ token: String) -> Int64? {
        guard let obj = payload(token), let n = obj["exp"] as? NSNumber else { return nil }
        return n.int64Value
    }

    static func isExpired(_ token: String, skewSec: Int64 = 30) -> Bool {
        guard let e = exp(token) else { return false }
        return Int64(Date().timeIntervalSince1970) >= e - skewSec
    }

    static func isAuthFail(code: Int64, message: String = "") -> Bool {
        if code == 401 { return true }
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty { return false }
        if m.localizedCaseInsensitiveContains("HTTP 403") { return false }
        let lower = m.lowercased()
        if lower.contains("unauthorized") { return true }
        if lower.contains("token") && (m.contains("过期") || m.contains("失效") || lower.contains("invalid") || lower.contains("expired")) {
            return true
        }
        return m.contains("登录过期") || m.contains("重新登录") || m.contains("未登录") || m.contains("鉴权") || m.contains("认证失败")
    }
}

extension Data {
    init?(base64URLEncoded str: String) {
        var s = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}

func todayFireAtEpochSec(h: Int, m: Int, s: Int) -> Int64 {
    var cal = Calendar.current
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    var c = cal.dateComponents([.year, .month, .day], from: Date())
    c.hour = h; c.minute = m; c.second = s
    guard let d = cal.date(from: c) else { return Int64(Date().timeIntervalSince1970) }
    return Int64(d.timeIntervalSince1970)
}

func bjTimeString() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Shanghai")
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

func md5Hex(_ s: String) -> String {
    let digest = Insecure.MD5.hash(data: Data(s.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
