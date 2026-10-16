import Foundation

/// 真源：`SettingsWorkers.RenWuWorker` + `farmRiChang` / `farmBangPaiTask` / `farmMenPaiTask` / `farmCargo`。
enum RenWuActions {
    static let fid = "renwu"
    private static let gapNs: UInt64 = 80_000_000
    private static let phoneBase =
        "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?zapp_uin=&sid=&channel=0&g_ut=1&"

    private static let xlIds = [
        "2722", "2752", "2495", "2526", "2439", "2437", "2369", "2395", "2461",
    ]
    private static let gfIds = [
        "3043", "3089", "3028", "3923", "3036", "3014", "6024",
        "5878", "3871", "3636", "1567", "3144", "6023",
    ]

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let s = RenWuStore.shared
        var parts: [String] = []

        let doRc = s.on("cb_rw_rc") || s.on("cb_rc") || s.on("daily")
            || s.on("cb_renwu_bingfa") || s.on("cb_renwu_shenzhuang")
            || s.on("cb_renwu_shenzhuang_ji_neng") || s.on("cb_renwu_zhuanjing")
            || s.on("cb_renwu_zhuanjing_wuqi") || s.on("cb_renwu_mingke")
            || s.on("cb_renwu_huizhang")
        if doRc {
            let msg = await farmRiChang(cookie: cookie, onLog: onLog)
            parts.append("日常:\(msg)")
        }

        let doMp = s.on("cb_rw_mp") || s.on("cb_mp") || s.on("sect")
            || s.on("cb_menpai_shuaxin") || s.on("rb_mp_xf_jc") || s.on("rb_mp_xf_sc")
            || s.on("rb_mp_sl")
        if doMp {
            let msg = await farmMenPaiTask(cookie: cookie, onLog: onLog)
            parts.append("门派:\(msg)")
        }

        let doBp = s.on("cb_rw_bp") || s.on("cb_bp") || s.on("faction")
            || s.on("rg_bp_xl_1") || s.on("rg_bp_gf_1")
        if doBp {
            let msg = await farmBangPaiTask(cookie: cookie, onLog: onLog)
            parts.append("帮派:\(msg)")
        }

        if s.on("cb_youji_1") || s.on("cb_youji_2") || s.on("cb_youji_3") {
            let msg = await MoreExtraActions.farmYouJi(cookie: cookie, onLog: onLog)
            parts.append("游记:\(msg)")
        }

        if s.on("cb_hy_yb_1", default: true) || s.on("cb_hy_yb_2", default: true)
            || s.on("cb_hy_yb_3") || s.on("cb_hy_yb_s")
        {
            let msg = await farmCargo(cookie: cookie, onLog: onLog)
            parts.append("押镖:\(msg)")
        }

        let tip = parts.isEmpty ? "未开启子项（请在任务设置勾选）" : parts.joined(separator: " | ")
        onLog(tip)
        return tip
    }

    // MARK: - 日常

    static func farmRiChang(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog("日常任务开始")
        var page = ""
        for _ in 0..<2 {
            let (_, b) = await LedouCGI.getPhonePk(
                cmd: "task", extra: ["sub": "7"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            page = b
            if !(b.contains("系统繁忙") && b.contains("使用规则")) { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        var msg = CombatLog.prefer(page, "完成任务", "获得", "一键完成", "已完成")
        if msg.isEmpty { msg = CombatLog.fromBody(page) }
        if !msg.isEmpty { onLog(String(msg.prefix(100))) }

        if let claim = firstGroup(#"href="([^"]+)"[^>]*>\s*领取奖励"#, in: page) {
            let (_, r) = await LedouCGI.getHref(claim, cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            onLog(CombatLog.fromBody(r).ifBlankMe("领取奖励"))
            let (_, again) = await LedouCGI.getPhonePk(
                cmd: "task", extra: ["sub": "7"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            page = again
        }
        let tip = CombatLog.fromBody(page).ifBlankMe("日常已请求一键完成")
        onLog(tip)
        return tip
    }

    // MARK: - 帮派

    static func farmBangPaiTask(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        var tried = Set<String>()
        var rounds = 0
        var claimFails = 0
        while rounds < 10 {
            if Task.isCancelled { break }
            rounds += 1
            let (_, page) = await LedouCGI.getPhonePk(
                cmd: "factiontask", extra: ["sub": "1"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if page.contains("系统繁忙"), page.contains("使用规则") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            if let claim = extractClaim(page) {
                let (_, r) = await LedouCGI.getHref(claim, cookie: cookie)
                try? await Task.sleep(nanoseconds: gapNs)
                let msg = CombatLog.fromBody(r)
                onLog(msg.isEmpty ? "领取帮派任务奖励" : msg)
                if r.contains("领取奖励"), r.contains("任务介绍"), !r.contains("已领奖") {
                    claimFails += 1
                    if claimFails >= 2 {
                        onLog("领取奖励无效果，结束（请手动领）")
                        break
                    }
                } else {
                    claimFails = 0
                }
                continue
            }

            let lines = (1...3).compactMap { lineOf(page, n: $0) }.filter { !$0.isEmpty }
            guard let target = lines.first(where: { !$0.contains("已领奖") }) else {
                onLog(page.contains("未完成")
                      ? "帮派任务仍有未完成（已尝试入口），结束"
                      : "帮派任务已完成")
                break
            }

            if let claim = extractClaim(target) {
                let (_, r) = await LedouCGI.getHref(claim, cookie: cookie)
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(r).ifBlankMe("领取帮派任务奖励"))
                continue
            }

            func unfinished(_ name: String) -> Bool {
                let blob = target.contains(name) ? target : page
                guard let r = blob.range(of: name) else { return false }
                let slice = String(blob[r.lowerBound...].prefix(80))
                return (slice.contains("未完成") || target.contains(name))
                    && !slice.contains("已领奖") && !slice.contains("领取奖励")
            }

            let next: (String, String)? = {
                if unfinished("加速贡献"), !tried.contains("加速贡献") {
                    return ("加速贡献", phoneBase + "cmd=use&id=3038&store_type=1&page=2")
                }
                if unfinished("帮战冠军"), !tried.contains("帮战冠军") {
                    return ("帮战冠军", phoneBase + "cmd=facwar&sub=0&id=1")
                }
                if unfinished("查看帮战"), !tried.contains("帮战") {
                    return ("帮战", phoneBase + "cmd=facwar&sub=0&id=1")
                }
                if unfinished("查看帮贡"), !tried.contains("帮贡") {
                    return ("帮贡", phoneBase + "cmd=factionhr&subtype=14")
                }
                if unfinished("查看要闻"), !tried.contains("要闻") {
                    return ("要闻", phoneBase + "cmd=factionop&subtype=8&pageno=1&type=2")
                }
                if unfinished("查看矿洞"), !tried.contains("矿洞") {
                    return ("矿洞", "https://fight.pet.qq.com/cgi-bin/petpk?cmd=factionmine")
                }
                if unfinished("帮派修炼"), !tried.contains("修炼") {
                    return ("修炼", bangPaiXlUrl())
                }
                if unfinished("粮草掠夺"), !tried.contains("粮草") {
                    return ("粮草", phoneBase + "cmd=forage_war")
                }
                if unfinished("帮派供奉"), !tried.contains("供奉") {
                    return ("供奉", bangPaiGfUrl())
                }
                return nil
            }()

            guard let next else {
                if page.contains("领取奖励") || target.contains("领取奖励") {
                    onLog("有领取奖励但未解析到链接，结束")
                } else {
                    onLog("帮派任务仍有未完成（已尝试入口），结束")
                }
                break
            }
            tried.insert(next.0)
            let (_, r) = await LedouCGI.getHref(next.1, cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("\(next.0)：\(CombatLog.fromBody(r).ifBlankMe("已请求"))")
        }
        return "帮派轮次\(rounds)"
    }

    // MARK: - 门派

    static func farmMenPaiTask(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        onLog("门派任务开始")
        var abandoned = Set<String>()
        var refreshed = Set<String>()
        var actionTried: [String: Int] = [:]
        var rounds = 0

        while rounds < 16 {
            if Task.isCancelled { break }
            rounds += 1
            let (_, page) = await LedouCGI.getPhonePk(cmd: "sect_task", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            if page.isEmpty || page.contains("404") {
                onLog("门派任务页异常，结束")
                break
            }
            if page.contains("系统繁忙"), page.contains("使用规则") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            let slots = parseMenPaiSlots(page)
            if slots.isEmpty {
                onLog("未能解析任务1/2/3，结束")
                break
            }
            if rounds == 1 {
                onLog(slots.map { "\($0.name)(\($0.done ? "已完成" : "未完成"))" }.joined(separator: "；"))
            }
            if slots.allSatisfy(\.done) {
                onLog("门派任务全部已完成")
                break
            }

            guard let slot = slots.first(where: { !$0.done && !abandoned.contains($0.name) }) else {
                onLog("剩余任务无法自动完成")
                break
            }

            if let finish = firstGroup(#"href="([^"]+)"[^>]*>\s*完成(?!任务)"#, in: slot.actionLine)
                ?? firstGroup(#"href="([^"]+)"[^>]*>\s*完成(?!任务)"#, in: page)
            {
                let (_, r) = await LedouCGI.getHref(finish, cookie: cookie)
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("\(slot.name)完成：\(CombatLog.fromBody(r).ifBlankMe("已点完成"))")
                continue
            }

            let key = menPaiActKey(slot.desc) ?? "去做"
            let tryKey = "\(slot.name):\(key)"
            let n = (actionTried[tryKey] ?? 0) + 1
            actionTried[tryKey] = n

            let hard = ["掌门", "首座", "堂主", "切磋同门", "切磋外派", "木桩", "查看同门", "查看外派", "上香", "心法"]
            if hard.contains(key), n > 2 {
                if RenWuStore.shared.on("cb_menpai_shuaxin"), !refreshed.contains(slot.name),
                   let tid = firstGroup(#"task_id=(\d+)"#, in: slot.actionLine)
                    ?? firstGroup(#"task_id=(\d+)"#, in: slot.desc)
                {
                    refreshed.insert(slot.name)
                    _ = await LedouCGI.getHref(
                        phoneBase + "cmd=sect_task&subtype=1&task_id=\(tid)",
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog("\(slot.name)已刷新委托人")
                    actionTried.removeValue(forKey: tryKey)
                    continue
                }
                abandoned.insert(slot.name)
                onLog("\(slot.name)放弃，改做下一任务")
                continue
            }

            if let go = firstGroup(#"href="([^"]+)"[^>]*>\s*去做任务"#, in: slot.actionLine)
                ?? firstGroup(#"href="([^"]+)"[^>]*>\s*去做任务"#, in: page)
            {
                let (_, r) = await LedouCGI.getHref(go, cookie: cookie)
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("\(slot.name)\(key)：\(CombatLog.fromBody(r).ifBlankMe("已去做"))")
                continue
            }

            onLog("\(slot.name)\(key) 无可用目标")
            abandoned.insert(slot.name)
        }
        return "门派轮次\(rounds)"
    }

    // MARK: - 押镖

    static func farmCargo(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let s = RenWuStore.shared
        let wantW = s.on("cb_hy_yb_1", default: true)
        let wantL = s.on("cb_hy_yb_2", default: true)
        let wantC = s.on("cb_hy_yb_3")
        let payBoss = s.on("cb_hy_yb_s")
        if !wantW, !wantL, !wantC {
            let tip = "没有护送押镖设置，自动跳过"
            onLog(tip)
            return tip
        }
        var last = ""
        for _ in 0..<12 {
            if Task.isCancelled { break }
            var (_, page) = await LedouCGI.getPhonePk(
                cmd: "cargo", extra: ["op": "7"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if page.contains("使用规则"), page.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                (_, page) = await LedouCGI.getPhonePk(
                    cmd: "cargo", extra: ["op": "7"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
            }
            last = CombatLog.fromBody(page).ifBlankMe(last)
            if page.contains("今天没有护送次数") {
                onLog("今天没有护送次数了")
                return "次数用尽"
            }
            if page.contains("正在护送押镖中哦") || page.contains("正在护送中，不能刷新镖师") {
                if !page.contains("剩余护送次数：0"), page.contains("免费刷新次数：2") {
                    let (_, claim) = await LedouCGI.getPhonePk(
                        cmd: "cargo", extra: ["op": "16"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let msg = CombatLog.fromBody(claim).ifBlankMe("领取护送奖励")
                    onLog(msg)
                    return msg
                }
                onLog("正在护送中")
                return "正在护送"
            }
            let hasW = page.contains("当前镖师：温良恭")
            let hasL = page.contains("当前镖师：吕青橙")
            let hasC = page.contains("当前镖师：蔡八斗")
            let hasS = page.contains("当前镖师：盛秋月")
            let freeZero = page.contains("免费刷新次数：0")
            let noTimes = page.contains("押镖次数不足")
            let accept: Bool = {
                if wantW && !wantL { return hasW }
                if wantW && wantL { return hasW || hasL }
                if wantL { return hasL }
                if wantC { return hasC }
                return false
            }()
            if !freeZero, !noTimes {
                if accept {
                    let (_, r) = await LedouCGI.getPhonePk(
                        cmd: "cargo", extra: ["op": "6"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let msg = CombatLog.fromBody(r).ifBlankMe("开始护送")
                    onLog(msg)
                    return msg
                }
                let (_, r) = await LedouCGI.getPhonePk(
                    cmd: "cargo", extra: ["op": "8"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(r).ifBlankMe("刷新镖师"))
                continue
            }
            if payBoss, freeZero, !hasW, !hasS {
                if page.contains("斗豆不足") {
                    let tip = "无温良恭时，压盛秋月失败！斗豆不足！"
                    onLog(tip)
                    return tip
                }
                let (_, r) = await LedouCGI.getPhonePk(
                    cmd: "cargo", extra: ["op": "9"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(r).ifBlankMe("花豆压盛秋月"))
                continue
            }
            let (_, r) = await LedouCGI.getPhonePk(
                cmd: "cargo", extra: ["op": "6"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(r).ifBlankMe("开始护送")
            onLog(msg)
            return msg
        }
        return last.isEmpty ? "押镖未完成" : last
    }

    // MARK: - helpers

    private static func bangPaiXlUrl() -> String {
        let keys = (1...9).map { "rg_bp_xl_\($0)" }
        let i = RenWuStore.shared.radioIndex(keys)
        let id = xlIds[min(i, xlIds.count - 1)]
        return phoneBase + "cmd=factiontrain&type=2&id=\(id)&num=1&i_p_w=num%7C"
    }

    private static func bangPaiGfUrl() -> String {
        let keys = (1...13).map { "rg_bp_gf_\($0)" }
        let i = RenWuStore.shared.radioIndex(keys)
        let id = gfIds[min(i, gfIds.count - 1)]
        return phoneBase + "cmd=oblation&id=\(id)&page=1"
    }

    private static func extractClaim(_ html: String) -> String? {
        firstGroup(#"href="([^"]+)"[^>]*>\s*领取奖励"#, in: html)
            ?? firstGroup(#"<a href="([^"]+)"[^>]*>\s*领取奖励"#, in: html)
    }

    private static func lineOf(_ page: String, n: Int) -> String? {
        let keys = ["\(n).<a href=", "\(n).", "任务\(n)"]
        for k in keys {
            guard let idx = page.range(of: k)?.lowerBound else { continue }
            let end = page.range(of: "<br", range: idx..<page.endIndex)?.lowerBound
                ?? page.index(idx, offsetBy: 280, limitedBy: page.endIndex) ?? page.endIndex
            let capped = page.distance(from: idx, to: end) > 280
                ? page.index(idx, offsetBy: 280, limitedBy: page.endIndex) ?? end
                : end
            return String(page[idx..<capped])
        }
        return nil
    }

    private struct MenPaiSlot {
        let name: String
        let desc: String
        let actionLine: String
        var done: Bool {
            actionLine.contains("已完成") || desc.contains("已完成")
        }
    }

    private static func parseMenPaiSlots(_ page: String) -> [MenPaiSlot] {
        guard page.contains("任务1") else { return [] }
        return ["任务1", "任务2", "任务3"].compactMap { name -> MenPaiSlot? in
            let desc = brAfter(page, name)
            guard !desc.isEmpty else { return nil }
            let action = brAfter(page, desc).ifBlankMe(desc)
            return MenPaiSlot(name: name, desc: desc, actionLine: action)
        }
    }

    private static func brAfter(_ html: String, _ needle: String) -> String {
        let parts = html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
        guard let i = parts.firstIndex(where: { $0.contains(needle) }),
              i + 1 < parts.count
        else { return "" }
        return parts[i + 1]
    }

    private static func menPaiActKey(_ desc: String) -> String? {
        let keys = [
            "掌门", "首座", "堂主", "切磋同门", "切磋外派", "木桩",
            "查看同门", "查看外派", "上香", "心法", "传功",
        ]
        return keys.first(where: { desc.contains($0) })
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
