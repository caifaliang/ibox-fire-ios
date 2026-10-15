import Foundation

enum LingJiangUrlResolver {
    static let formatSplit = "格式化"
    private static let randomSplit = "随机"

    struct Plan {
        var urls: [String] = []
        var formatFirst: String?
        var formatSecondTemplate: String?
    }

    static func plan(_ item: LingJiangItem) -> Plan {
        if !item.urlList.isEmpty {
            return Plan(urls: item.urlList.map { applyRandom($0.trimmingCharacters(in: .whitespaces)) }
                .filter { $0.hasPrefix("http") })
        }
        let fmt = item.formatUrl
        if item.url.isEmpty && fmt.contains(formatSplit) {
            let parts = fmt.components(separatedBy: formatSplit)
            let first = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let second = parts.dropFirst().joined(separator: formatSplit).trimmingCharacters(in: .whitespaces)
            if first.hasPrefix("http"), !second.isEmpty {
                return Plan(urls: [], formatFirst: first, formatSecondTemplate: second)
            }
        }
        if item.url.hasPrefix("http") || item.url.contains(randomSplit) {
            let picked = applyRandom(item.url.trimmingCharacters(in: .whitespaces))
            if picked.hasPrefix("http") {
                return Plan(urls: [picked])
            }
        }
        return Plan()
    }

    static func applyRandom(_ url: String) -> String {
        guard url.contains(randomSplit) else { return url }
        let parts = url.components(separatedBy: randomSplit)
        guard parts.count >= 2 else { return url }
        let a = parts[0].trimmingCharacters(in: .whitespaces)
        let b = parts.dropFirst().joined(separator: randomSplit).trimmingCharacters(in: .whitespaces)
        let pick = Int.random(in: 0..<7) == 0 ? b : a
        return pick.isEmpty ? (a.isEmpty ? b : a) : pick
    }

    /// week: 1=周一 … 7=周日（Calendar 需转换）
    static func oneClickAllowed(type: Int, week: Int, hour: Int) -> Bool {
        switch type {
        case 18:
            return (week == 5 && hour > 20) || week == 6 || week == 7 || (week == 1 && hour < 6)
        case 25:
            return week == 6 && hour > 6 && hour < 19
        case 26:
            return week == 7 && hour > 6 && hour < 19
        case 43:
            return (13...21).contains(hour)
        default:
            return true
        }
    }

    static func fillFormat(template: String, body: String) -> String? {
        let t = template.trimmingCharacters(in: .whitespaces)
        if t == "auto" || !t.hasPrefix("http") { return nil }
        if !t.contains("%s") { return t }
        guard let re = try? NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)=%s"#) else { return nil }
        let ns = t as NSString
        let matches = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        var out = t
        for m in matches {
            guard m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: t) else { return nil }
            let name = String(t[r])
            guard let value = valueFor(name, body: body) else { return nil }
            if let range = out.range(of: "%s") {
                out.replaceSubrange(range, with: value)
            }
        }
        return out
    }

    private static func valueFor(_ name: String, body: String) -> String? {
        let aliases: [String]
        switch name {
        case "team_id": aliases = ["team_id", "id", "team"]
        case "type_id": aliases = ["type_id", "type", "id"]
        case "goods_id": aliases = ["goods_id", "id", "goodsid"]
        case "weapon_id": aliases = ["weapon_id", "id"]
        default: aliases = [name, "id"]
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
           let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in aliases {
                if let s = obj[key] as? String, !s.isEmpty, s != "0" { return s }
                if let n = obj[key] as? Int, n > 0 { return "\(n)" }
                if let n = obj[key] as? NSNumber, n.intValue > 0 { return "\(n.intValue)" }
            }
        }
        for key in aliases {
            if let re = try? NSRegularExpression(pattern: #"[?&]\#(NSRegularExpression.escapedPattern(for: key))=([^&\"'<>]+)"#, options: .caseInsensitive),
               let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let r = Range(m.range(at: 1), in: body) {
                let v = String(body[r])
                if !v.isEmpty { return v }
            }
        }
        return nil
    }
}
