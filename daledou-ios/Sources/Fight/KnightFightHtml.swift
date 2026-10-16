import Foundation

/// 真源：`KnightFightReplayHtml.kt` — Act(`&Build:1;…`) → 阵容/战绩/过程 HTML。
/// 拼接首屏默认 `resolveSkills=false`（对齐 GameShellScreen 加速）；再后台解析技能中文名。
enum KnightFightHtml {
    private static let levelColors = [
        "#189FCB", "#F4B736", "#30CAAD", "#B39517", "#7192F3",
        "#DF5A1E", "#F14DCB", "#D13427", "#9D38D7", "#6B41D9",
    ]

    private static let knightElement: [String: String] = [
        "风云依旧": "土", "越女鹅": "水", "鹅晓峰": "阳", "鹅乔峰": "木",
        "发财鹅": "土", "福马鹅": "火", "笑红尘": "水", "胡斐": "金",
        "石破天": "土", "木岛主": "木", "行者鹅": "木", "斗酒僧": "火",
        "龙岛主": "水", "周芷若": "木", "张三丰": "火", "王处一": "金",
        "郭襄": "水", "张无忌": "火", "周伯通": "木", "梅超风": "土",
        "郭靖": "火", "金轮法王": "金", "杨过": "金", "小龙女": "水",
        "林朝英": "木", "李莫愁": "土", "李光弼": "火", "杜十三": "土",
        "欧阳锋": "水", "黄药师": "木", "王重阳": "水", "段智兴": "金",
        "圣诞老鹅": "土", "九品芝麻官": "木", "洪七公": "火", "李师师": "土",
        "燕青": "火", "断亦": "水", "染承": "金",
    ]

    private struct Fighter {
        let name: String
        let uin: String
        let level: Int
        let hp: Int
        let str: Int
        let agi: Int
        let spd: Int
        let skillIds: [Int]
        var skillNames: [String] = []
    }

    /// 同步快路径：不打技能页（`resolveSkills` 忽略，一律按 ID 展示）。
    static func toHtml(_ raw: String, resolveSkills: Bool = false) -> String {
        // 保留旧签名；真正解析走 toHtmlAsync。
        _ = resolveSkills
        return render(raw, skillLabel: { id in "\(id)" }, rosterNames: { ids in
            ids.prefix(8).map { "\($0)" }
        })
    }

    /// 真源：`KnightFightReplayHtml.toHtml(resolveSkills=…)` — 拉取 phonepk view 解析中文技能名。
    static func toHtmlAsync(
        _ raw: String,
        resolveSkills: Bool,
        cookie: String
    ) async -> String {
        if !resolveSkills || cookie.isEmpty {
            return toHtml(raw, resolveSkills: false)
        }
        var nameCache: [Int: String] = [:]
        func label(_ id: Int) async -> String {
            if let hit = nameCache[id] { return hit }
            let n = await KnightSkillPages.resolveName(id: id, cookie: cookie)
            nameCache[id] = n
            return n
        }
        return await renderAsync(raw, skillLabel: label) { ids in
            var out: [String] = []
            for id in ids.prefix(8) {
                out.append(await label(id))
            }
            return out
        }
    }

    /// 真源：`shouldAutoExpandKnightAttrs`
    static func shouldAutoExpand(
        url: String,
        phoneHtml: String = "",
        fromHuaShan: Bool = false,
        fromKnightFight: Bool = false
    ) -> Bool {
        if url.isEmpty { return false }
        let u = url.lowercased()
        if fromKnightFight { return true }
        if u.contains("knightarena") { return true }
        if u.contains("knightfight"),
           u.contains("view_my_replay") || u.contains("view_replay")
            || u.contains("view_top") || u.contains("view_feeds")
        {
            return true
        }
        let type = URLComponents(string: url)?
            .queryItems?.first(where: { $0.name == "type" })?.value ?? ""
        if type == "9" || type == "24" { return true }
        if fromHuaShan { return true }
        if phoneHtml.contains("华山论剑") || phoneHtml.contains("【华山】")
            || phoneHtml.contains("华山论剑场")
        {
            return true
        }
        if phoneHtml.range(
            of: #"战斗场景[：:][^<\n]{0,24}(?:华山|论剑)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }

    // MARK: - render

    private static func render(
        _ raw: String,
        skillLabel: (Int) -> String,
        rosterNames: ([Int]) -> [String]
    ) -> String {
        let act = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !act.isEmpty else { return "本局轮空或无战斗数据" }
        let builds = act.components(separatedBy: "&Build:1;").filter { $0.contains("&Player") }
        guard !builds.isEmpty else { return "无法解析战斗数据" }

        var records = "侠士战斗记录：<br />"
        var process = "战斗过程：<br />"
        var lastWinHtml = ""
        var seenSide1: [String: Fighter] = [:]
        var seenSide2: [String: Fighter] = [:]
        var side1Order: [String] = []
        var side2Order: [String] = []

        for seg in builds {
            let win = seg.contains("&Win:0;")
            let winHtml = win
                ? "<b><font color='red'>胜</font></b>"
                : "<b><font color='green'>负</font></b>"
            lastWinHtml = winHtml

            guard var left = parseSide(seg, player1: true),
                  var right = parseSide(seg, player1: false)
            else { continue }

            left.skillNames = rosterNames(left.skillIds)
            right.skillNames = rosterNames(right.skillIds)

            if seenSide1[left.name] == nil {
                seenSide1[left.name] = left
                side1Order.append(left.name)
            }
            if seenSide2[right.name] == nil {
                seenSide2[right.name] = right
                side2Order.append(right.name)
            }

            let tag = restrainTag(left.name, right.name)
            let lHp = "\(left.name)(血:<b><font color='red'>\(left.hp)</font></b>)"
            let rHp = "\(right.name)(血:<b><font color='red'>\(right.hp)</font></b>)"
            records += "(\(winHtml))\(tag)\(lHp) vs \(rHp)<br />"
            process += appendActProcess(seg: seg, left: left, right: right, skillLabel: skillLabel)
        }

        var rosters = "战斗结果：\(lastWinHtml)<br />"
        rosters += appendRoster(
            title: "阵容1侠士",
            list: side1Order.compactMap { seenSide1[$0] }
        )
        rosters += "<br />"
        rosters += appendRoster(
            title: "阵容2侠士",
            list: side2Order.compactMap { seenSide2[$0] }
        )
        return rosters + "<br />" + records + "<br />" + process
    }

    private static func renderAsync(
        _ raw: String,
        skillLabel: (Int) async -> String,
        rosterNames: ([Int]) async -> [String]
    ) async -> String {
        let act = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !act.isEmpty else { return "本局轮空或无战斗数据" }
        let builds = act.components(separatedBy: "&Build:1;").filter { $0.contains("&Player") }
        guard !builds.isEmpty else { return "无法解析战斗数据" }

        var records = "侠士战斗记录：<br />"
        var process = "战斗过程：<br />"
        var lastWinHtml = ""
        var seenSide1: [String: Fighter] = [:]
        var seenSide2: [String: Fighter] = [:]
        var side1Order: [String] = []
        var side2Order: [String] = []

        for seg in builds {
            let win = seg.contains("&Win:0;")
            let winHtml = win
                ? "<b><font color='red'>胜</font></b>"
                : "<b><font color='green'>负</font></b>"
            lastWinHtml = winHtml

            guard var left = parseSide(seg, player1: true),
                  var right = parseSide(seg, player1: false)
            else { continue }

            left.skillNames = await rosterNames(left.skillIds)
            right.skillNames = await rosterNames(right.skillIds)

            if seenSide1[left.name] == nil {
                seenSide1[left.name] = left
                side1Order.append(left.name)
            }
            if seenSide2[right.name] == nil {
                seenSide2[right.name] = right
                side2Order.append(right.name)
            }

            let tag = restrainTag(left.name, right.name)
            let lHp = "\(left.name)(血:<b><font color='red'>\(left.hp)</font></b>)"
            let rHp = "\(right.name)(血:<b><font color='red'>\(right.hp)</font></b>)"
            records += "(\(winHtml))\(tag)\(lHp) vs \(rHp)<br />"
            process += await appendActProcessAsync(
                seg: seg, left: left, right: right, skillLabel: skillLabel
            )
        }

        var rosters = "战斗结果：\(lastWinHtml)<br />"
        rosters += appendRoster(
            title: "阵容1侠士",
            list: side1Order.compactMap { seenSide1[$0] }
        )
        rosters += "<br />"
        rosters += appendRoster(
            title: "阵容2侠士",
            list: side2Order.compactMap { seenSide2[$0] }
        )
        return rosters + "<br />" + records + "<br />" + process
    }

    private static func parseSide(_ seg: String, player1: Bool) -> Fighter? {
        let parts = seg
            .replacingOccurrences(of: "&Player1:0;", with: "\u{0001}")
            .components(separatedBy: "&Player2:0;")
        guard parts.count >= 2 else { return nil }
        var raw: String
        if player1 {
            raw = parts[0]
            if let r = raw.range(of: "\u{0001}") {
                raw = String(raw[r.upperBound...])
            }
        } else {
            raw = parts[1]
        }
        raw = raw
            .components(separatedBy: "&Win").first?
            .components(separatedBy: "&Act").first?
            .trimmingCharacters(in: CharacterSet(charactersIn: ";")) ?? raw
        return parseFighter(raw)
    }

    private static func appendRoster(title: String, list: [Fighter]) -> String {
        guard let first = list.first else { return "" }
        var sb = "\(title)\(first.uin)：<br />"
        for (idx, f) in list.enumerated() {
            sb += "\(idx + 1).\(f.name)(等级:\(f.level))"
            sb += "(血:<b><font color='red'>\(f.hp)</font></b>,"
            sb += "力:\(colorLevel(f.str)),速:\(colorLevel(f.spd)),敏:\(colorLevel(f.agi)))"
            if !f.skillNames.isEmpty {
                sb += "<br />&emsp; \(f.skillNames.joined(separator: ", "))"
            } else if !f.skillIds.isEmpty {
                sb += "<br />&emsp; \(f.skillIds.map(String.init).joined(separator: ", "))"
            }
            sb += "<br />"
        }
        return sb
    }

    private static func parseFighter(_ raw: String) -> Fighter? {
        let bits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
            .components(separatedBy: ";")
        guard let head = bits.first, !head.isEmpty else { return nil }
        let name = head.components(separatedBy: "(").first?
            .trimmingCharacters(in: .whitespaces) ?? head
        let uin: String = {
            if let r = head.range(of: "(") {
                return "(" + String(head[r.upperBound...])
            }
            return ""
        }()
        func at(_ i: Int) -> String {
            guard i < bits.count else { return "" }
            return bits[i].trimmingCharacters(in: .whitespaces)
        }
        let level = Int(at(1)) ?? 0
        let hp = Int(at(2)) ?? 0
        let str = Int(at(3)) ?? 0
        let agi = Int(at(4)) ?? 0
        let spd = Int(at(5)) ?? 0
        var ids: [Int] = []
        if bits.count > 6 {
            for i in 6..<bits.count {
                let chunk = at(i)
                if chunk.isEmpty || chunk == "0" { continue }
                for p in chunk.split(separator: ",") {
                    if let id = Int(p.trimmingCharacters(in: .whitespaces)), id > 0 {
                        ids.append(id)
                    }
                }
            }
        }
        return Fighter(
            name: name, uin: uin, level: level, hp: hp,
            str: str, agi: agi, spd: spd, skillIds: Array(Set(ids))
        )
    }

    private static func colorLevel(_ v: Int) -> String {
        let idx: Int
        switch v {
        case ..<10: idx = 0
        case ..<20: idx = 1
        case ..<30: idx = 2
        case ..<40: idx = 3
        case ..<50: idx = 4
        case ..<60: idx = 5
        case ..<70: idx = 6
        case ..<80: idx = 7
        case ..<90: idx = 8
        default: idx = 9
        }
        return "<b><font color='\(levelColors[idx])'>\(v)</font></b>"
    }

    private static func restrainTag(_ a: String, _ b: String) -> String {
        guard let ea = knightElement[a], let eb = knightElement[b] else { return "" }
        let beats: String? = ["土": "水", "木": "土", "水": "火", "火": "金", "金": "木"][ea]
        let beatenBy: String? = ["土": "木", "木": "金", "水": "土", "火": "水", "金": "火"][ea]
        if eb == beats { return "[<b><font color='red'>克制</font></b>]" }
        if eb == beatenBy { return "[<b><font color='green'>被克</font></b>]" }
        return ""
    }

    private static func appendActProcess(
        seg: String,
        left: Fighter,
        right: Fighter,
        skillLabel: (Int) -> String
    ) -> String {
        guard let actRange = seg.range(of: "Act:") else { return "" }
        var actBody = String(seg[actRange.upperBound...])
        actBody = actBody.components(separatedBy: "&Win").first ?? actBody
        actBody = actBody.components(separatedBy: "&Build").first ?? actBody
        let rounds = actBody.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.contains("|") }
        var roundNo = 1
        var hpL = left.hp
        var hpR = right.hp
        var sb = ""
        for round in rounds {
            let pipes = round.replacingOccurrences(of: "|", with: "#").components(separatedBy: "#")
            guard let head0 = pipes.first else { continue }
            let head = head0.split(separator: ",").map(String.init)
            guard !head.isEmpty else { continue }
            let side0 = head[0] == "0"
            let atk = side0 ? left : right
            let def = side0 ? right : left
            var dmg = 0
            for pipe in pipes.dropFirst() {
                let nums = pipe.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if let cand = nums.filter({ (1...9999).contains($0) }).max() {
                    dmg = cand
                }
            }
            let skillId = head.compactMap(Int.init).first(where: { $0 >= 10 })
            let skillName = skillId.map { skillLabel($0) } ?? ""
            if side0 { hpR = max(0, hpR - dmg) } else { hpL = max(0, hpL - dmg) }
            let remain = side0 ? hpR : hpL
            sb += formatRound(
                roundNo: roundNo, atk: atk, def: def,
                skillLabel: skillName, dmg: dmg, remain: remain
            )
            roundNo += 1
            if roundNo > 80 { break }
        }
        return sb
    }

    private static func appendActProcessAsync(
        seg: String,
        left: Fighter,
        right: Fighter,
        skillLabel: (Int) async -> String
    ) async -> String {
        guard let actRange = seg.range(of: "Act:") else { return "" }
        var actBody = String(seg[actRange.upperBound...])
        actBody = actBody.components(separatedBy: "&Win").first ?? actBody
        actBody = actBody.components(separatedBy: "&Build").first ?? actBody
        let rounds = actBody.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.contains("|") }
        var roundNo = 1
        var hpL = left.hp
        var hpR = right.hp
        var sb = ""
        for round in rounds {
            let pipes = round.replacingOccurrences(of: "|", with: "#").components(separatedBy: "#")
            guard let head0 = pipes.first else { continue }
            let head = head0.split(separator: ",").map(String.init)
            guard !head.isEmpty else { continue }
            let side0 = head[0] == "0"
            let atk = side0 ? left : right
            let def = side0 ? right : left
            var dmg = 0
            for pipe in pipes.dropFirst() {
                let nums = pipe.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if let cand = nums.filter({ (1...9999).contains($0) }).max() {
                    dmg = cand
                }
            }
            let skillId = head.compactMap(Int.init).first(where: { $0 >= 10 })
            let skillName: String
            if let skillId {
                skillName = await skillLabel(skillId)
            } else {
                skillName = ""
            }
            if side0 { hpR = max(0, hpR - dmg) } else { hpL = max(0, hpL - dmg) }
            let remain = side0 ? hpR : hpL
            sb += formatRound(
                roundNo: roundNo, atk: atk, def: def,
                skillLabel: skillName, dmg: dmg, remain: remain
            )
            roundNo += 1
            if roundNo > 80 { break }
        }
        return sb
    }

    private static func formatRound(
        roundNo: Int,
        atk: Fighter,
        def: Fighter,
        skillLabel: String,
        dmg: Int,
        remain: Int
    ) -> String {
        var sb = "<b><font color='black'>回合\(roundNo)：</font></b>"
        sb += "\(atk.name)\(atk.uin)"
        if !skillLabel.isEmpty {
            sb += "使用技能<b><font color='blue'>\(skillLabel)</font></b>，"
        } else {
            sb += "发起攻击，"
        }
        sb += "击中\(def.name)"
        if dmg > 0 {
            sb += "，<b><font color='red'>HP-\(dmg)</font></b>"
            sb += remain <= 0
                ? " (HP余 0 )。中招身亡，实在是不堪一击！"
                : "(HP余\(remain))。"
        }
        sb += "<br />"
        return sb
    }
}
