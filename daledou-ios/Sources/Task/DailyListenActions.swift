import Foundation

/// 真源：`DailyExtraActions` — 矿洞 / 劫镖 / 粮草（一键代玩 + 后台监听共用）。
enum DailyListenActions {
    static let gapNs: UInt64 = 120_000_000

    static func hourGmt8() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal.component(.hour, from: Date())
    }

    /// 周一=1 … 周日=7
    static func weekdayMon1() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let w = cal.component(.weekday, from: Date())
        return w == 1 ? 7 : w - 1
    }

    // MARK: - 矿洞

    static func farmKuangDong(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "kuangdong"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }
        let mode = t.getString(fid, "mode", default: "zhijie").ifBlank("zhijie")
        let hpNeed = Int(t.getString(fid, "hp").trimmingCharacters(in: .whitespaces))
        let posWanted = t.getString(fid, "pos")
            .split(whereSeparator: { "、,， ".contains($0) })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        let (_, st) = await LedouCGI.getPetPk(cmd: "factionmine", cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = (CombatLog.jsonField(st, "msg") ?? "").ifBlank(CombatLog.fromBody(st))
        let rewardMsg = CombatLog.jsonField(st, "reward_message") ?? ""
        if !rewardMsg.isEmpty || msg.contains("可领") || st.contains("reward_message") {
            let (_, r) = await LedouCGI.getPhonePk(
                cmd: "factionmine", extra: ["op": "reward"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let rm = CombatLog.fromBody(r).ifBlank("已领奖")
            onLog("领奖：\(rm)")
            return rm
        }
        let fightTimes = CombatLog.jsonInt(st, "fight_times") ?? 0
        let hp = CombatLog.jsonInt(st, "current_hp") ?? 0
        let maxHp = CombatLog.jsonInt(st, "max_hp") ?? 0
        let pos = CombatLog.jsonInt(st, "current_dungeon_pos") ?? 0
        let dungeonMode = CombatLog.jsonInt(st, "current_dungeon_mode") ?? 0
        let floor = CombatLog.jsonInt(st, "current_dungeon_floor") ?? 0
        let npc = CombatLog.jsonField(st, "npc_name") ?? ""
        onLog("副本F\(floor)/M\(dungeonMode) 怪\(pos) \(npc) 血\(hp)/\(maxHp) 次数\(fightTimes)")

        if floor <= 0 && npc.isEmpty && hp <= 0 {
            let tip = msg.ifBlank("矿洞未开启")
            onLog(tip)
            return tip
        }
        if fightTimes >= 3 && b("wc_gb", true) {
            t.setEnabled(fid, false)
            let tip = "次数用尽，已关闭监听"
            onLog(tip)
            return tip
        }
        if b("kn") && dungeonMode != 3 {
            let tip = "只打困难：当前非困难模式"
            onLog(tip)
            return tip
        }

        let hour = hourGmt8()
        let forceBx = b("bx") && hour == 5
        let shouldFight: Bool = {
            if forceBx { return true }
            switch mode {
            case "zhijie": return true
            case "canxie": return hpNeed.map { hp > 0 && hp < $0 } ?? false
            case "bighp": return hpNeed.map { hp >= $0 } ?? false
            case "boss": return posWanted.isEmpty || posWanted.contains(pos)
            default: return false
            }
        }()
        if !shouldFight {
            let tip = "未命中打怪条件（\(mode)）"
            onLog(tip)
            return tip
        }
        if b("dt") {
            let (_, iron) = await LedouCGI.getPetPk(cmd: "blacksmith", extra: ["op": "5"], cookie: cookie)
            onLog("打铁：\(CombatLog.fromBody(iron))")
            try? await Task.sleep(nanoseconds: gapNs)
        }
        let (_, fight) = await LedouCGI.getPhonePk(
            cmd: "factionmine", extra: ["op": "fight"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let fm = CombatLog.fromBody(fight).ifBlank("已挑战")
        onLog(fm)
        if (fm.contains("次数") && (fm.contains("用尽") || fm.contains("不足"))) && b("wc_gb", true) {
            t.setEnabled(fid, false)
            onLog("次数用尽，已关闭监听")
        }
        return fm
    }

    // MARK: - 劫镖

    static func farmJieBiao(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "jiebiao"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }
        func s(_ key: String) -> String { t.getString(fid, key).trimmingCharacters(in: .whitespacesAndNewlines) }
        func n(_ key: String) -> Int { Int(s(key)) ?? 0 }

        var isSqy = b("isSQY", true)
        var isWlg = b("isWLG", false)
        let beiXuan = b("isBeiXuan", false)
        let closeWhenEmpty = b("is_WC_GB", false)
        let byCondition = b("is_TJ_ZD", true)
        let maxDj = n("maxDengJi")
        let maxZl = n("maxZhanLi")
        let maxSq = n("maxShenqi")
        let minJy = n("minJingYan")
        let zdQq = s("QQ")

        if beiXuan && hourGmt8() >= 5 {
            isWlg = true
            isSqy = false
        }
        if !isSqy && !isWlg {
            let tip = "温良恭和盛秋月最少选一个"
            onLog(tip)
            return tip
        }

        _ = await LedouCGI.getPetPk(cmd: "cargo", extra: ["op": "3"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let (_, body) = await LedouCGI.getPetPk(cmd: "cargo", cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)

        let left: Int = {
            if let m = body.range(of: #"剩余拦截次数[：:]\s*(\d+)"#, options: .regularExpression) {
                let s = String(body[m])
                if let r = s.range(of: #"\d+$"#, options: .regularExpression) {
                    return Int(s[r]) ?? -1
                }
            }
            return CombatLog.jsonInt(body, "left_times")
                ?? CombatLog.jsonInt(body, "remain_times")
                ?? -1
        }()
        if left == 0 {
            let tip = "剩余拦截次数：0"
            onLog(tip)
            if closeWhenEmpty {
                t.setEnabled(fid, false)
                onLog("次数用完，已关闭监听")
            }
            return tip
        }
        if left > 0 { onLog("剩余拦截次数：\(left)") }

        if !byCondition {
            let qqs = zdQq.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let qq = qqs.first else {
                let tip = "指定QQ为空"
                onLog(tip)
                return tip
            }
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "cargo", extra: ["op": "14", "passerby_uin": qq], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = "指定QQ\(qq)：\(CombatLog.fromBody(r).ifBlank("已请求"))"
            onLog(msg)
            return msg
        }

        struct Target {
            let uin: String
            let name: String
            let biaoshi: String
            let dengji: Int
            let exp: Int
            let zhanli: Int
            let shenqi: Int
        }

        var prefer: [String] = []
        if isSqy { prefer.append("盛秋月") }
        if isWlg { prefer.append("温良恭") }

        var targets: [Target] = []
        let chunks = CombatLog.jsonChunks(body, "passerbys").ifEmpty(CombatLog.jsonChunks(body, "passerlist"))
        for chunk in chunks {
            let uin = (CombatLog.jsonField(chunk, "passerby_uin") ?? "")
                .ifBlank(CombatLog.jsonField(chunk, "uin") ?? "")
            if uin.isEmpty { continue }
            let biaoshi = (CombatLog.jsonField(chunk, "escort_npc_name") ?? "")
                .ifBlank(CombatLog.jsonField(chunk, "biaoshi") ?? "")
            let name = (CombatLog.jsonField(chunk, "passerby_name") ?? "")
                .ifBlank(CombatLog.jsonField(chunk, "name") ?? "")
            let dengji = CombatLog.jsonInt(chunk, "passerby_lvl")
                ?? CombatLog.jsonInt(chunk, "level")
                ?? 0
            let exp = CombatLog.jsonInt(chunk, "exp_award")
                ?? CombatLog.jsonInt(chunk, "exp")
                ?? 0
            let zhanli = CombatLog.jsonInt(chunk, "zhanli")
                ?? CombatLog.jsonInt(chunk, "fight_capacity")
                ?? 0
            let shenqi = CombatLog.jsonInt(chunk, "shenqi")
                ?? CombatLog.jsonInt(chunk, "god_weapon")
                ?? 0
            targets.append(Target(uin: uin, name: name, biaoshi: biaoshi, dengji: dengji, exp: exp, zhanli: zhanli, shenqi: shenqi))
        }
        if targets.isEmpty {
            let h = body.replacingOccurrences(of: "&amp;", with: "&")
            let re = try? NSRegularExpression(pattern: "passerby_uin=(\\d+)")
            let ns = h as NSString
            re?.enumerateMatches(in: h, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 2 else { return }
                let uin = ns.substring(with: m.range(at: 1))
                let start = max(0, m.range.location - 120)
                let end = min(ns.length, m.range.location + m.range.length + 80)
                let ctx = ns.substring(with: NSRange(location: start, length: end - start))
                let biaoshi = prefer.first(where: { ctx.contains($0) }) ?? ""
                if biaoshi.isEmpty && !prefer.isEmpty { return }
                let dj = Int(ctx.range(of: #"等级[^\d]*(\d+)"#, options: .regularExpression).map { String(ctx[$0]).filter(\.isNumber) } ?? "") ?? 0
                let exp = Int(ctx.range(of: #"经验[^\d]*(\d+)"#, options: .regularExpression).map { String(ctx[$0]).filter(\.isNumber) } ?? "") ?? 0
                targets.append(Target(uin: uin, name: "", biaoshi: biaoshi, dengji: dj, exp: exp, zhanli: 0, shenqi: 0))
            }
        }

        func matchBiaoshi(_ t: Target) -> Bool {
            if prefer.isEmpty { return true }
            if !t.biaoshi.isEmpty { return prefer.contains(where: { t.biaoshi.contains($0) }) }
            return true
        }
        func matchCond(_ t: Target) -> Bool {
            guard matchBiaoshi(t) else { return false }
            if maxDj > 0 && t.dengji > 0 && t.dengji > maxDj { return false }
            if minJy > 0 && t.exp > 0 && t.exp < minJy { return false }
            if maxZl > 0 && t.zhanli > 0 && t.zhanli > maxZl { return false }
            if maxSq > 0 && t.shenqi > 0 && t.shenqi > maxSq { return false }
            if maxZl > 0 && t.zhanli <= 0 { return false }
            return true
        }

        let ordered = targets.filter(matchCond).sorted { a, b in
            let ia = prefer.firstIndex(where: { a.biaoshi.contains($0) }) ?? 99
            let ib = prefer.firstIndex(where: { b.biaoshi.contains($0) }) ?? 99
            return ia < ib
        }
        let hit = ordered.first
            ?? targets.first(where: { matchBiaoshi($0) && (maxDj <= 0 || $0.dengji <= 0 || $0.dengji <= maxDj) })

        guard let hit else {
            let tip = "没有符合条件的镖车（列表\(targets.count)）"
            onLog(tip)
            return tip
        }

        let (_, r) = await LedouCGI.getPetPk(
            cmd: "cargo", extra: ["op": "14", "passerby_uin": hit.uin], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let detail = "\(hit.biaoshi.ifBlank("镖车")) \(hit.name)@\(hit.uin) Lv\(hit.dengji) 经验\(hit.exp)"
        let msg = "劫\(detail)：\(CombatLog.fromBody(r).ifBlank("已请求"))"
        onLog(msg)
        return msg
    }

    // MARK: - 粮草（攻击）

    static func farmLiangCao(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "liangcao"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }
        if !b("attack", true) {
            let tip = "未勾选自动攻击"
            onLog(tip)
            return tip
        }
        let wd = weekdayMon1()
        let hour = hourGmt8()
        let open = (wd == 2 && hour >= 6) || (wd == 6 && hour >= 6) || (wd == 3 && hour < 6)
        if !open {
            let tip = "不在粮草开放时段"
            onLog(tip)
            return tip
        }
        let minDj = Int(t.getString(fid, "min_dengji").trimmingCharacters(in: .whitespaces))
        let maxDj = Int(t.getString(fid, "max_dengji").trimmingCharacters(in: .whitespaces))
        let minZl = Int(t.getString(fid, "min_zhanli").trimmingCharacters(in: .whitespaces))
        let maxZl = Int(t.getString(fid, "max_zhanli").trimmingCharacters(in: .whitespaces))
        let zbNot = b("not_zb")
        var zbList = Set(
            t.getString(fid, "zb_list")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        let (_, page) = await LedouCGI.getPhonePk(
            cmd: "forage_war", extra: ["subtype": "3"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let blood = CombatLog.jsonInt(page, "blood") ?? CombatLog.jsonInt(page, "resurgence_times")
        if b("wc_gb"), let blood, blood <= 0, page.contains("resurgence_times") {
            let left = CombatLog.jsonInt(page, "resurgence_times") ?? 0
            if left <= 0 && (CombatLog.jsonInt(page, "blood") ?? 0) <= 0 {
                t.setEnabled(fid, false)
                let tip = "次数用尽，已关闭"
                onLog(tip)
                return tip
            }
        }

        let granaries = CombatLog.jsonChunks(page, "granary_list").ifEmpty(CombatLog.jsonChunks(page, "list"))
        var attacked = false
        for g in granaries {
            let graId = (CombatLog.jsonField(g, "gra_id") ?? "").ifBlank(CombatLog.jsonField(g, "id") ?? "")
            if graId.isEmpty { continue }
            let total = Int(CombatLog.jsonField(g, "total_num") ?? "1") ?? 1
            if total <= 0 { continue }
            let defs = CombatLog.jsonChunks(g, "defend_list")
            guard let def = defs.first else { continue }
            let name = CombatLog.jsonField(def, "name") ?? ""
            let level = CombatLog.jsonInt(def, "level") ?? 0
            let power = CombatLog.jsonInt(def, "power")
                ?? CombatLog.jsonInt(def, "zhanli")
                ?? 0
            if zbNot && !name.isEmpty && zbList.contains(name) { continue }
            if let minDj, level < minDj { continue }
            if let maxDj, level > maxDj { continue }
            if let minZl, power < minZl { continue }
            if let maxZl, power > maxZl { continue }
            onLog("攻击 \(name) Lv\(level) 战力\(power) gra=\(graId)")
            let (_, atk) = await LedouCGI.getPhonePk(
                cmd: "forage_war", extra: ["subtype": "4", "gra_id": graId], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let am = CombatLog.fromBody(atk).ifBlank("已攻击")
            onLog(am)
            if am.contains("Win:0") || am.contains("战败") || atk.contains("\"Win\":0") {
                if !name.isEmpty {
                    zbList.insert(name)
                    t.setString(fid, "zb_list", zbList.sorted().joined(separator: ","))
                }
            }
            attacked = true
            break
        }
        if !attacked {
            if b("wc_gb") {
                t.setEnabled(fid, false)
                let tip = "无合适目标，已关闭"
                onLog(tip)
                return tip
            }
            let tip = "无合适目标"
            onLog(tip)
            return tip
        }
        return "粮草已攻击"
    }

    /// 一键活跃粮草：查看 + 领参与/胜负奖（对齐 HuoYueRunner.cb_dw_lc）。
    static func claimLiangCao(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let (_, view) = await LedouCGI.getPhonePk(cmd: "forage_war", cookie: cookie)
        let viewMsg = CombatLog.fromBody(view)
        if !viewMsg.isEmpty { onLog(viewMsg) }
        try? await Task.sleep(nanoseconds: gapNs)
        let (_, r) = await LedouCGI.getPetPk(
            cmd: "forage_war", extra: ["subtype": "5"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let (_, win) = await LedouCGI.getPetPk(
            cmd: "forage_war", extra: ["subtype": "6"], cookie: cookie
        )
        let a = CombatLog.fromBody(r).ifBlank("参与奖")
        let b = CombatLog.fromBody(win).ifBlank("胜负奖")
        let msg = "\(a)；\(b)"
        onLog(msg)
        return msg
    }

    // MARK: - 问鼎监听

    static func farmWenDingListen(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "wending"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }

        let wd = weekdayMon1()
        let hour = hourGmt8()
        let blocked = wd == 1 || (wd == 6 && hour >= 6)

        if b("draw") {
            let (_, d1) = await LedouCGI.getPetPk(
                cmd: "tbattle", extra: ["op": "drawreward"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("奖励：\(CombatLog.fromBody(d1).ifBlank("drawreward"))")
            let (_, d2) = await LedouCGI.getPetPk(
                cmd: "tbattle", extra: ["op": "drawreleasereward"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("枯竭：\(CombatLog.fromBody(d2).ifBlank("drawreleasereward"))")
        }
        if !b("occupy", true) {
            let tip = "未勾选自动占领"
            onLog(tip)
            return tip
        }
        if blocked {
            let tip = "当前时段不做问鼎占领"
            onLog(tip)
            return tip
        }

        var regions: [Int] = []
        if b("qy_dh") { regions.append(1) }
        if b("qy_nh") { regions.append(2) }
        if b("qy_xz") { regions.append(3) }
        if b("qy_bh") { regions.append(4) }
        if regions.isEmpty && b("region_auto", true) { regions = [1, 2, 3, 4] }
        if regions.isEmpty { regions = [1] }

        let s2 = b("s2j")
        let s3 = b("s3j", true)
        let minExp = Int(t.getString(fid, "zi_yuan", default: "200").trimmingCharacters(in: .whitespaces)) ?? 200
        let maxZl = Int(t.getString(fid, "zhanli_max", default: "500").trimmingCharacters(in: .whitespaces)) ?? 500
        let zbNot = b("zb_not")
        var failSet = Set(
            t.getString(fid, "zb_list")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let names = ["", "东海", "南荒", "西泽", "北寒"]

        for region in regions {
            let (_, page) = await LedouCGI.getPetPk(
                cmd: "tbattle",
                extra: ["op": "showregion", "region": "\(region)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if page.contains("系统繁忙") { continue }
            let left = CombatLog.jsonInt(page, "left_fight_times")
            if b("no_cd"), let left, left <= 0 {
                onLog("\(names[region])：无挑战次数")
                continue
            }
            // self_territory 对象切片
            if let m = page.range(of: #""self_territory"\s*:\s*(\{[^{}]*\})"#, options: .regularExpression) {
                let chunk = String(page[m])
                let selfId = (CombatLog.jsonField(chunk, "canoncial_id") ?? "")
                    .ifBlank(CombatLog.jsonField(chunk, "id") ?? "")
                if !selfId.isEmpty && selfId != "0" {
                    onLog("\(names[region])：已有领地")
                    continue
                }
            }
            var arrays: [String] = []
            if s2 { arrays += CombatLog.jsonChunks(page, "level_2_territories") }
            if s3 { arrays += CombatLog.jsonChunks(page, "level_3_territories") }
            if arrays.isEmpty {
                arrays += CombatLog.jsonChunks(page, "level_3_territories")
                arrays += CombatLog.jsonChunks(page, "level_2_territories")
            }
            for chunk in arrays {
                let id = (CombatLog.jsonField(chunk, "canoncial_id") ?? "")
                    .ifBlank(CombatLog.jsonField(chunk, "id") ?? "")
                if id.isEmpty || id == "0" { continue }
                if zbNot && failSet.contains(id) { continue }
                let owner = CombatLog.jsonField(chunk, "owner_name") ?? ""
                let faction = CombatLog.jsonField(chunk, "owner_faction_name") ?? ""
                let combat = CombatLog.jsonInt(chunk, "owner_combat_points") ?? 999_999
                let exploits = CombatLog.jsonInt(chunk, "exploits_left") ?? 0
                let empty = (owner == "暂无" || owner.isEmpty) && (faction == "暂无" || faction.isEmpty)
                if exploits < minExp { continue }
                if !empty && combat > maxZl { continue }
                onLog("\(names[region])占领 \(id) 战力\(combat) 资源\(exploits)")
                let (_, occ) = await LedouCGI.getPetPk(
                    cmd: "tbattle", extra: ["op": "occupy", "id": id], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let om = CombatLog.fromBody(occ).ifBlank("已请求")
                onLog(om)
                if om.contains("战败") || om.contains("失败") || (CombatLog.jsonInt(occ, "result") ?? 0) != 0 {
                    failSet.insert(id)
                    t.setString(fid, "zb_list", failSet.sorted().joined(separator: ","))
                }
                return om
            }
            if b("tz_notify") {
                onLog("\(names[region])：未找到合适空地")
            }
        }
        let tip = "问鼎本轮无目标"
        onLog(tip)
        return tip
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private extension Array {
    func ifEmpty(_ other: [Element]) -> [Element] {
        isEmpty ? other : self
    }
}
