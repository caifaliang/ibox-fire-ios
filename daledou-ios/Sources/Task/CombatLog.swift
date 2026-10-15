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

    /// 抽取 JSON 数组 `"name":[{...},{...}]` 中的对象切片。
    static func jsonChunks(_ body: String, _ arrayName: String) -> [String] {
        guard let keyAt = body.range(of: "\"\(arrayName)\"")?.lowerBound else { return [] }
        guard let openRel = body[keyAt...].firstIndex(of: "[") else { return [] }
        var depth = 0
        var end = openRel
        var i = openRel
        while i < body.endIndex {
            let c = body[i]
            if c == "[" { depth += 1 }
            else if c == "]" {
                depth -= 1
                if depth == 0 { end = i; break }
            }
            i = body.index(after: i)
        }
        let slice = String(body[openRel...end])
        var out: [String] = []
        var d = 0
        var start: String.Index?
        var j = slice.startIndex
        while j < slice.endIndex {
            let c = slice[j]
            if c == "{" {
                if d == 0 { start = j }
                d += 1
            } else if c == "}" {
                d -= 1
                if d == 0, let s = start {
                    out.append(String(slice[s...j]))
                    start = nil
                }
            }
            j = slice.index(after: j)
        }
        return out
    }
}
