import Foundation

/// 真源：`HuoYueCombat.kt` — 活跃涨分战斗循环（历练/画卷/幻境/深渊）。
enum HuoYueCombat {
    private static let maxLilian = 120
    private static let maxHuaJuan = 20
    private static let maxHuanJing = 40
    private static let maxAbyss = 40
    private static let gapNs: UInt64 = 80_000_000
    private static let gapSkipNs: UInt64 = 20_000_000

    private static let lilianDiyDefault = [
        20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2,
    ]

    struct LilianOpts {
        var tianFu = false
        var xiaoBao = false
        var tianShu = false
        var diy = false
        var autoHuoli = false
        var daHuoli = false
        var xiaoHuoli = false

        static func fromStore() -> LilianOpts {
            let t = FeatureToggleStore.shared
            let fid = "daiwan"
            let tianFu = t.getBool(fid, "rg_lilian_tianfu", default: false)
            let tianShu = t.getBool(fid, "rg_lilian_tianshu", default: false)
            let diy = t.getBool(fid, "rg_lilian_diy", default: false)
            return LilianOpts(
                tianFu: tianFu && !diy,
                xiaoBao: t.getBool(fid, "cb_lilian_xiaobao", default: false),
                tianShu: tianShu && !diy && !tianFu,
                diy: diy,
                autoHuoli: t.getBool(fid, "cb_lilian_auto", default: false),
                daHuoli: t.getBool(fid, "rg_lilian_da", default: false),
                xiaoHuoli: t.getBool(fid, "rg_lilian_xiao", default: false)
            )
        }
    }

    struct HuaJuanOpts {
        var payOk = false
        static func fromStore() -> HuaJuanOpts {
            let t = FeatureToggleStore.shared
            let pay = t.getBool("daiwan", "cb_huajuan_fufei", default: false)
            let freeOnly = t.getBool("daiwan", "cb_huajuan_mianfei", default: false)
            return HuaJuanOpts(payOk: pay && !freeOnly)
        }
    }

    struct HuanJingOpts {
        var secondLast = false
        static func fromStore() -> HuanJingOpts {
            HuanJingOpts(secondLast: FeatureToggleStore.shared.getBool("daiwan", "rb_huanjing_dao2", default: false))
        }
    }

    struct ShenYuanOpts {
        var payAdd = false
        var factionGift = false
        var revive = false
        var reviveSweep = false
        var abyssId = 1
        static func fromStore() -> ShenYuanOpts {
            let t = FeatureToggleStore.shared
            let fid = "more_settings"
            let id = Int(t.getString(fid, "ed_symj_id").trimmingCharacters(in: .whitespaces)) ?? 1
            return ShenYuanOpts(
                payAdd: t.getBool(fid, "cb_symj_add", default: false),
                factionGift: t.getBool(fid, "cb_symj_xl", default: false),
                revive: t.getBool(fid, "cb_symj_fh", default: false),
                reviveSweep: t.getBool(fid, "cb_symj_fh_sd", default: false),
                abyssId: max(1, id)
            )
        }
    }

    // MARK: - 历练

    static func farmLilian(
        cookie: String,
        reverse: Bool = false,
        opts: LilianOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        var effective = opts
        if reverse && !opts.diy {
            effective.tianFu = !opts.tianFu
            effective.tianShu = !opts.tianShu
        }
        let mode: String = {
            if effective.diy { return "自定义顺序" }
            if effective.tianFu && effective.xiaoBao { return "天赋丹·小宝" }
            if effective.tianFu { return "优先天赋丹" }
            if effective.tianShu { return "优先阅历" }
            return "默认阅历图"
        }()
        onLog(reverse ? "反向历练挑战开始（\(mode)）" : "历练挑战开始（\(mode)）")
        await ensureLilianAutoHuoli(cookie: cookie, wantOn: effective.autoHuoli, onLog: onLog)

        var diyList = effective.diy
            ? (reverse ? Array(lilianDiyDefault.reversed()) : lilianDiyDefault)
            : [Int]()
        var diyIndex = 0
        var mapid: Int
        var isTo = false
        if effective.diy {
            mapid = diyList.first ?? -1
        } else if effective.tianFu {
            mapid = effective.xiaoBao ? 6 : 10
        } else {
            mapid = 20
        }

        var fights = 0
        var kills = 0
        var drankDa = false
        var drankXiao = false

        func advanceMap() {
            if effective.diy {
                if mapid > 10 {
                    if !isTo { isTo = true; return }
                    isTo = false
                    diyIndex += 1
                    mapid = diyIndex < diyList.count ? diyList[diyIndex] : -1
                } else {
                    diyIndex += 1
                    mapid = diyIndex < diyList.count ? diyList[diyIndex] : -1
                }
                return
            }
            let next = setNextMapId(mapid, isTo: isTo)
            mapid = next.0
            isTo = next.1
        }

        while fights < maxLilian && mapid != -1 {
            if Task.isCancelled { break }
            let baseNpc = mapid * 20 + 5994
            let npcid = (mapid > 10 && isTo) ? baseNpc - 1 : baseNpc
            let (_, r) = await LedouCGI.getPhonePk(
                cmd: "mappush",
                extra: [
                    "subtype": "3",
                    "mapid": "\(mapid)",
                    "npcid": "\(npcid)",
                    "pageid": "2",
                ],
                cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)

            if !CombatLog.brLine(r, "系统繁忙").isEmpty {
                onLog("系统繁忙")
                try? await Task.sleep(nanoseconds: gapNs)
                continue
            }
            let kill = CombatLog.brLine(r, "你干掉了")
            if !kill.isEmpty {
                kills += 1
                onLog(kill)
                continue
            }
            if r.contains("请明天再来") || r.contains("挑战次数已经达到上限") {
                let t = CombatLog.brLine(r, "请明天再来挑战吧")
                    .ifEmpty(CombatLog.brLine(r, "挑战次数已经达到上限"))
                onLog(t.ifEmpty(CombatLog.fromBody(r)))
                advanceMap()
                try? await Task.sleep(nanoseconds: gapSkipNs)
                continue
            }
            if r.contains("活力不足") || r.contains("请好好休息") {
                let rest = CombatLog.brLine(r, "请好好休息后")
                    .ifEmpty(CombatLog.brLine(r, "好好休息"))
                    .ifEmpty(CombatLog.brLine(r, "活力不足"))
                onLog(rest.ifEmpty(CombatLog.fromBody(r)))
                if effective.autoHuoli { break }
                if effective.daHuoli && !drankDa {
                    drankDa = true
                    let (_, use) = await LedouCGI.getPhonePk(
                        cmd: "use", extra: ["id": "3105", "store_type": "1"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let used = CombatLog.brLine(use, "您使用了")
                    if !used.isEmpty { onLog(used); continue }
                    if use.contains("使用失败") || use.contains("不够") {
                        onLog("大活力不够了，好好休息"); break
                    }
                    if use.contains("该物品今天已经不能再使用了") || use.contains("每日上限") {
                        onLog("该物品今天已经不能再使用了"); break
                    }
                    onLog(CombatLog.fromBody(use).ifEmpty("大活力使用结果未知"))
                    continue
                }
                if effective.xiaoHuoli && !drankXiao {
                    drankXiao = true
                    let (_, use) = await LedouCGI.getPhonePk(
                        cmd: "use", extra: ["id": "3386", "store_type": "1"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let used = CombatLog.brLine(use, "您使用了")
                    if !used.isEmpty { onLog(used); continue }
                    if use.contains("使用失败") || use.contains("不够") {
                        onLog("小活力不够了，好好休息"); break
                    }
                    if use.contains("该物品今天已经不能再使用了") || use.contains("每日上限") {
                        onLog("该物品今天已经不能再使用了"); break
                    }
                    onLog(CombatLog.fromBody(use).ifEmpty("小活力使用结果未知"))
                    continue
                }
                break
            }
            if r.contains("每日上限") {
                onLog("很抱歉，活力药水使用次数已达到每日上限")
                break
            }
            let noScene = CombatLog.brLine(r, "还没有打到该历练场景")
            if !noScene.isEmpty {
                onLog(noScene)
                advanceMap()
                try? await Task.sleep(nanoseconds: gapSkipNs)
                continue
            }
            let cant = CombatLog.brLine(r, "不能挑战")
            if !cant.isEmpty {
                onLog(cant)
                advanceMap()
                try? await Task.sleep(nanoseconds: gapSkipNs)
                continue
            }
            let hint = CombatLog.fromBody(r).ifEmpty("无有效回文(map=\(mapid) npc=\(npcid))")
            onLog(hint)
            if kills == 0 && fights % 5 == 0 {
                advanceMap()
                try? await Task.sleep(nanoseconds: gapSkipNs)
            }
        }
        onLog("历练结束")
        return "战斗\(fights)次/击杀约\(kills)"
    }

    private static func setNextMapId(_ mapid: Int, isTo: Bool) -> (Int, Bool) {
        if mapid <= 10 && mapid > 2 { return (mapid - 1, false) }
        if mapid == 2 { return (-1, false) }
        if mapid > 10 {
            return isTo ? (mapid - 1, false) : (mapid, true)
        }
        return (-1, false)
    }

    private static func ensureLilianAutoHuoli(
        cookie: String, wantOn: Bool, onLog: @escaping (String) -> Void
    ) async {
        let (_, page) = await LedouCGI.getPhonePk(cmd: "view", extra: ["type": "6"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let needToggle: Bool = {
            if wantOn && page.contains("开启自动使用活力药水") { return true }
            if !wantOn && page.contains("取消自动使用活力药水") { return true }
            return false
        }()
        if !needToggle {
            if wantOn {
                onLog(page.contains("取消自动使用活力药水")
                    ? "已开启自动使用活力药水" : "活力自动开关页无匹配文案，继续")
            } else {
                onLog(page.contains("开启自动使用活力药水")
                    ? "已关闭自动使用活力药水" : "活力自动已关")
            }
            return
        }
        let (_, r) = await LedouCGI.getPhonePk(cmd: "set", extra: ["type": "11"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        if r.contains("取消自动使用活力药水") || (wantOn && !r.contains("开启自动使用活力药水")) {
            onLog("已开启自动使用活力药水")
        } else if r.contains("开启自动使用活力药水") || !wantOn {
            onLog("已取消自动使用活力药水")
        } else {
            onLog(CombatLog.fromBody(r).ifEmpty("活力自动切换完成"))
        }
    }

    // MARK: - 画卷

    static func farmHuaJuan(
        cookie: String,
        opts: HuaJuanOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog(opts.payOk ? "画卷挑战开始（含付费）" : "画卷挑战开始（仅免费）")
        var fights = 0
        var usedPay = false
        while fights < maxHuaJuan {
            if Task.isCancelled { break }
            let (_, q) = await LedouCGI.getPetPk(cmd: "scroll_dungeon", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            let qMsg = CombatLog.fromBody(q)
            if q.contains("明天再来") || q.contains("征战书不足") || q.contains("没有挑战次数") {
                if opts.payOk && !usedPay && (q.contains("没有挑战次数") || q.contains("征战书不足")) {
                    usedPay = true
                    onLog("免费次数用尽，尝试付费挑战")
                    let (_, fPay) = await LedouCGI.getPetPk(
                        cmd: "scroll_dungeon",
                        extra: ["op": "fight", "buff": "1"],
                        cookie: cookie
                    )
                    fights += 1
                    try? await Task.sleep(nanoseconds: gapNs)
                    let line = CombatLog.prefer(fPay, "你干掉了", "战胜").ifEmpty(CombatLog.fromBody(fPay))
                    onLog(line.ifEmpty("画卷付费战\(fights)"))
                    if fPay.contains("明天再来") || fPay.contains("没有挑战次数")
                        || fPay.contains("征战书不足") || fPay.contains("斗豆不足")
                    {
                        onLog(CombatLog.fromBody(fPay).ifEmpty("付费不可用，结束"))
                        break
                    }
                    continue
                }
                onLog(qMsg.ifEmpty("明天再来吧"))
                break
            }
            let (_, f) = await LedouCGI.getPetPk(
                cmd: "scroll_dungeon",
                extra: ["op": "fight", "buff": "0"],
                cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let line = CombatLog.prefer(f, "你干掉了", "战胜").ifEmpty(CombatLog.fromBody(f))
            onLog(line.ifEmpty("画卷战斗\(fights)"))
            if f.contains("明天再来") || f.contains("没有挑战次数") || f.contains("征战书不足") {
                if opts.payOk && !usedPay {
                    usedPay = true
                    onLog("免费次数用尽，尝试付费挑战")
                    continue
                }
                break
            }
        }
        return "画卷战斗\(fights)次"
    }

    // MARK: - 幻境

    static func farmHuanJing(
        cookie: String,
        opts: HuanJingOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        func query() async -> String {
            let (_, b) = await LedouCGI.getPetPk(cmd: "misty", cookie: cookie)
            return b
        }

        func stagePick(_ raw: String) -> Int {
            var s = CombatLog.jsonInt(raw, "stage_num") ?? 1
            if s <= 0 { s = 1 }
            if opts.secondLast {
                if s != 1 { s -= 1 }
            } else if s == 21 {
                s = 20
            }
            return s
        }

        func claimBoxes(_ raw: String, forceAll: Bool = false) async -> Int {
            var ids = Set<Int>()
            let html = raw.replacingOccurrences(of: "&amp;", with: "&")
            let re = try? NSRegularExpression(
                pattern: #"cmd=misty[^"'\s>]*op=reward[^"'\s>]*box_id=(\d+)"#,
                options: .caseInsensitive
            )
            let ns = html as NSString
            re?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 2 else { return }
                let id = Int(ns.substring(with: m.range(at: 1))) ?? 0
                if id > 0 { ids.insert(id) }
            }
            if ids.isEmpty || forceAll {
                let stars = CombatLog.jsonInt(raw, "star_num") ?? -1
                if forceAll || stars < 0 {
                    ids.formUnion([1, 2, 3])
                } else if stars >= 15 {
                    ids.formUnion([1, 2, 3])
                } else if stars >= 10 {
                    ids.formUnion([1, 2])
                } else if stars >= 6 {
                    ids.insert(1)
                } else {
                    ids.formUnion([1, 2, 3])
                }
            }
            var claimed = 0
            for id in ids.filter({ (1...3).contains($0) }).sorted() {
                let (_, r) = await LedouCGI.getPhonePk(
                    cmd: "misty",
                    extra: ["op": "reward", "box_id": "\(id)"],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let msg = CombatLog.fromBody(r)
                if msg.contains("不能领取") || msg.contains("已领取") || msg.contains("非法")
                    || msg.contains("不存在") || msg.contains("错误")
                {
                    continue
                }
                if !msg.isEmpty {
                    onLog("领宝箱\(id)：\(msg)")
                    claimed += 1
                } else if r.contains("获得") || r.contains("幻境积分") || r.contains("领取") {
                    onLog("领宝箱\(id)：成功")
                    claimed += 1
                }
            }
            return claimed
        }

        func doReturn() async -> Bool {
            var ok = false
            let (_, phone) = await LedouCGI.getPhonePk(
                cmd: "misty", extra: ["op": "return"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let pm = CombatLog.fromBody(phone)
            if !pm.isEmpty { onLog("返回(phone)：\(pm)") }
            if !pm.contains("未结束") && !pm.contains("非法") && !phone.isEmpty { ok = true }
            let (_, pet) = await LedouCGI.getPetPk(
                cmd: "misty", extra: ["op": "return"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let m = CombatLog.fromBody(pet)
            if !m.isEmpty { onLog("返回(pet)：\(m)") }
            if !m.contains("未结束") && !m.contains("非法") && !pet.isEmpty { ok = true }
            return ok
        }

        func tryClaimPending(_ reason: String) async -> Bool {
            onLog(reason)
            var cleared = false
            let pet = await query()
            try? await Task.sleep(nanoseconds: gapNs)
            if await claimBoxes(pet, forceAll: true) > 0 { cleared = true }
            let (_, html) = await LedouCGI.getPhonePk(cmd: "misty", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            if await claimBoxes(html, forceAll: true) > 0 { cleared = true }
            if await doReturn() { cleared = true }
            let after = await query()
            try? await Task.sleep(nanoseconds: gapNs)
            if !after.contains("请重新开始挑战") && !after.contains("副本未结束") {
                cleared = true
            }
            return cleared
        }

        var q = await query()
        try? await Task.sleep(nanoseconds: gapNs)
        let stage = stagePick(q)
        onLog("幻境挑战开始（关卡\(stage)\(opts.secondLast ? "·倒数第二" : "·最后")）")

        func snap(_ raw: String) -> (Int, Int, String) {
            let cur = CombatLog.jsonInt(raw, "cur_stage") ?? 0
            let can = CombatLog.jsonInt(raw, "can_return") ?? 0
            let times = CombatLog.jsonField(raw, "challenge_times") ?? ""
            let msg = CombatLog.fromBody(raw)
            let result = CombatLog.jsonInt(raw, "result") ?? 0
            onLog("查询 result=\(result) cur=\(cur) return=\(can) 次数=\(times)\(msg.isEmpty ? "" : " \(msg)")")
            return (cur, can, times)
        }
        _ = snap(q)

        var fights = 0
        var needClaimTried = false
        var resumeTried = false
        var idleLoops = 0
        while fights < maxHuanJing && idleLoops < 8 {
            if Task.isCancelled { break }
            q = await query()
            try? await Task.sleep(nanoseconds: gapNs)
            let (cur, canReturn, times) = snap(q)
            let result = CombatLog.jsonInt(q, "result") ?? 0
            let qMsg = CombatLog.fromBody(q)
            if result != 0 {
                onLog(qMsg.ifEmpty("幻境查询失败"))
                if qMsg.contains("系统繁忙") { idleLoops += 1; continue }
                break
            }
            if canReturn != 0 {
                _ = await claimBoxes(q)
                _ = await doReturn()
                idleLoops = 0
                continue
            }
            if cur > 0 {
                idleLoops = 0
                let (_, f) = await LedouCGI.getPetPk(
                    cmd: "misty", extra: ["op": "fight"], cookie: cookie
                )
                fights += 1
                try? await Task.sleep(nanoseconds: gapNs)
                let line = CombatLog.prefer(f, "你干掉了").ifEmpty(CombatLog.fromBody(f))
                if !line.isEmpty { onLog(line) }
                if f.contains("请重新开始挑战") || line.contains("请重新开始挑战") {
                    if needClaimTried {
                        onLog("仍需领奖：自动领失败，请先在游戏内点宝箱领奖，再点幻境")
                        return "需手动领奖"
                    }
                    needClaimTried = true
                    if !(await tryClaimPending("战斗提示重新开始，phone 领宝箱/返回")) {
                        onLog("自动领奖失败：请先在游戏内领取上场奖励，再点幻境")
                        return "需手动领奖"
                    }
                    needClaimTried = false
                } else if f.contains("次数已用完") || f.contains("没有挑战次数") || line.contains("次数已用完") {
                    onLog("幻境次数用尽")
                    return "幻境战斗\(fights)次"
                } else if f.contains("明天") {
                    onLog(line.ifEmpty("今日不可再挑战"))
                    return "幻境战斗\(fights)次"
                } else {
                    let after = await query()
                    try? await Task.sleep(nanoseconds: gapNs)
                    _ = await claimBoxes(after)
                }
                continue
            }

            let leftParsed: Int? = {
                guard let re = try? NSRegularExpression(pattern: #"(\d+)\s*/\s*(\d+)"#),
                      let m = re.firstMatch(in: times, range: NSRange(times.startIndex..., in: times)),
                      let r = Range(m.range(at: 1), in: times)
                else { return nil }
                return Int(times[r])
            }()
            if let left = leftParsed, left <= 0 {
                onLog("幻境次数用尽（剩余\(times)）")
                break
            }
            if q.contains("请重新开始挑战") || q.contains("副本未结束") {
                if needClaimTried {
                    onLog("仍有未结束副本/待领奖：请先在游戏内处理，再点幻境（不是次数用尽）")
                    return "需手动领奖"
                }
                needClaimTried = true
                if !(await tryClaimPending("查询提示未结束/需重开，尝试领奖或返回")) {
                    if !resumeTried {
                        resumeTried = true
                        onLog("尝试续打未结束副本")
                        let (_, f) = await LedouCGI.getPetPk(
                            cmd: "misty", extra: ["op": "fight"], cookie: cookie
                        )
                        fights += 1
                        try? await Task.sleep(nanoseconds: gapNs)
                        let line = CombatLog.prefer(f, "你干掉了").ifEmpty(CombatLog.fromBody(f))
                        onLog(line.ifEmpty("续打已请求"))
                        if f.contains("请重新开始挑战") || line.contains("请重新开始挑战") {
                            onLog("续打仍需领奖：请先在游戏内点「领取奖励」")
                            return "需手动领奖"
                        }
                        needClaimTried = false
                        continue
                    }
                    onLog("自动处理失败：请先在游戏内结束/领取上场副本，再点幻境")
                    return "需手动领奖"
                }
                needClaimTried = false
                continue
            }

            let (_, start) = await LedouCGI.getPetPk(
                cmd: "misty",
                extra: ["op": "start", "stage_id": "\(stage)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let sm = CombatLog.fromBody(start)
            if sm.contains("未结束") || sm.contains("请重新开始挑战") || sm.contains("领取") {
                onLog("开局被拒：\(sm)")
                idleLoops += 1
                if needClaimTried && resumeTried {
                    onLog("仍有未结束副本：请先在游戏内领取或打完，再点幻境（不是次数用尽）")
                    return "需手动领奖"
                }
                if !needClaimTried {
                    needClaimTried = true
                    _ = await tryClaimPending("开局提示未结束，尝试领奖/返回")
                }
                if !resumeTried {
                    resumeTried = true
                    onLog("尝试续打未结束副本")
                    let (_, f) = await LedouCGI.getPetPk(
                        cmd: "misty", extra: ["op": "fight"], cookie: cookie
                    )
                    fights += 1
                    try? await Task.sleep(nanoseconds: gapNs)
                    let line = CombatLog.prefer(f, "你干掉了").ifEmpty(CombatLog.fromBody(f))
                    onLog(line.ifEmpty("续打已请求"))
                    if line.contains("请重新开始挑战") || f.contains("请重新开始挑战") {
                        onLog("续打仍需领奖：请先在游戏内点「领取奖励」")
                        return "需手动领奖"
                    }
                }
                continue
            }
            if sm.contains("次数") && (sm.contains("用尽") || sm.contains("用完") || sm.contains("不足")) {
                onLog(sm)
                break
            }
            idleLoops = 0
            resumeTried = false
            needClaimTried = false
            onLog("开始关卡\(stage)\(sm.isEmpty ? "" : "：\(sm)")")
        }
        if idleLoops >= 8 {
            onLog("开局空转过多，已停止（多半是上场副本未领奖/未结束）")
        }
        return "幻境战斗\(fights)次"
    }

    // MARK: - 深渊

    static func farmShenYuan(
        cookie: String,
        opts: ShenYuanOpts = .fromStore(),
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog("深渊秘境开始")
        var fights = 0
        var busy = 0
        let id = opts.abyssId
        if opts.factionGift {
            let (_, gift) = await LedouCGI.getPetPk(
                cmd: "abyss_tide", extra: ["op": "getfactiongift"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let gm = CombatLog.fromBody(gift)
            if !gm.isEmpty { onLog("巡礼:\(gm)") }
        }
        var (_, view) = await LedouCGI.getPetPk(
            cmd: "abyss_tide", extra: ["op": "viewallabyss"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        if let name = CombatLog.jsonField(view, "abyss_name"), !name.isEmpty {
            onLog("当前：\(name)")
        }
        var status = CombatLog.jsonInt(view, "status") ?? 0
        let fightStatus0 = CombatLog.jsonInt(view, "fight_status")
        var access = CombatLog.jsonInt(view, "access_time")
        if access == 0 || view.contains("暂无可用挑战次数") {
            if opts.payAdd {
                let canBuy = CombatLog.jsonInt(view, "can_buy_times") ?? 0
                if canBuy > 0 {
                    let (_, add) = await LedouCGI.getPetPk(
                        cmd: "abyss_tide", extra: ["op": "addaccess"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(add).ifEmpty("购买次数"))
                    (_, view) = await LedouCGI.getPetPk(
                        cmd: "abyss_tide", extra: ["op": "viewallabyss"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    access = CombatLog.jsonInt(view, "access_time")
                    status = CombatLog.jsonInt(view, "status") ?? 0
                }
            }
            if access == 0 || view.contains("暂无可用挑战次数") {
                onLog("暂无可用挑战次数")
                return "无次数"
            }
        }
        if status == 0 {
            let (_, enter) = await LedouCGI.getPetPk(
                cmd: "abyss_tide",
                extra: ["op": "enterabyss", "id": "\(id)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let em = CombatLog.fromBody(enter)
            if !em.isEmpty { onLog(em) }
            if enter.contains("暂无可用") || enter.contains("没有挑战")
                || ((enter.contains("次数") || enter.contains("挑战"))
                    && (enter.contains("不足") || enter.contains("用完") || enter.contains("暂无")))
            {
                onLog("无法进入深渊，结束")
                return "无法进入"
            }
        } else if status == 1 && fightStatus0 == 2 {
            if opts.revive {
                let (_, rev) = await LedouCGI.getPetPk(
                    cmd: "abyss_tide", extra: ["op": "revive"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(rev).ifEmpty("复活"))
                if opts.reviveSweep {
                    let (_, sw) = await LedouCGI.getPetPk(
                        cmd: "abyss_tide", extra: ["op": "sweep"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(sw).ifEmpty("扫荡"))
                }
            } else {
                onLog("战斗失败状态，退出结算")
                await endAbyss(cookie: cookie, onLog: onLog)
                return "深渊已结算"
            }
        }
        while fights < maxAbyss {
            if Task.isCancelled { break }
            let (_, f) = await LedouCGI.getPetPk(
                cmd: "abyss_tide", extra: ["op": "beginfight"], cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let line = CombatLog.fromBody(f)
            if !line.isEmpty && !line.contains("系统繁忙") { onLog(line) }
            if f.contains("系统繁忙") || line.contains("系统繁忙") {
                busy += 1
                if busy >= 3 {
                    onLog("系统繁忙次数过多，结束深渊")
                    break
                }
                try? await Task.sleep(nanoseconds: gapNs)
                continue
            }
            busy = 0
            let fs = CombatLog.jsonInt(f, "fight_status")
            if fs == 2 || line.contains("已通关该副本") || f.contains("已通关该副本")
                || line.contains("请退出副本") || f.contains("请退出副本")
            {
                if fs == 2 && opts.revive && !line.contains("已通关") {
                    let (_, rev) = await LedouCGI.getPetPk(
                        cmd: "abyss_tide", extra: ["op": "revive"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(rev).ifEmpty("复活"))
                    if opts.reviveSweep {
                        let (_, sw) = await LedouCGI.getPetPk(
                            cmd: "abyss_tide", extra: ["op": "sweep"], cookie: cookie
                        )
                        try? await Task.sleep(nanoseconds: gapNs)
                        onLog(CombatLog.fromBody(sw).ifEmpty("扫荡"))
                        if CombatLog.jsonInt(sw, "fight_status") == 1 { continue }
                    } else {
                        continue
                    }
                }
                await endAbyss(cookie: cookie, onLog: onLog)
                break
            }
            if line.contains("暂无可用") || line.contains("没有挑战")
                || (line.contains("次数") && (line.contains("不足") || line.contains("用完")))
                || line.contains("明天") || line.contains("无法挑战")
            {
                onLog(line.ifEmpty("次数不足"))
                break
            }
            if line.isEmpty && f.contains("\"result\":\"-1\"") {
                onLog("深渊请求失败，结束")
                break
            }
        }
        onLog("深渊秘境结束")
        return "深渊战斗\(fights)次"
    }

    private static func endAbyss(cookie: String, onLog: @escaping (String) -> Void) async {
        let (_, end) = await LedouCGI.getPetPk(
            cmd: "abyss_tide", extra: ["op": "endabyss"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        onLog(CombatLog.fromBody(end).ifEmpty("退出副本结算"))
    }
}

private extension String {
    func ifEmpty(_ alt: @autoclosure () -> String) -> String {
        isEmpty ? alt() : self
    }
}
