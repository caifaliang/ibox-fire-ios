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

    // MARK: - 问鼎复仇

    static func farmFuChouWenDing(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "fuchou_wending"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }

        var factionName = t.getString(fid, "faction_name").trimmingCharacters(in: .whitespacesAndNewlines)
        let factionId = t.getString(fid, "faction_id").trimmingCharacters(in: .whitespacesAndNewlines)
        if factionName.isEmpty && !factionId.isEmpty {
            let (_, vf) = await LedouCGI.getPetPk(
                cmd: "viewfaction", extra: ["id": factionId], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            factionName = (CombatLog.jsonField(vf, "name") ?? "").ifBlank({
                if let m = vf.range(of: #"帮派[：:]([^<\n]+)"#, options: .regularExpression) {
                    return String(vf[m]).replacingOccurrences(of: #"帮派[：:]"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                }
                return ""
            }())
            if !factionName.isEmpty {
                t.setString(fid, "faction_name", factionName)
            }
        }
        if factionName.isEmpty {
            let tip = "请填写目标帮派名或帮派 ID"
            onLog(tip)
            return tip
        }

        var regions: [Int] = []
        if b("qy_dh", true) { regions.append(1) }
        if b("qy_nh", true) { regions.append(2) }
        if b("qy_xz", true) { regions.append(3) }
        if b("qy_bh", true) { regions.append(4) }
        if regions.isEmpty { regions = [1, 2, 3, 4] }

        struct Hit {
            let id: String
            let name: String
            let combat: Int
            let region: Int
        }
        var hits: [Hit] = []
        for region in regions {
            for tli in ["0", "1", "2"] {
                let (_, page) = await LedouCGI.getPetPk(
                    cmd: "tbattle",
                    extra: [
                        "level": "3",
                        "region": "\(region)",
                        "occupied": "1",
                        "time_left_index": tli,
                        "op": "fuzzysearch",
                    ],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: 80_000_000)
                var chunks = CombatLog.jsonChunks(page, "territories")
                    .ifEmpty(CombatLog.jsonChunks(page, "level_3_territories"))
                if chunks.isEmpty {
                    let re = try? NSRegularExpression(pattern: #"\{[^{}]*"canoncial_id"[^{}]*\}"#)
                    let ns = page as NSString
                    re?.enumerateMatches(in: page, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                        guard let m else { return }
                        chunks.append(ns.substring(with: m.range))
                    }
                }
                for c in chunks {
                    let fac = CombatLog.jsonField(c, "owner_faction_name") ?? ""
                    if !fac.contains(factionName) && fac != factionName { continue }
                    let id = (CombatLog.jsonField(c, "canoncial_id") ?? "")
                        .ifBlank(CombatLog.jsonField(c, "id") ?? "")
                    if id.isEmpty { continue }
                    if hits.contains(where: { $0.id == id }) { continue }
                    hits.append(Hit(
                        id: id,
                        name: (CombatLog.jsonField(c, "name") ?? "").ifBlank(id),
                        combat: CombatLog.jsonInt(c, "owner_combat_points") ?? 999_999,
                        region: region
                    ))
                }
            }
        }
        if hits.isEmpty {
            let tip = "未找到帮派「\(factionName)」的地盘"
            onLog(tip)
            return tip
        }
        let sorted = hits.sorted { $0.combat < $1.combat }
        let preview = sorted.prefix(5).map { "\($0.name)(\($0.combat))" }.joined(separator: ",")
        onLog("命中 \(sorted.count)：\(preview)")
        if !b("auto_occupy") {
            return "查询到\(sorted.count)块"
        }
        let target = sorted[0]
        onLog("占领 \(target.name) id=\(target.id)")
        let (_, occ) = await LedouCGI.getPetPk(
            cmd: "tbattle", extra: ["op": "occupy", "id": target.id], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let om = CombatLog.fromBody(occ).ifBlank("已请求")
        onLog(om)
        return om
    }

    // MARK: - 开矿洞

    /// 按 OpenKdScreen 日程决定 floor/mode，再 `factionmine op=start`。
    static func farmOpenKd(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "open_kd"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }

        let any = b("is7") || b("is1") || b("is_new_1") || b("is2") || b("is3") || b("isOther", true) || b("isMax")
        if !any {
            let tip = "没有勾选功能，请检查设置"
            onLog(tip)
            return tip
        }

        let wd = weekdayMon1()
        let hour = hourGmt8()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let minute = cal.component(.minute, from: Date())
        let nowMin = hour * 60 + minute

        let openH = Int(t.getString(fid, "hours", default: "22")) ?? 22
        let openM = Int(t.getString(fid, "minute", default: "0")) ?? 0
        let endH = Int(t.getString(fid, "hour_end", default: "6")) ?? 6
        let endM = Int(t.getString(fid, "minutes_end", default: "0")) ?? 0
        let openAt = openH * 60 + openM
        let endAt = endH * 60 + endM

        // 困难五层：周日/周一时段、周一全天、周二/周三全天
        var wantHard = false
        if b("is1") && wd == 1 { wantHard = true }
        if b("is2") && wd == 2 { wantHard = true }
        if b("is3") && wd == 3 { wantHard = true }
        if b("is7") {
            // 开启时间后开困难；hour<6 视为周一
            let inWindow: Bool = {
                if wd == 7 { return nowMin >= openAt }
                if wd == 1 {
                    if b("is_new_1") { return nowMin < endAt }
                    return nowMin >= openAt || hour < 6
                }
                return false
            }()
            if inWindow { wantHard = true }
        }
        if b("is_new_1") && wd == 1 && nowMin >= endAt {
            wantHard = false
        }

        let floor: String
        let mode: String
        let label: String
        if b("isMax") && !wantHard {
            floor = "99"
            mode = "3"
            label = "最高层"
        } else if wantHard {
            floor = "5"
            mode = "3"
            label = "五层困难"
        } else if b("isOther", true) {
            floor = "1"
            mode = "1"
            label = "一层简单"
        } else {
            let tip = "当前时段无匹配开矿规则"
            onLog(tip)
            return tip
        }

        let (_, status) = await LedouCGI.getPetPk(cmd: "factionmine", cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let stMsg = CombatLog.fromBody(status)
        if !stMsg.isEmpty { onLog("状态：\(stMsg)") }

        let floorNow = CombatLog.jsonInt(status, "current_dungeon_floor") ?? 0
        let modeNow = CombatLog.jsonInt(status, "current_dungeon_mode") ?? 0
        let hp = CombatLog.jsonInt(status, "current_hp") ?? 0
        let npc = CombatLog.jsonField(status, "npc_name") ?? ""
        let alreadyOpen = floorNow > 0 || !npc.isEmpty || hp > 0
        if alreadyOpen {
            let tip = "矿洞已开 F\(floorNow)/M\(modeNow)，跳过 start"
            onLog(tip)
            return tip
        }

        let (_, start) = await LedouCGI.getPhonePk(
            cmd: "factionmine",
            extra: ["op": "start", "floor": floor, "mode": mode],
            cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let sm = CombatLog.fromBody(start).ifBlank("已请求开矿")
        let msg = "开启\(label) F\(floor)/M\(mode)：\(sm)"
        onLog(msg)
        return msg
    }

    // MARK: - 换守护神

    static func farmChangeGuard(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "change_guard"
        let qinglong = t.getBool(fid, "qinglong", default: true)
        let allBaihu = t.getBool(fid, "all_baihu", default: false)
        let h1 = Int(t.getString(fid, "h1", default: "0")) ?? 0
        let m1 = Int(t.getString(fid, "m1", default: "0")) ?? 0
        let h2 = Int(t.getString(fid, "h2", default: "12")) ?? 12
        let m2 = Int(t.getString(fid, "m2", default: "0")) ?? 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nowMin = hour * 60 + minute
        let t1 = h1 * 60 + m1
        let t2 = h2 * 60 + m2
        let inQingLongWindow: Bool = {
            if t1 == t2 { return true }
            if t1 < t2 { return nowMin >= t1 && nowMin < t2 }
            // 跨午夜：t1→24:00 或 0→t2
            return nowMin >= t1 || nowMin < t2
        }()

        let preferQingLong: Bool = {
            if inQingLongWindow { return qinglong }
            if allBaihu { return false }
            return qinglong
        }()

        let (_, check) = await LedouCGI.getPhonePk(
            cmd: "factionop", extra: ["subtype": "12"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let checkMsg = CombatLog.fromBody(check)
        if !checkMsg.isEmpty { onLog("查询：\(checkMsg)") }

        let protectId = preferQingLong ? "101" : "103"
        let name = preferQingLong ? "青龙" : "白虎"
        let (_, set) = await LedouCGI.getPhonePk(
            cmd: "setprotect", extra: ["id": protectId], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let sm = CombatLog.fromBody(set).ifBlank("已请求")
        let msg = "换\(name)：\(sm)"
        onLog(msg)
        return msg
    }

    // MARK: - 任务派遣

    static func farmPaiQian(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "paiqian"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }
        let wantS = b("accept_s", true)
        let wantA = b("accept_a", true)
        let wantB = b("accept_b")
        let preferBx = b("bx")
        let canRefresh = b("refresh")
        let doClaim = b("claim", true)

        func typeOk(_ type: Int) -> Bool {
            switch type {
            case 1: return wantS
            case 2: return wantA
            case 3: return wantB
            default: return wantS || wantA || wantB
            }
        }

        var page = await LedouCGI.getPhonePk(
            cmd: "assignment", extra: ["op": "0"], cookie: cookie
        ).1
        try? await Task.sleep(nanoseconds: gapNs)
        var claimed = 0
        var accepted = 0

        if doClaim {
            let acceptedList = CombatLog.jsonChunks(page, "acceptedMissionInfo")
                .ifEmpty(CombatLog.jsonChunks(page, "accepted"))
            for m in acceptedList {
                let remain = CombatLog.jsonInt(m, "remainTime") ?? -1
                let status = CombatLog.jsonInt(m, "status") ?? 0
                let mid = (CombatLog.jsonField(m, "mission_id") ?? "")
                    .ifBlank(CombatLog.jsonField(m, "id") ?? "")
                if mid.isEmpty { continue }
                if remain == 0 || status == 1 || m.contains("可领取") {
                    let (_, c) = await LedouCGI.getPhonePk(
                        cmd: "assignment", extra: ["op": "2", "mission_id": mid], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog("领奖：\(mid) \(CombatLog.fromBody(c))")
                    _ = await LedouCGI.getPhonePk(
                        cmd: "assignment", extra: ["op": "8", "mission_id": mid], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    claimed += 1
                }
            }
            if claimed > 0 {
                page = await LedouCGI.getPhonePk(
                    cmd: "assignment", extra: ["op": "0"], cookie: cookie
                ).1
                try? await Task.sleep(nanoseconds: gapNs)
            }
        }

        let acceptedCount = CombatLog.jsonChunks(page, "acceptedMissionInfo").count
        if acceptedCount >= 3 {
            let tip = "已满 3 个派遣"
            onLog(tip)
            return tip
        }

        func tryAcceptOnce(_ from: [String]) async -> Bool {
            let ordered = preferBx
                ? from.sorted { $0.contains("宝匣") && !$1.contains("宝匣") }
                : from
            for m in ordered {
                let mid = (CombatLog.jsonField(m, "mission_id") ?? "")
                    .ifBlank(CombatLog.jsonField(m, "id") ?? "")
                if mid.isEmpty { continue }
                let type = CombatLog.jsonInt(m, "type") ?? 0
                let acceptedFlag = CombatLog.jsonInt(m, "accepted") ?? 0
                if acceptedFlag != 0 { continue }
                if !typeOk(type) { continue }
                let (_, a) = await LedouCGI.getPhonePk(
                    cmd: "assignment", extra: ["op": "4", "mission_id": mid], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("接取\(mid)：\(CombatLog.fromBody(a))")
                let (_, d) = await LedouCGI.getPhonePk(
                    cmd: "assignment", extra: ["op": "6", "mission_id": mid], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let dm = CombatLog.fromBody(d)
                onLog("派遣：\(dm)")
                if dm.contains("成功") || CombatLog.jsonInt(d, "result") == 0 {
                    _ = await LedouCGI.getPhonePk(
                        cmd: "assignment", extra: ["op": "7", "mission_id": mid], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                }
                return true
            }
            return false
        }

        let standy = CombatLog.jsonChunks(page, "standyMissionInfo")
            .ifEmpty(CombatLog.jsonChunks(page, "standby"))
        if await tryAcceptOnce(standy) {
            accepted += 1
        } else if canRefresh {
            let dayFmt = DateFormatter()
            dayFmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
            dayFmt.dateFormat = "yyyyMMdd"
            let day = dayFmt.string(from: Date())
            let usedDay = t.getString(fid, "refresh_day")
            var used = usedDay == day ? (Int(t.getString(fid, "refresh_count")) ?? 0) : 0
            if used < 3 {
                _ = await LedouCGI.getPhonePk(
                    cmd: "assignment", extra: ["op": "1"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                used += 1
                t.setString(fid, "refresh_day", day)
                t.setString(fid, "refresh_count", "\(used)")
                onLog("刷新任务（\(used)/3）")
                page = await LedouCGI.getPhonePk(
                    cmd: "assignment", extra: ["op": "0"], cookie: cookie
                ).1
                try? await Task.sleep(nanoseconds: gapNs)
                if await tryAcceptOnce(
                    CombatLog.jsonChunks(page, "standyMissionInfo")
                        .ifEmpty(CombatLog.jsonChunks(page, "standby"))
                ) {
                    accepted += 1
                }
            }
        }
        let tip = "派遣 领\(claimed) 接\(accepted)"
        onLog(tip)
        return tip
    }

    // MARK: - 门派守夜

    static func farmMenPaiShouYe(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "menpai_shouye"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }

        if b("auto_signup") {
            let (_, su) = await LedouCGI.getPetPk(
                cmd: "secttournament", extra: ["op": "signup"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("报名：\(CombatLog.fromBody(su).ifBlank("已请求"))")
            let (_, inv) = await LedouCGI.getPetPk(
                cmd: "secttournament", extra: ["op": "invite"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("邀请：\(CombatLog.fromBody(inv).ifBlank("已请求"))")
        }

        if weekdayMon1() != 1 {
            let tip = "非周一，跳过守夜挑战"
            onLog(tip)
            return tip
        }

        let hourNeed = Int(t.getString(fid, "hours", default: "0").trimmingCharacters(in: .whitespaces)) ?? 0
        let minNeed = Int(t.getString(fid, "minute", default: "5").trimmingCharacters(in: .whitespaces)) ?? 5
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let now = Date()
        let nowM = (cal.component(.hour, from: now) * 60) + cal.component(.minute, from: now)
        if nowM < hourNeed * 60 + minNeed {
            let tip = "未到守夜时间 \(hourNeed):\(String(format: "%02d", minNeed))"
            onLog(tip)
            return tip
        }
        if !b("fight", true) {
            let tip = "未勾选自动挑战"
            onLog(tip)
            return tip
        }

        let (_, rank) = await LedouCGI.getPetPk(
            cmd: "secttournament", extra: ["op": "showcurrentseasonrank"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let mingci = Int(t.getString(fid, "mingci", default: "50").trimmingCharacters(in: .whitespaces)) ?? 50
        let isJf = b("is_jf")
        let points = CombatLog.jsonInt(rank, "self_ranking_points")
        let pos = CombatLog.jsonInt(rank, "self_group_rank_pos") ?? 0
        let needFight = isJf ? ((points ?? 0) < mingci) : (pos == 0 || pos > mingci)
        if !needFight {
            let tip = "已达目标（分\(points.map(String.init) ?? "-") 名\(pos) / 阈值\(mingci)）"
            onLog(tip)
            return tip
        }

        let (_, fight) = await LedouCGI.getPhonePk(
            cmd: "secttournament", extra: ["op": "fight"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let fm = CombatLog.fromBody(fight).ifBlank("已挑战")
        onLog(fm)
        if fm.contains("门派战书不足") && b("hzs") {
            let (_, ex) = await LedouCGI.getPhonePk(
                cmd: "exchange",
                extra: ["subtype": "2", "type": "1249", "times": "1", "costtype": "11"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("换战书：\(CombatLog.fromBody(ex))")
            let (_, again) = await LedouCGI.getPhonePk(
                cmd: "secttournament", extra: ["op": "fight"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let am = CombatLog.fromBody(again).ifBlank("再挑战")
            onLog(am)
            return am
        }
        return fm
    }

    // MARK: - 喝酒（一轮：对齐 HejiuWorker tick / 悬浮窗点一下）

    static func farmHeJiu(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "hejiu"
        _ = await LedouCGI.getPhonePk(
            cmd: "warriorinn", extra: ["op": "viewknights"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let (_, poll) = await LedouCGI.getPhonePk(
            cmd: "newAct", extra: ["subtype": "154"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let body = poll
        if body.contains("登陆校验") || body.contains("请先登录") {
            let tip = "会话失效，已停喝酒"
            t.setEnabled(fid, false)
            onLog(tip)
            return tip
        }

        var dataStr = t.getString(fid, "dataStr")
        var dataTime = t.getString(fid, "dataTime")
        var huang = t.getString(fid, "huangCount")
        for raw in body.components(separatedBy: CharacterSet(charactersIn: "\n"))
            .flatMap({ $0.components(separatedBy: "<br />") })
            .flatMap({ $0.components(separatedBy: "<br/>") })
            .flatMap({ $0.components(separatedBy: "<br>") })
        {
            let plain = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if plain.contains("下次刷新时间：") { dataTime = plain }
            else if plain.contains("本次可能获得的奖励：") { dataStr = plain }
            else if plain.contains("现有黄酒数量：") { huang = plain }
        }
        t.setString(fid, "dataStr", dataStr)
        t.setString(fid, "dataTime", dataTime)
        t.setString(fid, "huangCount", huang)
        if body.contains("次数已满") || body.contains("已达上限") || body.contains("已喝满") {
            t.setBool(fid, "isHeJiu_20_MAX", true)
        }

        let hour = hourGmt8()
        let heman = t.getBool(fid, "isHeJiu_20")
        var hemanMax = t.getBool(fid, "isHeJiu_20_MAX")
        let otherStr = t.getString(fid, "otherStr").trimmingCharacters(in: .whitespacesAndNewlines)
        var drinkMsg = "未献酒"

        if heman && !hemanMax && hour == 5 {
            let (_, drink) = await LedouCGI.getPhonePk(
                cmd: "newAct", extra: ["subtype": "155"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            drinkMsg = "凌晨拉满:\(CombatLog.fromBody(drink).ifBlank(String(drink.prefix(50))))"
        } else {
            if hour >= 6 {
                hemanMax = false
                t.setBool(fid, "isHeJiu_20_MAX", false)
            }
            if !otherStr.isEmpty && !dataStr.isEmpty {
                let tokens = otherStr
                    .components(separatedBy: CharacterSet(charactersIn: "、,，"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if let hit = tokens.first(where: { dataStr.contains($0) }) {
                    let (_, drink) = await LedouCGI.getPhonePk(
                        cmd: "newAct", extra: ["subtype": "155"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    drinkMsg = "命中[\(hit)]:\(CombatLog.fromBody(drink).ifBlank(String(drink.prefix(50))))"
                } else {
                    drinkMsg = "奖励未命中指令"
                }
            } else if otherStr.isEmpty {
                // 悬浮窗一键：无指令时直接自己献酒一次
                let (_, drink) = await LedouCGI.getPhonePk(
                    cmd: "newAct", extra: ["subtype": "155"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                drinkMsg = "自己献酒:\(CombatLog.fromBody(drink).ifBlank(String(drink.prefix(50))))"
            }
        }
        let tip = "奖励:\(String((dataStr.isEmpty ? body : dataStr).prefix(40))) | \(drinkMsg)"
        onLog(tip)
        return tip
    }

    // MARK: - 侠客行

    static func farmXkx(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "xkx"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }
        let yx1 = b("yx_1")
        let yx2 = b("yx_2")
        let refType: Int = {
            if b("ref_pay") { return 3 }
            if b("ref_free", true) { return 1 }
            if b("ref_sign") { return 2 }
            return 0
        }()

        let (_, page) = await LedouCGI.getPhonePk(
            cmd: "knightisland", extra: ["op": "viewmissionindex"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let missions = CombatLog.jsonChunks(page, "mission")
            .ifEmpty(CombatLog.jsonChunks(page, "list"))
        var did = 0
        let posList: [(Int, String)] = {
            if !missions.isEmpty {
                return missions.enumerated().map { i, m in
                    let pos = CombatLog.jsonInt(m, "pos") ?? (i + 1)
                    return (pos, m)
                }
            }
            return [(1, ""), (2, ""), (3, "")]
        }()

        for (pos, raw) in posList.prefix(3) {
            if Task.isCancelled { break }
            let chunk = raw.isEmpty ? page : raw
            let status = CombatLog.jsonInt(chunk, "status")
                ?? (chunk.contains("已完成") || chunk.contains("领取") ? 2
                    : chunk.contains("进行") ? 1 : 0)
            let reward: String = {
                if let r = CombatLog.jsonField(chunk, "reward"), !r.isEmpty { return r }
                if let range = chunk.range(of: #"奖励[^\n<]{0,40}"#, options: .regularExpression) {
                    return String(chunk[range])
                }
                return ""
            }()

            switch status {
            case 2:
                if b("reward", true) {
                    let (_, r) = await LedouCGI.getPhonePk(
                        cmd: "knightisland",
                        extra: ["pos": "\(pos)", "op": "getmissionreward"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog("P\(pos) 领奖：\(CombatLog.fromBody(r))")
                    did += 1
                }
            case 0:
                let prefer = (yx1 && reward.contains("太玄经")) || (yx2 && reward.contains("鉴宝真炎"))
                let low = reward.contains("*1") || reward.contains("×1") || reward.contains("x1")
                let shouldRefresh: Bool = {
                    switch refType {
                    case 1: return low && !prefer
                    case 3: return !prefer
                    default: return false
                    }
                }()
                if shouldRefresh {
                    let (_, rf) = await LedouCGI.getPhonePk(
                        cmd: "knightisland",
                        extra: ["pos": "\(pos)", "op": "refreshmission"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog("P\(pos) 刷新：\(CombatLog.fromBody(rf))")
                    did += 1
                    continue
                }
                if b("auto_assign", true) || refType == 2 {
                    let (_, a) = await LedouCGI.getPhonePk(
                        cmd: "knightisland",
                        extra: ["pos": "\(pos)", "op": "autoassign"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog("P\(pos) 派遣：\(CombatLog.fromBody(a))")
                    did += 1
                }
                if b("begin", true) {
                    let (_, bg) = await LedouCGI.getPhonePk(
                        cmd: "knightisland",
                        extra: ["pos": "\(pos)", "op": "begin"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog("P\(pos) 开始：\(CombatLog.fromBody(bg))")
                    did += 1
                }
            default:
                onLog("P\(pos) 进行中")
            }
        }
        let tip = "侠客行处理\(did)"
        onLog(tip)
        return tip
    }

    // MARK: - 好友管理（同意申请；加好友需查区名册，iOS 暂只同意）

    static func farmFriendMgmt(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "friend_mgmt"
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }
        var done = 0
        if b("auto_accept", true) {
            let (_, apply) = await LedouCGI.getPhonePk(
                cmd: "friend_change", extra: ["op": "getapplylist"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            var uins: [String] = []
            let re1 = try? NSRegularExpression(pattern: #"oppuin=(\d+)"#)
            let ns = apply as NSString
            re1?.enumerateMatches(in: apply, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 2 else { return }
                let u = ns.substring(with: m.range(at: 1))
                if !uins.contains(u) { uins.append(u) }
            }
            if uins.isEmpty {
                let re2 = try? NSRegularExpression(pattern: #""uin"\s*:\s*"?(\d+)"#)
                re2?.enumerateMatches(in: apply, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let m, m.numberOfRanges >= 2 else { return }
                    let u = ns.substring(with: m.range(at: 1))
                    if !uins.contains(u) { uins.append(u) }
                }
            }
            for uin in uins.prefix(10) {
                let (_, r) = await LedouCGI.getPhonePk(
                    cmd: "friend_change",
                    extra: ["op": "accessfriend", "oppuin": uin],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("同意\(uin)：\(CombatLog.fromBody(r))")
                done += 1
            }
            if uins.isEmpty { onLog("无好友申请") }
        }
        if b("auto_add") {
            onLog("自动加好友需查区名册，本轮跳过")
        }
        if b("auto_del") {
            onLog("自动删除需在查区标记后使用，本轮跳过批量删（防误删）")
        }
        return "好友处理\(done)"
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
