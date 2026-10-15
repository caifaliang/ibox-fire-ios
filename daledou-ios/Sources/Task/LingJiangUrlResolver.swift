import Foundation

/// 真源：`LingJiangUrlResolver.kt`
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
            if picked.hasPrefix("http") { return Plan(urls: [picked]) }
        }
        return Plan()
    }

    static func applyRandom(_ url: String) -> String {
        guard url.contains(randomSplit) else { return url }
        let parts = url.components(separatedBy: randomSplit)
        guard parts.count >= 2 else { return url }
        let a = parts[0].trimmingCharacters(in: .whitespaces)
        let b = parts[1].trimmingCharacters(in: .whitespaces)
        let pick = Int.random(in: 0..<7) == 0 ? b : a
        return pick.isEmpty ? (a.isEmpty ? b : a) : pick
    }

    static func oneClickAllowed(type: Int, week: Int, hour: Int) -> Bool {
        switch type {
        case 18: return (week == 5 && hour > 20) || week == 6 || week == 7 || (week == 1 && hour < 6)
        case 25: return week == 6 && hour > 6 && hour < 19
        case 26: return week == 7 && hour > 6 && hour < 19
        case 43: return (13...21).contains(hour)
        default: return true
        }
    }

    static func fillFormat(template: String, body: String) -> String? {
        let t = template.trimmingCharacters(in: .whitespaces)
        if t == "auto" || !t.hasPrefix("http") { return nil }
        if !t.contains("%s") { return t }
        var out = t
        guard let re = try? NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)=%s"#) else { return nil }
        let ns = t as NSString
        let names = re.matches(in: t, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
        if names.isEmpty { return nil }
        for name in names {
            guard let value = valueFor(name, body: body) else { return nil }
            if let r = out.range(of: "%s") {
                out.replaceSubrange(r, with: value)
            }
        }
        return out
    }

    private static func valueFor(_ name: String, body: String) -> String? {
        let aliases: [String] = {
            switch name {
            case "team_id": return ["team_id", "id", "team"]
            case "type_id": return ["type_id", "type", "id"]
            case "goods_id": return ["goods_id", "id", "goodsid"]
            case "faction": return ["faction", "faction_id", "id"]
            case "season": return ["season", "season_id"]
            case "weapon_id": return ["weapon_id", "id"]
            case "player_uin", "recipient", "receiver": return [name, "uin", "puin"]
            case "section_id": return ["section_id", "section"]
            case "round_id": return ["round_id", "round"]
            case "poetry": return ["poetry", "poem", "answer", "id"]
            default: return [name, "id"]
            }
        }()
        for key in aliases {
            if let v = CombatLog.jsonField(body, key), !v.isEmpty, v != "0" { return v }
            if let n = CombatLog.jsonInt(body, key), n > 0 { return "\(n)" }
        }
        return nil
    }
}
