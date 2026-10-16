import Foundation

/// 真源：`QunXiaLuXiangScreens` — 届数 / view_top / 对阵解析。
enum QunXiaActions {
    static let weapons = ["龙雀", "死寂", "风刃", "霸皇", "鬼鳍"]
    static let regions = ["东邪", "西毒", "中神", "南帝", "北丐", "总冠军"]

    struct TopIdParts {
        let period: Int
        let weapon: Int
        let region: Int
    }

    struct Slot: Identifiable {
        var id: String { "\(uin)-\(replayId)-\(name)" }
        let name: String
        let uin: String
        let replayId: String
        var playable: Bool { !replayId.isEmpty }
    }

    struct Pack {
        let period: Int
        let slots: [Slot]
        let tip: String
    }

    static func isTop8Url(_ url: String?) -> Bool {
        guard let url, !url.isEmpty else { return false }
        let u = url.lowercased()
        guard u.contains("knightfight") else { return false }
        return u.contains("op=view_top")
            || u.contains("op=showknightfight")
            || u.contains("view_top")
    }

    static func parseTopIdFromUrl(_ url: String?) -> TopIdParts? {
        guard let url, !url.isEmpty else { return nil }
        let re = try? NSRegularExpression(pattern: #"[?&]id=(\d+)"#)
        let ns = url as NSString
        guard let m = re?.firstMatch(in: url, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        return parseTopId(ns.substring(with: m.range(at: 1)))
    }

    static func parseTopId(_ id: String) -> TopIdParts? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let re = try? NSRegularExpression(pattern: #"^(\d+)0([0-5])0([0-4])$"#)
        let ns = trimmed as NSString
        guard let match = re?.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 4,
              let p = Int(ns.substring(with: match.range(at: 1))), p > 0,
              let region = Int(ns.substring(with: match.range(at: 2))),
              let weapon = Int(ns.substring(with: match.range(at: 3)))
        else { return nil }
        return TopIdParts(period: p, weapon: weapon, region: region)
    }

    static func load(
        seedUrl: String?,
        weapon: Int,
        region: Int,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> Pack {
        let seed = parseTopIdFromUrl(seedUrl)
        let saved = FeatureToggleStore.shared.getInt("qunxia_luxiang", "last_period")
        let (period, how) = await resolvePeriod(seed: seed, saved: saved, cookie: cookie)
        if period <= 0 {
            onLog(how)
            return Pack(period: 0, slots: [], tip: how.isEmpty ? "未获取到赛季 id" : how)
        }
        if FeatureToggleStore.shared.getBool("qunxia_luxiang", "cb_start") {
            FeatureToggleStore.shared.setInt("qunxia_luxiang", "last_period", period)
        }
        let body = await fetchViewTop(period: period, weapon: weapon, region: region, cookie: cookie)
        let slots = parseSlots(body)
        let plays = slots.filter(\.playable).count
        let tip: String
        if plays > 0 {
            tip = "第\(period)届 · \(plays) 场可回放"
        } else if !slots.isEmpty {
            tip = "第\(period)届 · 对阵已出，录像未挂"
        } else if body.isEmpty {
            tip = "赛况接口空响应"
        } else {
            tip = CombatLog.fromBody(body).ifBlankMe("本赛区暂无录像（换武器/赛区）")
        }
        onLog("第\(period)届 \(weapons[safe: weapon] ?? "?")/\(regions[safe: region] ?? "?") \(plays)场")
        return Pack(period: period, slots: slots.filter(\.playable), tip: tip)
    }

    static func replayPetUrl(replayId: String) -> String {
        "https://fight.pet.qq.com/cgi-bin/petpk?cmd=knightfight&op=view_replay&id=\(replayId)"
    }

    // MARK: - private

    private static func resolvePeriod(
        seed: TopIdParts?,
        saved: Int,
        cookie: String
    ) async -> (Int, String) {
        if let seed, seed.period > 0 {
            return (seed.period, "来自游戏页 id")
        }
        let tries: [(String, [String: String])] = [
            ("pet", ["op": "showknightfight", "groundid": "0"]),
            ("phone", ["op": "showknightfight", "groundid": "0"]),
            ("pet2", ["op": "showknightfight"]),
        ]
        var hints: [String] = []
        for (tag, extra) in tries {
            let body: String
            if tag.hasPrefix("phone") {
                body = await LedouCGI.getPhonePk(cmd: "knightfight", extra: extra, cookie: cookie).1
            } else {
                body = await LedouCGI.getPetPk(cmd: "knightfight", extra: extra, cookie: cookie).1
            }
            if let p = extractPeriod(body) {
                return (p, "\(tag) showknightfight")
            }
            hints.append("\(tag):\(String(body.prefix(24)))")
        }
        if saved > 0 {
            return (saved, "接口失败，用本地届 \(saved)")
        }
        return (0, "未获取到赛季 id（\(hints.joined(separator: " | "))）")
    }

    private static func fetchViewTop(
        period: Int,
        weapon: Int,
        region: Int,
        cookie: String
    ) async -> String {
        let id = "\(period)0\(region)0\(weapon)"
        let pet = await LedouCGI.getPetPk(
            cmd: "knightfight", extra: ["op": "view_top", "id": id], cookie: cookie
        ).1
        if pet.contains("\"info\"") || pet.contains("\"rep\"") || pet.contains("view_replay") {
            return pet
        }
        let phone = await LedouCGI.getPhonePk(
            cmd: "knightfight", extra: ["op": "view_top", "id": id], cookie: cookie
        ).1
        return phone.isEmpty ? pet : phone
    }

    private static func extractPeriod(_ body: String) -> Int? {
        if body.isEmpty { return nil }
        let ns = body as NSString
        let patterns = [
            #""period"\s*:\s*"?(\d{3,6})"?"#,
            #"第\s*(\d{3,6})\s*届"#,
        ]
        for pat in patterns {
            let re = try? NSRegularExpression(pattern: pat)
            if let match = re?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2,
               let p = Int(ns.substring(with: match.range(at: 1))), p > 0 {
                return p
            }
        }
        return nil
    }

    private static func parseSlots(_ body: String) -> [Slot] {
        var out: [Slot] = []
        let re = try? NSRegularExpression(pattern: #"\{[^{}]*\}"#)
        let ns = body as NSString
        re?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let raw = ns.substring(with: m.range)
            let name = jsonLoose(raw, "name")
            let uin = jsonLoose(raw, "uin")
            let rep = jsonLoose(raw, "rep")
            if name.isEmpty && uin.isEmpty && rep.isEmpty { return }
            out.append(Slot(name: name, uin: uin, replayId: rep))
        }
        return out
    }

    private static func jsonLoose(_ obj: String, _ key: String) -> String {
        let re = try? NSRegularExpression(pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"([^\"]*)\"")
        let ns = obj as NSString
        if let m = re?.firstMatch(in: obj, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        let re2 = try? NSRegularExpression(pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*([^\",}\\s]+)")
        if let m = re2?.firstMatch(in: obj, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        return ""
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
