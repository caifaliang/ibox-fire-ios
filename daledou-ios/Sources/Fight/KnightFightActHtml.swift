import Foundation

/// 真源：`KnightFightActHtml.java` — Act 协议战斗过程。
/// 技能 id 在 `c[1]`（type=5）；武器 id 在 `a[2]` / `b[1]`（type=3）。
enum KnightFightActHtml {
    /// - Parameters:
    ///   - skillName: `(id, kind)` → 显示名；`kind` 为 `"weapon"` | `"skill"`
    static func format(
        _ raw: String,
        skillName: (String, String) -> String
    ) -> String {
        if raw.isEmpty { return "战斗过程：<br />" }
        var sb = "战斗过程：<br />"
        var roundNo = 1
        for seg in raw.components(separatedBy: "&Build:1;") {
            guard seg.contains("Player"), seg.contains("Act:") else { continue }
            guard let p1 = parsePlayer(seg, key: "Player1"),
                  let p2 = parsePlayer(seg, key: "Player2")
            else { continue }
            var hp1 = p1.hp
            var hp2 = p2.hp
            let act = extractActBody(seg)
            guard !act.isEmpty else { continue }

            for rawRound in act.split(separator: ";") {
                var round = String(rawRound).trimmingCharacters(in: .whitespaces)
                if round.isEmpty || !round.contains("|") { continue }
                var suffix = ""
                if let star = round.firstIndex(of: "*") {
                    suffix = String(round[star...])
                    round = String(round[..<star])
                }
                let feignBySuffix = suffix.contains(",2,")
                let pipes = round.components(separatedBy: "|")
                guard pipes.count >= 3 else { continue }

                let a = pipes[0].components(separatedBy: ",")
                let b = pipes[1].components(separatedBy: ",")
                let c = pipes[2].components(separatedBy: ",")
                let d = pipes.count >= 4 ? pipes[3].components(separatedBy: ",") : []
                guard !a.isEmpty else { continue }

                let side0 = nz(a, 0) == "0"
                let atkName = side0 ? p1.label : p2.label
                let defName = side0 ? p2.label : p1.label
                var atkHp = side0 ? hp1 : hp2
                var defHp = side0 ? hp2 : hp1

                var line = "<b><font color='black'>回合\(roundNo)：</font></b>"

                // 虹吸 / 62
                if a.count == 2, nz(a, 1) == "62" {
                    var trailDmgs: [Int] = []
                    var specAt = -1
                    for pi in 0..<pipes.count {
                        if pipes[pi].hasPrefix("1,0,0,") {
                            specAt = pi
                            break
                        }
                    }
                    if specAt >= 0 {
                        for pi in (specAt + 1)..<pipes.count {
                            guard let td = parseTrailDmg(pipes[pi]) else { break }
                            trailDmgs.append(td)
                        }
                    }
                    line += atkName + "使用"
                    if specAt >= 0 {
                        line += "<b><font color='blue'>触发专精控制武器，</font></b>"
                    }
                    if !isSide(nz(b, 1)) {
                        line += "武器" + skillName(nz(b, 1), "weapon") + "，"
                    } else {
                        line += "空手，"
                    }
                    if let heal = positiveInt(b, 0) {
                        atkHp += heal
                        line += atkName
                        line += "<b><font color='green'>在击中对方时触发吸血，HP+\(heal)</font></b>"
                        line += "（HP余\(atkHp)）。"
                    }
                    if trailDmgs.isEmpty {
                        var dmg = intOr(d, 13, 0)
                        if dmg <= 0 { dmg = intOr(b, 0, 0) }
                        let feign = feignBySuffix || eq(d, 7, "2683")
                        var remain = defHp - dmg
                        if remain <= 0 { remain = feign ? (feignBySuffix ? 60 : 1) : 0 }
                        line += defName + "吃了一招，"
                        line += "<b><font color='red'>HP-\(dmg)"
                        if feign, remain > 0, remain <= 60 {
                            line += "，\(defName)顺势倒地，气息紧闭，呈假死状（HP余\(remain)）。</font></b>"
                        } else if remain == 0 {
                            line += " (HP余 0 )。中招身亡，实在是不堪一击！</font></b>"
                        } else {
                            line += "（HP余\(remain)）。</font></b>"
                        }
                        defHp = max(0, remain)
                    } else {
                        for (ti, dmg) in trailDmgs.enumerated() {
                            let last = ti == trailDmgs.count - 1
                            if ti > 0, specAt >= 0 {
                                line += "触发专精控制武器，"
                                if !isSide(nz(b, 1)) {
                                    line += "一记" + skillName(nz(b, 1), "weapon") + "掠向对方。"
                                }
                            }
                            var remain = defHp - dmg
                            let feign = last && (feignBySuffix || eq(d, 7, "2683"))
                            if remain <= 0 { remain = feign ? (feignBySuffix ? 60 : 1) : 0 }
                            line += defName + "吃了一招，"
                            line += "<b><font color='red'>HP-\(dmg)"
                            if feign, remain > 0 {
                                line += "，\(defName)顺势倒地，气息紧闭，呈假死状（HP余\(remain)）。</font></b>"
                            } else if remain == 0 {
                                line += " (HP余 0 )。中招身亡，实在是不堪一击！</font></b>"
                            } else {
                                line += "（HP余\(remain)）。</font></b>"
                            }
                            defHp = max(0, remain)
                        }
                    }
                    if side0 { hp1 = atkHp; hp2 = defHp } else { hp2 = atkHp; hp1 = defHp }
                    sb += line + "<br />"
                    roundNo += 1
                    continue
                }

                let feign = feignBySuffix || eq(c, 7, "2683")
                let life3170 = eq(c, 7, "3170") || (c.count >= 8 && nz(c, 7) == "3170")

                if let poison = positiveInt(c, 5), !isSide(nz(c, 5)) {
                    var pr = atkHp - poison
                    if pr < 0 { pr = feign ? 1 : 0 }
                    line += atkName
                    line += "<b><font color='blue'>身中剧毒，</font></b>"
                    line += "<b><font color='red'>HP-\(poison)"
                    line += " (HP余\(pr))。</font></b>"
                    atkHp = pr
                    if pr <= 0 {
                        line += "中招身亡，实在是不堪一击！<br />"
                        sb += line
                        if side0 { hp1 = 0 } else { hp2 = 0 }
                        roundNo += 1
                        continue
                    }
                }

                if eq(a, 1, "32") || eq(a, 1, "81") {
                    line += atkName
                    line += "<b><font color='blue'>凝神摒气触发暴击。</font></b>"
                }

                line += atkName
                if eq(c, 3, "2") {
                    line += "<b><font color='blue'>原地转身一圈，掷出</font></b>"
                } else if eq(c, 3, "3") {
                    line += "<b><font color='blue'>触发连击。</font></b>使用"
                } else {
                    line += "使用"
                }
                line += describeAction(a: a, b: b, c: c, skillName: skillName)

                let c4 = intOr(c, 4, 0)
                if c4 < 0 {
                    let healSelf = -c4
                    atkHp += healSelf
                    line += "<b><font color='green'>HP+\(healSelf)</font></b>"
                    line += " (HP余\(atkHp))。"
                    if side0 { hp1 = atkHp; hp2 = defHp } else { hp2 = atkHp; hp1 = defHp }
                    sb += line + "<br />"
                    roundNo += 1
                    continue
                }

                if isDodge(c) {
                    line += defName + "侧身一闪，躲过猛烈一击。"
                    line += appendLostWeapon(b: b, defName: defName, skillName: skillName)
                    sb += line + "<br />"
                    if side0 { hp1 = atkHp; hp2 = defHp } else { hp2 = atkHp; hp1 = defHp }
                    roundNo += 1
                    continue
                }

                var dmg: Int
                var healDef = 0
                if life3170, !d.isEmpty {
                    dmg = intOr(d, 6, 0)
                    healDef = intOr(d, 0, 0)
                    if dmg <= 0 { dmg = intOr(c, 13, 0) }
                } else {
                    dmg = intOr(c, 13, 0)
                }

                if dmg <= 0, !life3170 {
                    if eq(c, 3, "3") {
                        line += "连击蓄势，暂无伤害。"
                    } else {
                        line += "特效命中，暂无伤害。"
                    }
                    line += appendLostWeapon(b: b, defName: defName, skillName: skillName)
                    sb += line + "<br />"
                    if side0 { hp1 = atkHp; hp2 = defHp } else { hp2 = atkHp; hp1 = defHp }
                    roundNo += 1
                    continue
                }

                line += "击中" + defName + "，"

                var remain = defHp - dmg
                if life3170 { remain = defHp - dmg + healDef }
                if remain <= 0 { remain = feign ? (feignBySuffix ? 60 : 1) : 0 }

                if life3170, healDef > 0 {
                    line += "<b><font color='red'>HP-\(dmg)</font></b>，"
                    line += defName
                    line += "<b><font color='blue'>再被对方击中时触发回血</font></b>，"
                    line += "<b><font color='green'>HP+\(healDef)</font></b>"
                    line += " (HP余\(remain))。"
                } else {
                    line += "<b><font color='red'>HP-\(dmg)。"
                    if feign, remain > 0 {
                        line += "气息紧闭，呈假死状（HP余\(remain)）。</font></b>"
                    } else if remain == 0 {
                        line += " (HP余 0 )。中招身亡，实在是不堪一击！</font></b>"
                    } else {
                        line += "(HP余\(remain))。</font></b>"
                    }
                }

                line += appendLostWeapon(b: b, defName: defName, skillName: skillName)
                defHp = max(0, remain)

                if c4 > 0 {
                    var cremain = atkHp - c4
                    if cremain < 0 { cremain = 0 }
                    line += defName
                    if eq(c, 7, "2686") {
                        line += "<b><font color='blue'>使出了大海无量，</font></b>"
                    } else {
                        line += "<b><font color='blue'>使出了反击，</font></b>"
                    }
                    line += atkName + "被击中"
                    line += "<b><font color='red'>HP-\(c4)"
                    line += " (HP余\(cremain))。</font></b>"
                    atkHp = cremain
                }

                if side0 { hp1 = atkHp; hp2 = defHp } else { hp2 = atkHp; hp1 = defHp }
                sb += line + "<br />"
                roundNo += 1
                if roundNo > 300 { break }
            }
        }
        return sb
    }

    static func formatAsync(
        _ raw: String,
        skillName: (String, String) async -> String
    ) async -> String {
        // 收集 (id,kind) 后批量解析，再同步 format
        var pairs: [(String, String)] = []
        _ = format(raw) { id, kind in
            if !id.isEmpty, !isSide(id) {
                pairs.append((id, kind))
            }
            return id
        }
        var cache: [String: String] = [:]
        for (id, kind) in pairs {
            let key = "\(kind):\(id)"
            if cache[key] != nil { continue }
            cache[key] = await skillName(id, kind)
        }
        return format(raw) { id, kind in
            cache["\(kind):\(id)"] ?? id
        }
    }

    // MARK: - helpers

    private static func describeAction(
        a: [String], b: [String], c: [String],
        skillName: (String, String) -> String
    ) -> String {
        if !isSide(nz(c, 1)) {
            return "技能" + skillName(nz(c, 1), "skill") + "，"
        }
        if !isSide(nz(a, 2)) {
            return "武器" + skillName(nz(a, 2), "weapon") + "，"
        }
        if b.count >= 2, !isSide(nz(b, 1)) {
            return "武器" + skillName(nz(b, 1), "weapon") + "，"
        }
        return "空手，"
    }

    private static func appendLostWeapon(
        b: [String], defName: String, skillName: (String, String) -> String
    ) -> String {
        if b.count == 1, !isSide(nz(b, 0)) {
            return defName
                + "<b><font color='blue'>丢失武器"
                + skillName(nz(b, 0), "weapon")
                + "。</font></b>"
        }
        return ""
    }

    private static func isDodge(_ c: [String]) -> Bool {
        nz(c, 12) == "2" && (isSide(nz(c, 13)) || nz(c, 13) == "0")
    }

    private static func extractActBody(_ seg: String) -> String {
        guard let actAt = seg.range(of: "Act:") else { return "" }
        var act = String(seg[actAt.upperBound...])
        if let winAt = act.range(of: "&Win") { act = String(act[..<winAt.lowerBound]) }
        if let buildAt = act.range(of: "&Build") { act = String(act[..<buildAt.lowerBound]) }
        return act
    }

    static func isSide(_ s: String) -> Bool {
        s.isEmpty || s == "0" || s == "1"
    }

    private static func eq(_ arr: [String], _ i: Int, _ v: String) -> Bool {
        nz(arr, i) == v
    }

    private static func nz(_ arr: [String], _ i: Int) -> String {
        guard i >= 0, i < arr.count else { return "" }
        return arr[i].trimmingCharacters(in: .whitespaces)
    }

    private static func intOr(_ arr: [String], _ i: Int, _ def: Int) -> Int {
        Int(nz(arr, i)) ?? def
    }

    private static func positiveInt(_ arr: [String], _ i: Int) -> Int? {
        let v = intOr(arr, i, 0)
        return v > 0 ? v : nil
    }

    private static func parseTrailDmg(_ pipe: String) -> Int? {
        if pipe.isEmpty { return nil }
        let parts = pipe.components(separatedBy: ",")
        guard let first = Int(parts[0].trimmingCharacters(in: .whitespaces)), first >= 10
        else { return nil }
        for p in parts.dropFirst() {
            let s = p.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if (Int(s) ?? -1) != 0 { return nil }
        }
        return first
    }

    private struct Player {
        let hp: Int
        let label: String
    }

    private static func parsePlayer(_ seg: String, key: String) -> Player? {
        var token: String?
        for part in seg.components(separatedBy: "&") {
            if part.hasPrefix(key) {
                token = part
                break
            }
        }
        guard let token else { return nil }
        let bits = token.components(separatedBy: ";")
        guard bits.count >= 4 else { return nil }
        let head = bits[1]
        let name: String
        let uin: String
        if let r = head.range(of: "(") {
            name = String(head[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            uin = String(head[r.lowerBound...])
        } else {
            name = head.trimmingCharacters(in: .whitespaces)
            uin = ""
        }
        let hp = Int(bits[3].trimmingCharacters(in: .whitespaces)) ?? 0
        return Player(hp: hp, label: name + uin)
    }
}
