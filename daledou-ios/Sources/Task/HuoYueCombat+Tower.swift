import Foundation

/// 真源：斗神塔 `HuoYueCombat.farmDouShenTa`；问鼎/华山 `MoreExtraActions`。
extension HuoYueCombat {
    private static let maxTower = 200

    struct DouShenTaOpts {
        var freeOnce = true
        var maxTimes = false
        var share = true
        var day7Max = false

        static func fromStore() -> DouShenTaOpts {
            let t = FeatureToggleStore.shared
            let fid = "more_settings"
            return DouShenTaOpts(
                freeOnce: t.getBool(fid, "cb_doushenta_one", default: true),
                maxTimes: t.getBool(fid, "cb_doushenta_max", default: false),
                share: t.getBool(fid, "cb_doushenta_fenxiang", default: true),
                day7Max: t.getBool(fid, "cb_doushenta_day7_max", default: false)
            )
        }
    }

    // MARK: - 斗神塔

    static func farmDouShenTa(
        cookie: String,
        opts: DouShenTaOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let sunday = cal.component(.weekday, from: Date()) == 1
        let pullMax = opts.maxTimes || (opts.day7Max && sunday)
        let freeOnly = opts.freeOnce && !pullMax
        let maxRuns = pullMax ? 30 : 1
        onLog("斗神塔开始（\(pullMax ? "拉满次数" : "免费一次")\(opts.share ? "，监控分享" : "")）")

        var fights = 0
        var starts = 0
        var shareHitCap = false
        var lastLayer = -1
        var lastStatus = -99
        var idleStreak = 0
        var illegalStreak = 0

        func maybeShare(_ st: String) async {
            guard let layer = CombatLog.jsonInt(st, "cur_layer") else { return }
            if layer != lastLayer {
                lastLayer = layer
                onLog("当前层数\(layer)")
            }
            guard opts.share, !shareHitCap, layer > 0, layer % 5 == 0 else { return }
            if (91...99).contains(layer) {
                let (_, t10) = await LedouCGI.getPetPk(
                    cmd: "towerfight", extra: ["type": "10"], cookie: cookie
                )
                let m = CombatLog.fromBody(t10)
                if !m.isEmpty { onLog(m) }
            } else {
                let (_, share) = await LedouCGI.getPhonePk(
                    cmd: "sharegame",
                    extra: ["subtype": "2", "shareinfo": "4"],
                    cookie: cookie
                )
                if share.contains("分享成功") {
                    onLog("分享成功！")
                } else if share.contains("分享次数已达上限") {
                    onLog("您今日的分享次数已达上限！")
                    shareHitCap = true
                    let (_, t10) = await LedouCGI.getPetPk(
                        cmd: "towerfight", extra: ["type": "10"], cookie: cookie
                    )
                    let m = CombatLog.fromBody(t10)
                    if !m.isEmpty { onLog(m) }
                } else {
                    let m = CombatLog.fromBody(share)
                    if !m.isEmpty { onLog(m) }
                }
            }
            try? await Task.sleep(nanoseconds: gapNs)
        }

        func pollStatus() async -> String {
            let (_, st) = await LedouCGI.getPetPk(
                cmd: "towerfight", extra: ["type": "3"], cookie: cookie
            )
            await maybeShare(st)
            return st
        }

        func exhausted(_ st: String, inFight: Bool) -> String? {
            let day = CombatLog.jsonField(st, "day_left_times") ?? ""
            guard day == "0/1" else { return nil }
            let weekLeft = CombatLog.jsonInt(st, "week_left_times") ?? 0
            let weekMax = CombatLog.jsonInt(st, "week_max_times") ?? 0
            if weekLeft <= 0 && weekMax > 0 { return "次数已经用完了" }
            let spell = CombatLog.jsonInt(st, "towerspellnum") ?? 0
            if spell <= 0 && pullMax { return "斗神符不足，结束监听" }
            if freeOnly { return inFight ? "挑战结束" : "免费次数已用完" }
            return nil
        }

        func doStart() async -> Bool {
            let (_, start) = await LedouCGI.getPetPk(
                cmd: "towerfight", extra: ["type": "0"], cookie: cookie
            )
            let msg = CombatLog.fromBody(start)
            if !msg.isEmpty { onLog(msg) }
            starts += 1
            try? await Task.sleep(nanoseconds: gapNs)
            if towerStop(start) && !towerFatal(start) { return false }
            return true
        }

        while fights < maxTower && starts <= maxRuns + 2 && idleStreak < 12 {
            if Task.isCancelled { break }
            let st = await pollStatus()
            if towerFatal(st) && CombatLog.jsonInt(st, "status") == nil {
                illegalStreak += 1
                if illegalStreak >= 2 {
                    onLog("状态查询连续非法，已停止")
                    break
                }
                try? await Task.sleep(nanoseconds: gapNs)
                continue
            }
            illegalStreak = 0

            let status = CombatLog.jsonInt(st, "status") ?? -1
            let day = CombatLog.jsonField(st, "day_left_times") ?? ""
            let maxLayer = CombatLog.jsonInt(st, "max_layer") ?? 0
            if status != lastStatus {
                lastStatus = status
                onLog("status=\(status) day=\(day)")
            }

            if let reason = exhausted(st, inFight: status == 2 || status == 3) {
                onLog(reason)
                break
            }

            switch status {
            case 2, 3:
                idleStreak = 0
                let (_, fight) = await LedouCGI.getPetPk(
                    cmd: "towerfight", extra: ["type": "7"], cookie: cookie
                )
                fights += 1
                try? await Task.sleep(nanoseconds: gapNs)
                let msg = CombatLog.fromBody(fight)
                if !msg.isEmpty { onLog(msg) }
                if towerFatal(fight) {
                    idleStreak += 1
                    if idleStreak >= 3 {
                        onLog("战斗回非法且状态未恢复，已停止")
                        break
                    }
                } else if fight.contains("系统繁忙") || fight.contains("操作频繁") {
                    try? await Task.sleep(nanoseconds: gapNs)
                } else if towerStop(fight) {
                    if pullMax && starts < maxRuns {
                        onLog("本轮结束，等待再开")
                    } else {
                        break
                    }
                }
            case 0, 1:
                if freeOnly && day == "0/1" {
                    onLog("免费次数已用完")
                    break
                }
                if day == "0/1" && !pullMax {
                    onLog("次数已经用完了")
                    break
                }
                let canStart: Bool = {
                    if status == 0 && opts.share && !shareHitCap { return true }
                    if status == 0 && !opts.share { return true }
                    if status == 1 && opts.share && !shareHitCap { return true }
                    if status == 1 && maxLayer < 100 { return true }
                    return false
                }()
                if !canStart {
                    idleStreak += 1
                    try? await Task.sleep(nanoseconds: gapNs)
                    continue
                }
                if starts >= maxRuns && freeOnly {
                    onLog("免费一次已开塔，等待可战斗状态")
                    idleStreak += 1
                    if idleStreak >= 6 { break }
                    try? await Task.sleep(nanoseconds: gapNs)
                    continue
                }
                if !(await doStart()) {
                    onLog("开塔失败，已停止")
                    break
                }
                idleStreak = 0
            default:
                onLog("未知 status=\(status)，已停止")
                break
            }
        }
        onLog("斗神塔结束（战斗\(fights)次/开塔\(starts)次）")
        return "斗神塔战斗\(fights)"
    }

    private static func towerFatal(_ raw: String) -> Bool {
        if raw.isEmpty { return false }
        if raw.contains("非法操作") || raw.contains("号码不允许") || raw.contains("不允许有此操作") {
            return true
        }
        let msg = CombatLog.jsonField(raw, "msg") ?? ""
        return msg.contains("非法") || msg.contains("不允许")
    }

    private static func towerStop(_ raw: String) -> Bool {
        if raw.isEmpty { return false }
        if towerFatal(raw) { return true }
        let keys = [
            "挑战次数不足", "今日挑战次数", "没有挑战次数", "次数已用完",
            "次数已达上限", "无法继续挑战", "请明天再来", "已通关斗神塔",
        ]
        if keys.contains(where: { raw.contains($0) }) { return true }
        if let result = CombatLog.jsonInt(raw, "result"), result != 0 {
            let body = CombatLog.fromBody(raw)
            return body.contains("次数") || body.contains("不足")
        }
        return false
    }

    // MARK: - 问鼎

    static func farmWenDing(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "more_settings"
        let region: Int = {
            if t.getBool(fid, "rg_wd_qy_1", default: false) { return 1 }
            if t.getBool(fid, "rg_wd_qy_2", default: false) { return 2 }
            if t.getBool(fid, "rg_wd_qy_3", default: false) { return 3 }
            if t.getBool(fid, "rg_wd_qy_4", default: false) { return 4 }
            return 0
        }()
        if region <= 0 {
            onLog("请先在更多设置勾选东海/南荒/西泽/北寒")
            return "未选区域"
        }
        let useBook = t.getBool(fid, "cb_wending_tzs", default: false)
        let abandonAbove = useBook ? 1 : 3
        let occupyAt = useBook ? 1 : 3
        let names = ["", "东海", "南荒", "西泽", "北寒"]
        onLog("打满问鼎开始（\(names[region])\(useBook ? "·挑战书" : "")）")

        var occupies = 0
        var retries = 0
        while occupies < 30 && retries < 50 {
            if Task.isCancelled { break }
            let (_, page) = await LedouCGI.getPetPk(
                cmd: "tbattle",
                extra: ["op": "showregion", "region": "\(region)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(page)
            if page.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            if msg.contains("当前时段不能") || page.contains("当前时段不能") {
                onLog(msg.ifEmpty("当前时段不能操作"))
                break
            }
            let left = CombatLog.jsonInt(page, "left_fight_times")
                ?? page.firstInt(pattern: #"剩余挑战[：:]\s*(\d+)"#)
            if let left, left <= 0 {
                onLog("挑战次数用完")
                break
            }
            let hasLand = page.contains("放弃") || page.contains("op=abandon")
                || (page.contains("owner_name") && !page.contains("\"owner_name\":\"暂无\""))
            if hasLand, let left, left > abandonAbove {
                let (_, ab) = await LedouCGI.getPetPk(
                    cmd: "tbattle", extra: ["op": "abandon"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(ab).ifEmpty("放弃领地"))
                continue
            }
            guard let id = pickWenDingId(page) else {
                retries += 1
                if retries >= 50 {
                    onLog("未找到合适目标")
                    break
                }
                continue
            }
            if let left, left > occupyAt, hasLand {
                _ = await LedouCGI.getPetPk(
                    cmd: "tbattle", extra: ["op": "abandon"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
            }
            let (_, occ) = await LedouCGI.getPetPk(
                cmd: "tbattle", extra: ["op": "occupy", "id": id], cookie: cookie
            )
            occupies += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let om = CombatLog.fromBody(occ)
            if !om.isEmpty { onLog(om) }
            if om.contains("挑战书不足") || om.contains("当前时段不能")
                || occ.contains("挑战书不足") || occ.contains("当前时段不能")
            {
                break
            }
            if om.contains("不足") && om.contains("次数") { break }
            retries = 0
        }
        onLog("打满问鼎结束")
        return "问鼎占\(occupies)"
    }

    private static func pickWenDingId(_ page: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\{[^{}]*"id"\s*:\s*"?(\d+)[^{}]*\}"#) else {
            return fallbackOccupyId(page)
        }
        let ns = page as NSString
        let matches = re.matches(in: page, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let block = ns.substring(with: m.range)
            guard let id = block.firstMatch(pattern: #""id"\s*:\s*"?(\d+)"#) else { continue }
            let owner = block.firstMatch(pattern: #""owner_name"\s*:\s*"([^"]*)""#) ?? ""
            let faction = block.firstMatch(pattern: #""owner_faction_name"\s*:\s*"([^"]*)""#) ?? ""
            let combat = Int(block.firstMatch(pattern: #""owner_combat_points"\s*:\s*"?(\d+)"#) ?? "") ?? 999_999
            let exploits = Int(block.firstMatch(pattern: #""exploits_left"\s*:\s*"?(\d+)"#) ?? "") ?? 0
            let empty = (owner == "暂无" || owner.isEmpty) && (faction == "暂无" || faction.isEmpty)
            let weak = combat <= 1000
            if (empty || weak) && exploits >= 200 { return id }
        }
        return fallbackOccupyId(page)
    }

    private static func fallbackOccupyId(_ page: String) -> String? {
        page.firstMatch(pattern: #"op=occupy[^"'\s]*id=(\d+)"#)
            ?? page.firstMatch(pattern: #"id=(\d+)[^>]{0,40}占领"#)
    }

    // MARK: - 华山论剑

    static func farmHuaShan(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let fid = "more_settings"
        let restore = t.getBool(fid, "cb_hslj_1", default: false)
        let payTicket = t.getBool(fid, "cb_hslj_fufei", default: false)
        let swap = t.getBool(fid, "cb_hslj_hzr", default: false)
        onLog("华山论剑开始")
        var fights = 0
        var loops = 0
        while loops < 40 {
            loops += 1
            if Task.isCancelled { break }
            let (_, page) = await LedouCGI.getPetPk(cmd: "knightarena", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            let free = CombatLog.jsonInt(page, "left_free_times")
                ?? page.firstInt(pattern: #"免费次数[：:]\s*(\d+)"#)
            if let free { onLog("免费次数：\(free)") }
            if (free == nil || free! <= 0) && !(payTicket && swap) {
                onLog("免费次数用完（未开入场券+换阵）")
                break
            }
            if restore {
                let (_, dorm) = await LedouCGI.getPetPk(
                    cmd: "knightarena", extra: ["op": "dormteam"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                var knights = allMatches(
                    pattern: #""id"\s*:\s*"?(\d+)[^}]*"durability"\s*:\s*"?0"#,
                    in: dorm
                )
                if knights.isEmpty {
                    knights = allMatches(
                        pattern: #"durability["\s:=]+0[\s\S]{0,40}?id["\s:=]+(\d+)"#,
                        in: dorm
                    )
                }
                for kid in knights.prefix(6) {
                    let (_, add) = await LedouCGI.getPetPk(
                        cmd: "knightarena",
                        extra: ["op": "adddurability", "id": kid],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let am = CombatLog.fromBody(add)
                    if !am.isEmpty { onLog("恢复耐久:\(am)") }
                    if am.contains("不足") { break }
                }
            }
            let (_, ch) = await LedouCGI.getPetPk(
                cmd: "knightarena", extra: ["op": "challenge"], cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let cmsg = CombatLog.fromBody(ch)
            if !cmsg.isEmpty { onLog(cmsg) }
            if cmsg.contains("门票不足") || cmsg.contains("上限")
                || ch.contains("门票不足") || ch.contains("上限")
            {
                break
            }
            if cmsg.contains("不足") && restore { continue }
            if cmsg.contains("不足") || ch.contains("没有挑战") { break }
        }
        let (_, rank) = await LedouCGI.getPhonePk(
            cmd: "knightarena", extra: ["op": "drawranking"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let rm = CombatLog.fromBody(rank)
        if !rm.isEmpty { onLog("排行:\(rm)") }
        onLog("华山论剑结束")
        return "华山\(fights)"
    }

    private static func allMatches(pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            guard $0.numberOfRanges > 1 else { return nil }
            return ns.substring(with: $0.range(at: 1))
        }
    }
}

private extension String {
    func ifEmpty(_ alt: @autoclosure () -> String) -> String {
        isEmpty ? alt() : self
    }

    func firstMatch(pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: self)
        else { return nil }
        return String(self[r])
    }

    func firstInt(pattern: String) -> Int? {
        firstMatch(pattern: pattern).flatMap(Int.init)
    }
}
