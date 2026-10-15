import Foundation

/// 真源：`HuoYueCombat.kt` — 12宫 / Boss / 会武 / 门派。
extension HuoYueCombat {
    private static let maxGong12 = 30
    private static let maxBoss = 25
    private static let maxHuiWu = 30
    private static let maxMenPai = 40

    // MARK: Opts

    struct Gong12Opts {
        var sao = true
        var dan = true
        static func fromStore() -> Gong12Opts {
            let t = FeatureToggleStore.shared
            let sao = t.getBool("daiwan", "rb_12gong_sao", default: false)
            let dan = t.getBool("daiwan", "rb_12gong_dan", default: false)
            if !sao && !dan { return Gong12Opts() }
            return Gong12Opts(sao: sao || !dan, dan: dan)
        }
    }

    struct BossOpts {
        var haoYou = false
        var bangPai = false
        var xiaBai = false
        var autoTiLi = false
        var autoGongXian = false
        var anySource: Bool { haoYou || bangPai || xiaBai }

        static func fromStore() -> BossOpts {
            let t = FeatureToggleStore.shared
            var o = BossOpts(
                haoYou: t.getBool("daiwan", "cb_boss_haoyou", default: false),
                bangPai: t.getBool("daiwan", "cb_boss_bangpai", default: false),
                xiaBai: t.getBool("daiwan", "cb_boss_xiabai", default: false),
                autoTiLi: t.getBool("daiwan", "cb_boss_tili", default: false),
                autoGongXian: t.getBool("daiwan", "cb_boss_gongxian", default: false)
            )
            // 代玩设置页未接时：回落到活跃页乐斗目标池
            if !o.anySource {
                o.haoYou = t.getBool("huoyue", "lv_fight_boss_hy", default: true)
                o.bangPai = t.getBool("huoyue", "lv_fight_boss_bp", default: true)
                o.xiaBai = t.getBool("huoyue", "lv_fight_boss_xb", default: true)
                o.autoTiLi = t.getBool("huoyue", "lv_fight_tili", default: true)
            }
            return o
        }
    }

    struct HuiWuOpts {
        var freeOnly = true
        var payOk = false
        var swapBook = false
        static func fromStore() -> HuiWuOpts {
            let t = FeatureToggleStore.shared
            let pay = t.getBool("daiwan", "rb_huiwu_fufei", default: false)
            let free = t.getBool("daiwan", "rb_huiwu_mianfi", default: true)
            return HuiWuOpts(
                freeOnly: free || !pay,
                payOk: pay,
                swapBook: t.getBool("daiwan", "cb_huiwu_huanshu", default: false)
            )
        }
    }

    struct MenPaiOpts {
        var xiangLu = true
        var xiangLuGao = false
        var xiangLuGaoHuan = false
        var muZhuang = true
        var qieCuo1 = true
        var qieCuo2 = true
        var qieCuoHuan = false
        var qieCuoBoss = false
        var yaoQingSai = false
        var yaoQingSaiMan = false
        var yaoQingSaiSkipSun = false

        static func fromStore() -> MenPaiOpts {
            let t = FeatureToggleStore.shared
            let fid = "daiwan"
            let o = MenPaiOpts(
                xiangLu: t.getBool(fid, "cb_menpai_xianglu", default: false),
                xiangLuGao: t.getBool(fid, "cb_menpai_xianglu_gaoji", default: false),
                xiangLuGaoHuan: t.getBool(fid, "cb_menpai_xianglu_gaoji_huan", default: false),
                muZhuang: t.getBool(fid, "cb_menpai_muzhuang", default: false),
                qieCuo1: t.getBool(fid, "cb_menpai_qiecuo", default: false),
                qieCuo2: t.getBool(fid, "cb_menpai_qiecuo_1", default: false),
                qieCuoHuan: t.getBool(fid, "cb_menpai_qiecuo_huan", default: false),
                qieCuoBoss: t.getBool(fid, "cb_menpai_qiecuo_boss", default: false),
                yaoQingSai: t.getBool(fid, "cb_menpai_yaoqingsai", default: false),
                yaoQingSaiMan: t.getBool(fid, "cb_menpai_yaoqingsai_huan", default: false),
                yaoQingSaiSkipSun: t.getBool(fid, "cb_menpai_yaoqingsai_zhouri", default: false)
            )
            let any = o.xiangLu || o.xiangLuGao || o.muZhuang || o.qieCuo1 || o.qieCuo2
                || o.qieCuoBoss || o.yaoQingSai
            return any ? o : MenPaiOpts()
        }
    }

    // MARK: - 12宫

    static func farmGong12(
        cookie: String,
        opts: Gong12Opts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        var fights = 0
        let (_, raw) = await LedouCGI.getPetPk(
            cmd: "zodiacdungeon", extra: ["op": "query"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        if raw.contains("系统繁忙") {
            onLog("系统繁忙，12宫改日再试")
            return "系统繁忙"
        }
        if let result = CombatLog.jsonInt(raw, "result"), result != 0 {
            let msg = CombatLog.jsonField(raw, "msg").flatMap { $0.isEmpty ? nil : $0 }
                ?? CombatLog.fromBody(raw)
            onLog(msg.ifEmpty("12宫查询失败"))
            return msg.ifEmpty("查询失败")
        }
        let scene = [
            CombatLog.jsonField(raw, "max_scene_id"),
            CombatLog.jsonField(raw, "current_scene_id"),
            CombatLog.jsonField(raw, "latest_scene_id"),
        ].compactMap { $0 }.first { !$0.isEmpty && $0 != "0" } ?? ""
        if scene.isEmpty {
            onLog("无有效场景 id（max_scene_id 空），已跳过，避免非法场景")
            return "无场景id"
        }
        let canAuto = CombatLog.jsonField(raw, "can_auto_fight")
        let pal = CombatLog.jsonField(raw, "latest_pal_uin") ?? ""
        onLog("12宫挑战开始（场景\(scene)；\(opts.sao ? "扫荡" : "不扫荡")\(opts.dan ? "+可手动" : "")）")

        func readPos(_ json: String) -> Int {
            if let cur = CombatLog.jsonInt(json, "current_pos"), cur > 0 { return cur }
            return CombatLog.jsonInt(json, "pos") ?? 0
        }

        func manualFight(seed: String) async -> Bool {
            if !opts.dan {
                onLog("未勾选「不扫荡/手动」，进度不足已跳过")
                return false
            }
            var page = seed
            var palUin = (CombatLog.jsonField(page, "latest_pal_uin") ?? "").ifEmpty(pal)
            if palUin.isEmpty {
                onLog("进度不足且无助手 uin，无法手动打，已跳过")
                return false
            }
            while fights < maxGong12 {
                if Task.isCancelled { return false }
                let pos = readPos(page)
                if pos <= 0 {
                    onLog("当前格子为空，不能发 pos=0（否则服务器回 pos非法），已停止")
                    return false
                }
                onLog("改手动战斗 pos=\(pos)")
                let (_, f) = await LedouCGI.getPetPk(
                    cmd: "zodiacdungeon",
                    extra: [
                        "op": "fight",
                        "scene_id": scene,
                        "pos": "\(pos)",
                        "pal_uin": palUin,
                    ],
                    cookie: cookie
                )
                fights += 1
                try? await Task.sleep(nanoseconds: gapNs)
                let line = (CombatLog.jsonField(f, "msg") ?? "")
                    .ifEmpty(CombatLog.fromBody(f))
                    .ifEmpty("手动战\(fights)")
                onLog(line)
                if f.contains("非法场景") || line.contains("非法")
                    || f.contains("明天再来") || f.contains("复活")
                    || line.contains("明天再来") || line.contains("复活")
                    || (f.contains("不足") && !f.contains("进度不足"))
                {
                    if f.contains("复活") || line.contains("复活") {
                        _ = await LedouCGI.getPetPk(
                            cmd: "zodiacdungeon", extra: ["op": "cancle"], cookie: cookie
                        )
                    }
                    break
                }
                let (_, q) = await LedouCGI.getPetPk(
                    cmd: "zodiacdungeon", extra: ["op": "query"], cookie: cookie
                )
                page = q
                try? await Task.sleep(nanoseconds: gapNs)
                palUin = (CombatLog.jsonField(page, "latest_pal_uin") ?? "").ifEmpty(palUin)
            }
            return true
        }

        if !opts.sao {
            _ = await manualFight(seed: raw)
            return "12宫手动\(fights)次/场景\(scene)"
        }
        if canAuto == "0" || canAuto == "false" {
            _ = await manualFight(seed: raw)
            return "12宫手动\(fights)次/场景\(scene)"
        }

        while fights < maxGong12 {
            if Task.isCancelled { break }
            let (_, f) = await LedouCGI.getPetPk(
                cmd: "zodiacdungeon",
                extra: ["op": "autofight", "pay_recovery_count": "0", "scene_id": scene],
                cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let line = (CombatLog.jsonField(f, "msg") ?? "")
                .ifEmpty(CombatLog.fromBody(f))
                .ifEmpty("自动战\(fights)")
            onLog(line)
            if f.contains("非法场景") || line.contains("非法场景") {
                onLog("场景id=\(scene) 非法，已停止")
                break
            }
            if line.contains("进度不足") || f.contains("进度不足")
                || line.contains("不足以使用自动") || f.contains("不足以使用自动")
            {
                _ = await manualFight(seed: raw)
                break
            }
            if f.contains("不足") || f.contains("明天再来") || f.contains("复活")
                || line.contains("不足") || line.contains("明天再来")
            {
                if f.contains("复活") || line.contains("复活") {
                    _ = await LedouCGI.getPetPk(
                        cmd: "zodiacdungeon", extra: ["op": "cancle"], cookie: cookie
                    )
                }
                break
            }
            if f.contains("\"records\"") && f.contains("复活") {
                _ = await LedouCGI.getPetPk(
                    cmd: "zodiacdungeon", extra: ["op": "cancle"], cookie: cookie
                )
                break
            }
        }
        return "12宫自动\(fights)次/场景\(scene)"
    }

    // MARK: - Boss

    static func farmBoss(
        cookie: String,
        opts: BossOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog("Boss挑战开始")
        if !opts.anySource {
            onLog("未勾选好友/帮派/侠拜，已跳过（请在代玩设置勾选）")
            return "未勾选来源"
        }
        await ensureBossAutoPotions(cookie: cookie, opts: opts, onLog: onLog)
        var fights = 0
        var wins = 0
        var tiliTried = false

        func extractXiaUins(_ html: String) -> [String] {
            var out: [String] = []
            let parts = html.components(separatedBy: CharacterSet(charactersIn: "\n"))
                .flatMap { $0.components(separatedBy: "<br />") }
                .flatMap { $0.components(separatedBy: "<br/>") }
                .flatMap { $0.components(separatedBy: "<br>") }
            for line in parts where line.contains("侠：") && !line.contains("已乐斗") {
                let s = line.replacingOccurrences(of: "&amp;", with: "&")
                if let re = try? NSRegularExpression(pattern: #"B_UID=(\d+)"#),
                   let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                   let r = Range(m.range(at: 1), in: s)
                {
                    let u = String(s[r])
                    if !out.contains(u) { out.append(u) }
                }
            }
            return out
        }

        func fightAll(_ uins: [String], type: String, tag: String) async -> Bool {
            for uin in uins {
                if fights >= maxBoss { return false }
                var same = 0
                while same < 3 && fights < maxBoss {
                    if Task.isCancelled { return true }
                    let (_, f) = await LedouCGI.getPhonePk(
                        cmd: "fight",
                        extra: [
                            "B_UID": uin,
                            "page": type == "2" ? "1" : "",
                            "type": type,
                        ],
                        cookie: cookie
                    )
                    fights += 1
                    same += 1
                    try? await Task.sleep(nanoseconds: gapNs)
                    let line = CombatLog.prefer(f, "打翻在地", "贡献度", "你干掉了")
                        .ifEmpty(CombatLog.fromBody(f))
                    onLog("[\(tag)]\(uin) \(line.ifEmpty("挑战"))")
                    if f.contains("体力值不足") || f.contains("请好好休息") {
                        if opts.autoTiLi && !tiliTried {
                            tiliTried = true
                            onLog("体力不足，尝试开启自动体力后继续")
                            var copy = opts
                            copy.autoTiLi = true
                            await ensureBossAutoPotions(cookie: cookie, opts: copy, onLog: onLog)
                            continue
                        }
                        onLog("体力不足，Boss 结束")
                        return true
                    }
                    if f.contains("打翻在地") || f.contains("贡献度") || f.contains("你干掉了") {
                        wins += 1
                        break
                    }
                    if f.contains("才可以挑战") || f.contains("还没有结婚")
                        || f.contains("已经和挑战过了") || f.contains("追魂锁链")
                        || f.contains("已乐斗")
                    {
                        break
                    }
                    if f.contains("系统繁忙") {
                        try? await Task.sleep(nanoseconds: gapNs)
                    } else {
                        break
                    }
                }
            }
            return false
        }

        if opts.xiaBai {
            let (_, page) = await LedouCGI.getPhonePk(cmd: "viewxialv", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapSkipNs)
            let uins = extractXiaUins(page)
            onLog("侠侣可打\(uins.count)人")
            if await fightAll(uins, type: "10", tag: "侠侣") {
                onLog("Boss挑战结束")
                return "Boss战斗\(fights)/胜约\(wins)"
            }
        }
        if fights < maxBoss && opts.bangPai {
            let (_, page) = await LedouCGI.getPhonePk(cmd: "viewmem", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapSkipNs)
            let uins = extractXiaUins(page)
            onLog("帮派可打\(uins.count)人")
            if await fightAll(uins, type: "2", tag: "帮派") {
                onLog("Boss挑战结束")
                return "Boss战斗\(fights)/胜约\(wins)"
            }
        }
        if fights < maxBoss && opts.haoYou {
            let (_, page) = await LedouCGI.getPhonePk(
                cmd: "friendlist", extra: ["page": "1"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapSkipNs)
            let uins = extractXiaUins(page)
            onLog("好友可打\(uins.count)人")
            _ = await fightAll(uins, type: "2", tag: "好友")
        }
        onLog("Boss挑战结束")
        return "Boss战斗\(fights)/胜约\(wins)"
    }

    private static func ensureBossAutoPotions(
        cookie: String, opts: BossOpts, onLog: @escaping (String) -> Void
    ) async {
        func sync(wantOn: Bool, openHint: String, closeHint: String, setType: String, tag: String) async {
            let (_, page) = await LedouCGI.getPhonePk(cmd: "view", extra: ["type": "6"], cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            let needOn = wantOn && page.contains(openHint)
            let needOff = !wantOn && page.contains(closeHint)
            if !needOn && !needOff {
                if wantOn && page.contains(closeHint) { onLog("[\(tag)]已开启") }
                return
            }
            let (_, r) = await LedouCGI.getPhonePk(cmd: "set", extra: ["type": setType], cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            if r.contains(closeHint) {
                onLog("[\(tag)]已开启")
            } else if r.contains(openHint) {
                onLog("[\(tag)]已取消")
            } else {
                onLog("[\(tag)]\(CombatLog.fromBody(r).ifEmpty("切换完成"))")
            }
        }
        await sync(
            wantOn: opts.autoGongXian,
            openHint: "开启自动使用贡献药水",
            closeHint: "取消自动使用贡献药水",
            setType: "4",
            tag: "贡献药水"
        )
        await sync(
            wantOn: opts.autoTiLi,
            openHint: "开启自动使用体力药水",
            closeHint: "取消自动使用体力药水",
            setType: "0",
            tag: "体力药水"
        )
    }

    // MARK: - 会武

    /// 周一～周三全天 + 周四 6 点前（GMT+8）。
    static func canHuiWuChallengeNow() -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let w = cal.component(.weekday, from: now) // 1=Sun … 7=Sat
        let mon1 = w == 1 ? 7 : w - 1
        let h = cal.component(.hour, from: now)
        let blocked = (mon1 != 1 || h < 6) && mon1 >= 4 && (mon1 != 4 || h >= 6)
        return !blocked
    }

    static func farmHuiWu(
        cookie: String,
        opts: HuiWuOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        if !canHuiWuChallengeNow() {
            onLog("当前时段不能会武挑战（仅周一～周三及周四6点前）")
            let (_, reward) = await LedouCGI.getPetPk(
                cmd: "sectmelee", extra: ["op": "drawreward"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("领奖：\(CombatLog.fromBody(reward).ifEmpty("已请求"))")
            let (_, cheer) = await LedouCGI.getPetPk(
                cmd: "sectmelee",
                extra: ["op": "cheer", "sect": "1003"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let cheerMsg = CombatLog.fromBody(cheer)
            if !cheerMsg.isEmpty && !cheerMsg.contains("当前时段不能") {
                onLog("助威：\(cheerMsg)")
            } else if cheerMsg.contains("当前时段不能") {
                onLog("助威：当前时段不可助威，已跳过")
            }
            return "会武非挑战时段：已领奖"
        }
        onLog("会武挑战开始")
        var fights = 0
        var passStreak = 0
        var bookSwapped = false
        var bossTried = false
        while fights < maxHuiWu {
            if Task.isCancelled { break }
            let (_, f) = await LedouCGI.getPhonePk(
                cmd: "sectmelee", extra: ["op": "dotraining"], cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            if f.contains("系统繁忙") {
                onLog("系统繁忙")
                try? await Task.sleep(nanoseconds: gapNs)
                continue
            }
            let line = CombatLog.prefer(
                f, "战胜", "惜败", "你已达今日挑战上限", "当前时段不能", "试炼书不足", "已通关"
            ).ifEmpty(CombatLog.fromBody(f))
            onLog(line.ifEmpty("会武\(fights)"))
            if f.contains("你已达今日挑战上限") || line.contains("你已达今日挑战上限")
                || f.contains("今日挑战上限")
            {
                break
            }
            if f.contains("当前时段不能") || line.contains("当前时段不能") { break }
            if f.contains("试炼书不足") || line.contains("试炼书不足") {
                if opts.payOk && opts.swapBook && !bookSwapped {
                    bookSwapped = true
                    let (_, ex) = await LedouCGI.getPhonePk(
                        cmd: "exchange",
                        extra: ["subtype": "2", "type": "1265", "times": "1", "costtype": "13"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(ex).ifEmpty("兑换试炼书已请求"))
                    continue
                }
                onLog(opts.payOk ? "试炼书不足" : "免费次数用完（试炼书也没了，不自动购买）")
                break
            }
            let fought = f.contains("战胜") || f.contains("惜败")
                || line.contains("战胜") || line.contains("惜败")
            let passed = !fought && (f.contains("已通关") || line.contains("已通关") || line.contains("通过了"))
            if passed {
                if !bossTried {
                    bossTried = true
                    let hit = await fightHuiWuBoss(cookie: cookie, html: f, onLog: onLog)
                    if hit > 0 {
                        fights += hit
                        passStreak = 0
                        continue
                    }
                }
                passStreak += 1
                if passStreak >= 2 {
                    onLog("试炼场已通关且没有后续战斗，停止")
                    break
                }
                continue
            }
            passStreak = 0
        }
        return "会武训练\(fights)次"
    }

    private static func fightHuiWuBoss(
        cookie: String, html: String, onLog: @escaping (String) -> Void
    ) async -> Int {
        let src = html.replacingOccurrences(of: "&amp;", with: "&")
        guard let re = try? NSRegularExpression(
            pattern: #"<a[^>]*href\s*=\s*["']([^"']*cmd=sectmelee[^"']*)["'][^>]*>\s*([^<]{0,32})"#,
            options: .caseInsensitive
        ) else { return 0 }
        let ns = src as NSString
        var pairs: [(String, String)] = []
        re.enumerateMatches(in: src, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 3 else { return }
            let href = ns.substring(with: m.range(at: 1))
            let label = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if !pairs.contains(where: { $0.0 == href }) { pairs.append((href, label)) }
        }
        var n = 0
        for (href, label) in pairs {
            let low = href.lowercased()
            if low.contains("op=dotraining") || low.contains("op=cheer")
                || low.contains("op=drawreward") || low.contains("op=show")
            {
                continue
            }
            let want = label.contains("挑战") || label.localizedCaseInsensitiveContains("boss")
                || label.contains("掌门") || label.contains("会武")
                || low.contains("op=fight") || low.contains("boss")
            if !want && !label.isEmpty { continue }
            onLog("挑战后续：\(label.isEmpty ? String(href.split(separator: "op=").last ?? "") : label)")
            let (_, r) = await LedouCGI.getHref(href, cookie: cookie)
            n += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.prefer(r, "战胜", "惜败", "你干掉了", "已通关")
                .ifEmpty(CombatLog.fromBody(r))
            if !msg.isEmpty { onLog(msg) }
        }
        return n
    }

    // MARK: - 门派

    static func farmMenPai(
        cookie: String,
        opts: MenPaiOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog("门派挑战开始")
        if opts.xiangLu {
            let (_, incense) = await LedouCGI.getPhonePk(
                cmd: "sect", extra: ["op": "fumigatefreeincense"], cookie: cookie
            )
            onLog(CombatLog.prefer(incense, "香炉", "点燃").ifEmpty("普通香炉已处理"))
            try? await Task.sleep(nanoseconds: gapNs)
        }
        if opts.xiangLuGao || opts.xiangLuGaoHuan {
            if opts.xiangLuGaoHuan {
                let (_, swap) = await LedouCGI.getPhonePk(
                    cmd: "sect", extra: ["op": "exchangeincense"], cookie: cookie
                )
                onLog(CombatLog.fromBody(swap).ifEmpty("换高香"))
                try? await Task.sleep(nanoseconds: gapNs)
            }
            if opts.xiangLuGao {
                let (_, gao) = await LedouCGI.getPhonePk(
                    cmd: "sect", extra: ["op": "fumigatepaidincense"], cookie: cookie
                )
                onLog(CombatLog.prefer(gao, "香炉", "点燃", "高").ifEmpty("高级香炉已处理"))
                try? await Task.sleep(nanoseconds: gapNs)
            }
        }

        if opts.muZhuang {
            var left = maxMenPai
            while left > 0 {
                left -= 1
                if Task.isCancelled { break }
                let (_, page) = await LedouCGI.getPhonePk(cmd: "sect", cookie: cookie)
                try? await Task.sleep(nanoseconds: gapNs)
                let muzhuangLine = CombatLog.brLine(page, "进入木桩训练")
                if muzhuangLine.contains("挑战次数已用尽") {
                    onLog("木桩挑战次数已用尽")
                    break
                }
                let (_, r) = await LedouCGI.getPhonePk(
                    cmd: "sect", extra: ["op": "trainingwithnpc"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let line = CombatLog.prefer(r, "你干掉了", "战胜", "木桩").ifEmpty(CombatLog.fromBody(r))
                onLog(line.ifEmpty("木桩训练"))
                if r.contains("次数已用尽") || r.contains("用完") || muzhuangLine.contains("挑战次数已用尽") {
                    onLog("木桩挑战次数已用尽")
                    break
                }
            }
        }

        if opts.qieCuo1 || opts.qieCuo2 || opts.qieCuoHuan {
            var freeOn = opts.qieCuo1 || opts.qieCuo2
            var payOn = opts.qieCuo1 || opts.qieCuo2
            var bookSwapped = false
            var rounds = 0
            var payAnnounced = false
            while rounds < maxMenPai && (freeOn || payOn) {
                rounds += 1
                if Task.isCancelled { break }
                let (_, page) = await LedouCGI.getPhonePk(cmd: "sect", cookie: cookie)
                try? await Task.sleep(nanoseconds: gapNs)
                if page.contains("系统繁忙") && page.contains("使用规则") {
                    try? await Task.sleep(nanoseconds: gapNs)
                    continue
                }
                let qie = CombatLog.brLine(page, "进入同门切磋")
                if freeOn {
                    if qie.contains("免费挑战") {
                        let (_, r) = await LedouCGI.getPhonePk(
                            cmd: "sect", extra: ["op": "trainingwithmember"], cookie: cookie
                        )
                        try? await Task.sleep(nanoseconds: gapNs)
                        let line = CombatLog.prefer(r, "你干掉了", "战胜", "切磋", "同门")
                            .ifEmpty(CombatLog.fromBody(r))
                        onLog(line.ifEmpty("同门切磋(免费)"))
                        continue
                    }
                    freeOn = false
                    onLog("同门切磋免费挑战次数已用尽")
                }
                if payOn {
                    if !payAnnounced {
                        payAnnounced = true
                        onLog("开始同门切磋(耗战书打满)")
                    }
                    if qie.contains("挑战次数已用尽") {
                        payOn = false
                        onLog("同门切磋付费挑战次数已用尽（已达挑战上限）")
                        break
                    }
                    let (_, r) = await LedouCGI.getPhonePk(
                        cmd: "sect", extra: ["op": "trainingwithmember"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let line = CombatLog.prefer(r, "你干掉了", "战胜", "切磋", "同门", "战书")
                        .ifEmpty(CombatLog.fromBody(r))
                    if r.contains("门派战书数量不足") || r.contains("门派战书不足")
                        || line.contains("门派战书数量不足") || line.contains("门派战书不足")
                    {
                        if opts.qieCuoHuan && !bookSwapped {
                            bookSwapped = true
                            let (_, ex) = await LedouCGI.getPhonePk(
                                cmd: "exchange",
                                extra: ["subtype": "2", "type": "1249", "times": "1", "costtype": "11"],
                                cookie: cookie
                            )
                            try? await Task.sleep(nanoseconds: gapNs)
                            onLog(CombatLog.fromBody(ex).ifEmpty("兑换门派战书已请求"))
                            continue
                        }
                        payOn = false
                        onLog("门派战书数量不足")
                        break
                    }
                    if r.contains("挑战次数已用尽") || r.contains("已达最大挑战上限")
                        || line.contains("挑战次数已用尽")
                    {
                        payOn = false
                        onLog("同门切磋付费挑战次数已用尽（已达挑战上限）")
                        break
                    }
                    onLog(line.ifEmpty("同门切磋(战书)"))
                }
            }
        }

        if opts.muZhuang || opts.qieCuo1 || opts.qieCuo2 || opts.qieCuoBoss {
            for (rank, pos) in [(1, 1), (2, 1), (3, 1)] {
                let (_, r) = await LedouCGI.getPhonePk(
                    cmd: "sect",
                    extra: ["op": "trainingwithcouncil", "rank": "\(rank)", "pos": "\(pos)"],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(r).ifEmpty("长老切磋 rank=\(rank)"))
                if r.contains("次数已用尽") || r.contains("用完") { break }
            }
        }

        if opts.qieCuoBoss {
            let (_, r) = await LedouCGI.getPhonePk(
                cmd: "sect", extra: ["op": "trainingwithboss"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog(CombatLog.fromBody(r).ifEmpty("门派Boss切磋"))
        }

        if opts.yaoQingSai {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let w = cal.component(.weekday, from: Date())
            let mon1 = w == 1 ? 7 : w - 1
            if opts.yaoQingSaiSkipSun && mon1 == 7 {
                onLog("周日不打邀请赛（已勾选）")
            } else {
                var left = opts.yaoQingSaiMan ? maxMenPai : 1
                while left > 0 {
                    left -= 1
                    let (_, r) = await LedouCGI.getPhonePk(
                        cmd: "secttournament", extra: ["op": "fight"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(r).ifEmpty("邀请赛"))
                    if (r.contains("次数") && (r.contains("用尽") || r.contains("不足")))
                        || r.contains("明天") || r.contains("无法")
                    {
                        break
                    }
                }
            }
        }

        onLog("门派挑战结束")
        return "门派代玩完成"
    }
}

private extension String {
    func ifEmpty(_ alt: @autoclosure () -> String) -> String {
        isEmpty ? alt() : self
    }
}
