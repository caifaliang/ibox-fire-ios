import Foundation

/// 对齐 Android AnnounceParser — 从公告正文提取 P1/P2/P3 锁单目标。
enum AnnounceParser {
    struct LockTargets {
        var p1: [String]
        var p2: [String]
        var p3: [String]
        var all: [String]
    }

    static func stripHtml(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        if let re = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        while s.contains("\n\n\n") { s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractLockTargets(title: String, contentHtml: String) -> LockTargets {
        var plain = stripHtml(contentHtml)
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            plain = title.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + plain
        }
        var skip = Set<String>()
        let skipRe = try? NSRegularExpression(pattern: "^(?:合成目标|空投目标|空投发放|奖励)[:：]", options: [])
        let nameRe = try? NSRegularExpression(pattern: "《([^》]+)》", options: [])
        for line in plain.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if skipRe?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
                nameRe?.matches(in: t, range: NSRange(t.startIndex..., in: t)).forEach { m in
                    if let r = Range(m.range(at: 1), in: t) { skip.insert(String(t[r])) }
                }
            }
        }
        func filt(_ xs: [String]) -> [String] { xs.filter { !skip.contains($0) } }
        let p1 = filt(extractP1(plain))
        let p2 = filt(extractP2(plain))
        let p3 = filt(extractP3(plain))
        var all: [String] = []
        var seen = Set<String>()
        for n in p1 + p2 + p3 where seen.insert(n).inserted { all.append(n) }
        return LockTargets(p1: p1, p2: p2, p3: p3, all: all)
    }

    private static func extractP1(_ plain: String) -> [String] {
        let pattern = #"《([^》]+)》[^《]{0,40}(?:提高售限价|最高寄售限价|提高.*?限价)|(?:提高售限价|最高寄售限价|提高.*?限价)[^《]{0,40}《([^》]+)》"#
        return regexNames(plain, pattern: pattern, groups: [1, 2])
    }

    private static func extractP2(_ plain: String) -> [String] {
        let pattern = #"(?:每)?持有(?:藏品)?【?《([^》]+)》】?(?:\s*/\s*《([^》]+)》)?|持有藏品【([^】]+)】"#
        return regexNames(plain, pattern: pattern, groups: [1, 2, 3])
    }

    private static func extractP3(_ plain: String) -> [String] {
        guard let hdr = plain.range(of: "合成材料", options: .caseInsensitive) else { return [] }
        let tail = String(plain[hdr.upperBound...])
        var names: [String] = []
        let endRe = try? NSRegularExpression(pattern: "^(?:合成时间|最大合成|活动[一二三]|通道|空投目标|空投资格|合成目标|注[:：]|提示[:：])", options: [])
        let nameRe = try? NSRegularExpression(pattern: "《([^》]+)》", options: [])
        for line in tail.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if endRe?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { break }
            nameRe?.matches(in: t, range: NSRange(t.startIndex..., in: t)).forEach { m in
                if let r = Range(m.range(at: 1), in: t) { names.append(String(t[r])) }
            }
        }
        return names
    }

    private static func regexNames(_ text: String, pattern: String, groups: [Int]) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            for g in groups where g < m.numberOfRanges {
                if let r = Range(m.range(at: g), in: text) {
                    let n = String(text[r]).trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty, seen.insert(n).inserted { out.append(n) }
                }
            }
        }
        return out
    }
}
