import Foundation

/// 真源：`HuoYueCombat.kt` — 巅峰 / 竞技场 / 抢地盘。
extension HuoYueCombat {
    private static let maxArena = 40
    private static let maxDianFeng = 80
    private static let maxQdp = 12

    struct DianFengOpts {
        var line = 0
        static func fromStore() -> DianFengOpts {
            let t = FeatureToggleStore.shared
            let fid = "daiwan"
            if t.getBool(fid, "rb_dianfeng_1", default: false) { return DianFengOpts(line: 1) }
            if t.getBool(fid, "rb_dianfeng_2", default: false) { return DianFengOpts(line: 2) }
            if t.getBool(fid, "rb_dianfeng_3", default: false) { return DianFengOpts(line: 3) }
            return DianFengOpts(line: 0)
        }
    }

    struct QiangDiPanOpts {
        var lv1 = true
        var lv2 = true
        var lv3 = true
        var lv4 = true
        var bossOnly = false
        var claimReward = true
        var abandonAfterReward = false
        var recommendType = 11

        static func fromStore() -> QiangDiPanOpts {
            let t = FeatureToggleStore.shared
            let fid = "qiangdipan"
            return QiangDiPanOpts(
                lv1: t.getBool(fid, "cb_dp_1", default: true),
                lv2: t.getBool(fid, "cb_dp_2", default: true),
                lv3: t.getBool(fid, "cb_dp_3", default: true),
                lv4: t.getBool(fid, "cb_dp_4", default: true),
                bossOnly: t.getBool(fid, "cb_boss", default: false),
                claimReward: true,
                abandonAfterReward: t.getBool(fid, "cb_zd_fq", default: false),
                recommendType: {
                    let s = t.getString(fid, "type")
                    return Int(s).flatMap { $0 > 0 ? $0 : nil } ?? 11
                }()
            )
        }
    }

    /// 周一 0–5 / 周三≥6 / 周四～周日（GMT+8）。
    static func canDianFengNow() -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let w = cal.component(.weekday, from: now)
        let mon1 = w == 1 ? 7 : w - 1
        let h = cal.component(.hour, from: now)
        let blocked = (mon1 != 3 || h < 6) && ((mon1 != 1 || h >= 6) && mon1 <= 3)
        return !blocked
    }

    // MARK: - 巅峰

    static func farmDianFeng(
        cookie: String,
        opts: DianFengOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        if !canDianFengNow() {
            onLog("当前时间不能进行巅峰挑战")
            return "非挑战时段"
        }
        var road = opts.line
        if road <= 0 { road = Int.random(in: 1...3) }
        onLog("巅峰挑战开始（线=\(road)）")

        let (_, home) = await LedouCGI.getPhonePk(cmd: "gvg", extra: ["sub": "0"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        if home.contains("系统繁忙") {
            onLog("系统繁忙，巅峰改日再试")
            return "系统繁忙"
        }
        if !CombatLog.brLine(home, "切换").isEmpty || home.contains("切换") {
            let (_, sw) = await LedouCGI.getPhonePk(
                cmd: "gvg", extra: ["sub": "6", "road": "\(road)"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog(CombatLog.fromBody(sw).ifEmpty("已切线\(road)"))
        } else if CombatLog.brLine(home, "征战").isEmpty && !home.contains("征战") {
            onLog(CombatLog.fromBody(home).ifEmpty("巅峰入口无征战/切换，已跳过"))
            return "无征战入口"
        }

        var rounds = 0
        while rounds < maxDianFeng {
            if Task.isCancelled { break }
            let (_, f) = await LedouCGI.getPhonePk(cmd: "gvg", extra: ["sub": "5"], cookie: cookie)
            rounds += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let line = CombatLog.fromBody(f).ifEmpty(CombatLog.brLine(f, "等级"))
            if !line.isEmpty { onLog(line) }
            if f.contains("您今天挑战次数已经达到上限了") || f.contains("挑战次数已经达到上限") {
                onLog("巅峰之战结束（次数上限）")
                break
            }
            if f.contains("请您先报名再挑战") {
                onLog("请您先报名再挑战，巅峰之战结束")
                break
            }
            if f.contains("用完复活次数了") {
                onLog("用完复活次数了，巅峰之战结束")
                break
            }
            if f.contains("撒花祝贺") {
                onLog("巅峰之战结束")
                break
            }
            if f.contains("等级") && !f.contains("系统繁忙") {
                onLog("巅峰之战结束")
                break
            }
            if f.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: gapNs)
            }
        }
        return "巅峰轮询\(rounds)次/线\(road)"
    }

    // MARK: - 竞技场

    static func farmJingJiChang(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog("竞技场挑战开始")
        var (_, page) = await LedouCGI.getPhonePk(cmd: "arena", cookie: cookie)
        if page.contains("使用规则") && page.contains("系统繁忙") {
            try? await Task.sleep(nanoseconds: gapNs)
            (_, page) = await LedouCGI.getPhonePk(cmd: "arena", cookie: cookie)
        }
        let season = CombatLog.brLine(page, "赛季状态：")
            .ifEmpty(page.contains("赛季状态：") ? "赛季中" : "")
        if !season.isEmpty { onLog(season) }

        var fights = 0
        while fights < maxArena {
            if Task.isCancelled { break }
            let free = page.contains("挑战消耗：免费挑战") || page.contains("免费挑战")
            if !free { break }
            let (_, r) = await LedouCGI.getPhonePk(
                cmd: "arena", extra: ["op": "challenge"], cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            if r.contains("系统繁忙") || r.contains("操作频繁") {
                onLog("系统繁忙")
                try? await Task.sleep(nanoseconds: gapNs)
                (_, page) = await LedouCGI.getPhonePk(cmd: "arena", cookie: cookie)
                continue
            }
            let line = CombatLog.prefer(r, "打翻在地", "惜败", "战胜", "挑战", "积分")
                .ifEmpty(CombatLog.fromBody(r))
            onLog(line.ifEmpty("挑战#\(fights)"))
            page = r
            if !r.contains("免费挑战") && !r.contains("挑战消耗：免费挑战") {
                let (_, confirm) = await LedouCGI.getPhonePk(cmd: "arena", cookie: cookie)
                page = confirm
                if !confirm.contains("免费挑战") { break }
            }
        }
        let (_, daily) = await LedouCGI.getPetPk(
            cmd: "arena", extra: ["op": "dailyreward"], cookie: cookie
        )
        let dailyMsg = CombatLog.fromBody(daily)
        if !dailyMsg.isEmpty { onLog("日结：\(dailyMsg)") }
        let (_, rank) = await LedouCGI.getPetPk(
            cmd: "arena", extra: ["op": "rankingreward"], cookie: cookie
        )
        let rankMsg = CombatLog.fromBody(rank)
        if !rankMsg.isEmpty { onLog("排行：\(rankMsg)") }
        onLog("竞技场结束（挑战\(fights)场）")
        return "竞技场挑战\(fights)"
    }

    // MARK: - 抢地盘

    static func farmQiangDiPan(
        cookie: String,
        opts: QiangDiPanOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog("抢地盘开始")
        if opts.claimReward {
            let (_, rew) = await LedouCGI.getPetPk(
                cmd: "get", extra: ["type": "1"], cookie: cookie
            )
            let name = CombatLog.jsonField(rew, "name")
            let msg = CombatLog.fromBody(rew)
            if let name, !name.isEmpty {
                onLog("地盘领奖：\(name)")
            } else if !msg.isEmpty {
                onLog("地盘领奖：\(msg)")
            } else {
                onLog("地盘领奖完成")
            }
            if opts.abandonAfterReward && (rew.contains("领取") || !(name ?? "").isEmpty) {
                let (_, ab) = await LedouCGI.getPhonePk(cmd: "abandonmanor", cookie: cookie)
                onLog(CombatLog.fromBody(ab).ifEmpty("放弃地盘"))
            }
            try? await Task.sleep(nanoseconds: gapNs)
        }

        _ = await LedouCGI.getPetPk(
            cmd: "visitmanor", extra: ["manorid": "0"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)

        var fights = 0
        let (_, listRaw) = await LedouCGI.getPetPk(
            cmd: "recommendmanor",
            extra: ["type": "\(opts.recommendType)"],
            cookie: cookie
        )
        if listRaw.contains("系统繁忙") {
            onLog("系统繁忙")
            try? await Task.sleep(nanoseconds: gapNs)
        }

        func allMatches(_ pattern: String, in text: String, group: Int = 1) -> [String] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = text as NSString
            return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
                guard $0.numberOfRanges > group else { return nil }
                return ns.substring(with: $0.range(at: group))
            }
        }

        let manorIds = Array(Set(allMatches(#""id"\s*:\s*"?(\d+)"?"#, in: listRaw))).sorted()
        // keep first-occurrence order
        let orderedIds = allMatches(#""id"\s*:\s*"?(\d+)"?"#, in: listRaw).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let levels = allMatches(#""level"\s*:\s*(\d+)"#, in: listRaw).compactMap(Int.init)
        let owners = allMatches(#""ownername"\s*:\s*"((?:\\.|[^"\\])*)""#, in: listRaw)

        func lvOk(_ lv: Int) -> Bool {
            switch lv {
            case 1: return opts.lv1
            case 2: return opts.lv2
            case 3: return opts.lv3
            case 4: return opts.lv4
            default: return true
            }
        }

        let ids = orderedIds.isEmpty ? manorIds : orderedIds
        for i in ids.indices {
            if fights >= maxQdp { break }
            if Task.isCancelled { break }
            let id = ids[i]
            let lv = i < levels.count ? levels[i] : 0
            let owner = i < owners.count ? owners[i] : ""
            if opts.bossOnly {
                if owner != "守将程关大侠" { continue }
            } else if (1...4).contains(lv) && !lvOk(lv) {
                continue
            }
            let (_, fight) = await LedouCGI.getPhonePk(
                cmd: "manorfight",
                extra: ["fighttype": "1", "manorid": id],
                cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let line = CombatLog.prefer(fight, "领主", "摆平", "攻占", "战败", "胜利")
                .ifEmpty(CombatLog.fromBody(fight))
            onLog(line.ifEmpty("攻占\(id)"))
            if fight.contains("你成为该地盘领主") { break }
            if fight.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: gapNs)
            }
        }

        for _ in 0..<3 {
            if Task.isCancelled { break }
            let (_, spar) = await LedouCGI.getPetPk(
                cmd: "manorfight",
                extra: ["type": "2", "manorid": "1100016"],
                cookie: cookie
            )
            let m = CombatLog.fromBody(spar)
            if !m.isEmpty { onLog("切磋：\(m)") }
            if spar.contains("次数") && (spar.contains("不足") || spar.contains("上限")) { break }
            try? await Task.sleep(nanoseconds: gapNs)
        }

        onLog("抢地盘结束（攻占\(fights)次）")
        return "抢地盘攻占\(fights)"
    }
}

private extension String {
    func ifEmpty(_ alt: @autoclosure () -> String) -> String {
        isEmpty ? alt() : self
    }
}
