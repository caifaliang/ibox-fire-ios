import Foundation

/// 轻量 RefLog：从 HTML/JSON 抽可读行，禁止把整段 JSON 甩进日志。
enum CombatLog {
    static func fromBody(_ raw: String) -> String {
        if let msg = jsonField(raw, "msg"), !msg.isEmpty { return msg }
        let plain = raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(plain.prefix(80))
    }

    static func brLine(_ raw: String, _ needle: String) -> String {
        let parts = raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
        for p in parts {
            let t = p.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if t.contains(needle) { return String(t.prefix(80)) }
        }
        if raw.contains(needle) {
            return String(fromBody(raw).prefix(80))
        }
        return ""
    }

    static func prefer(_ raw: String, _ needles: String...) -> String {
        for n in needles {
            let hit = brLine(raw, n)
            if !hit.isEmpty { return hit }
        }
        return fromBody(raw)
    }

    static func jsonField(_ raw: String, _ key: String) -> String? {
        let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
        if let m = raw.range(of: pattern, options: .regularExpression) {
            let s = String(raw[m])
            if let r = s.range(of: #""[^"]*"$"#, options: .regularExpression) {
                return String(s[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        let num = "\"\(key)\"\\s*:\\s*(-?\\d+)"
        if let m = raw.range(of: num, options: .regularExpression) {
            let s = String(raw[m])
            if let r = s.range(of: #"-?\d+$"#, options: .regularExpression) {
                return String(s[r])
            }
        }
        return nil
    }

    static func jsonInt(_ raw: String, _ key: String) -> Int? {
        jsonField(raw, key).flatMap(Int.init)
    }
}
