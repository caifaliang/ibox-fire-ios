import Foundation

/// 真源：`MoreExtraActions.kt` — 悬浮窗「报名 / 更多 / 电脑」简易项。
enum MoreExtraActions {
    private static let gapNs: UInt64 = 80_000_000
    private static let pcSaiqu: Set<String> = ["01", "02", "03", "04", "05"]

    // MARK: - 报名

    static func signupFeiSheng(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let type = Bool.random() ? "2" : "1"
        let label = type == "1" ? "排位" : "匹配"
        onLog("飞升报名-\(label) 开始")
        let (_, r) = await LedouCGI.getPetPk(
            cmd: "ascendheaven", extra: ["op": "signup", "type": type], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(r).ifBlankMe("已请求")
        onLog(msg)
        return "飞升\(type):\(msg)"
    }

    static func signupXiaLvPhone(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("手机侠侣报名开始")
        let (_, r) = await LedouCGI.getPhonePk(cmd: "cfight", extra: ["subtype": "9"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(r).ifBlankMe("已请求")
        onLog(msg)
        return msg
    }

    static func signupXiaLvPc(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("电脑侠侣报名开始")
        let (_, r) = await LedouCGI.getPetPk(cmd: "couplefight", extra: ["subtype": "4"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(r).ifBlankMe("已请求")
        onLog(msg)
        return msg
    }

    static func signupQunXia(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("群侠报名开始")
        let (_, r) = await LedouCGI.getPetPk(
            cmd: "knightfight", extra: ["op": "signup"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(r).ifBlankMe("已请求")
        onLog(msg)
        return msg
    }

    static func signupWuLinPhone(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("手机武林报名开始（按等级随机分区）")
        let (_, r) = await LedouCGI.getPhonePk(
            cmd: "fastSignWulin", extra: ["ifFirstSign": "1"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = wulinResult(r)
        onLog(msg)
        return msg
    }

    static func signupWuLinPc(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("电脑武林报名开始")
        let (_, show) = await LedouCGI.getPetPk(cmd: "showwulin", cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let pcIds = parseShowWuLinIds(show).filter { pcSaiqu.contains(saiquOf($0)) }
        let forced = FeatureToggleStore.shared.getString("chaqu", "wlbm_saiqu_pc").trimmingCharacters(in: .whitespaces)
        let names = ["01": "华东", "02": "华西", "03": "华中", "04": "华南", "05": "华北"]
        let signupId: String? = {
            if forced.count == 2 {
                return pcIds.first { saiquOf($0) == forced }
            }
            return pcIds.randomElement()
        }()
        guard let signupId, !signupId.isEmpty else {
            let tip = forced.count == 2
                ? "指定电脑赛区 \(forced) 本周未开放"
                : "本周没有电脑赛区（华东–华北）"
            onLog(tip)
            return tip
        }
        let sq = saiquOf(signupId)
        onLog("电脑赛区-\(names[sq] ?? sq) id=\(signupId)")
        let url = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=signup&ifFirstSign=1&id=\(signupId)&cmd=qsinginwl"
        guard let u = URL(string: url) else { return "URL 无效" }
        let (_, r) = await LedouCGI.get(url: u, cookie: cookie, referer: LedouCGI.petpkBase)
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = wulinResult(r)
        onLog(msg)
        return msg
    }

    // MARK: - 踢馆 / 游记 / 祭坛

    static func farmTiGuan(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let wd = DailyListenActions.weekdayMon1()
        let hour = DailyListenActions.hourGmt8()
        if !(wd == 5 && (6...22).contains(hour)) {
            onLog("踢馆不在活动时间（仅周五6–22点）")
            return "不在活动时间"
        }
        onLog("踢馆开始")
        var rounds = 0
        let steps: [(String, String)] = [("6", "高倍转盘"), ("3", "挑战"), ("2", "试炼")]
        let limits = ["6": 4, "3": 36, "2": 8]
        for (sub, tag) in steps {
            var n = 0
            let max = limits[sub] ?? 8
            while n < max {
                if Task.isCancelled { return "已取消" }
                let (_, r) = await LedouCGI.getPetPk(
                    cmd: "fac_challenge", extra: ["subtype": sub], cookie: cookie
                )
                n += 1
                rounds += 1
                try? await Task.sleep(nanoseconds: gapNs)
                let msg = CombatLog.fromBody(r)
                if !msg.isEmpty { onLog("[\(tag)]\(msg)") }
                if r.contains("不在活动")
                    || (r.contains("次数") && (r.contains("不足") || r.contains("用完") || r.contains("上限")))
                {
                    break
                }
                if r.contains("系统繁忙") {
                    try? await Task.sleep(nanoseconds: gapNs)
                    continue
                }
            }
        }
        onLog("踢馆结束")
        return "踢馆轮次\(rounds)"
    }

    static func farmYouJi(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("游记任务开始")
        let t = FeatureToggleStore.shared
        var doTask = t.getBool("renwu", "cb_youji_1")
        var doAward = t.getBool("renwu", "cb_youji_2")
        var doExchange = t.getBool("renwu", "cb_youji_3")
        // 悬浮窗一键：未勾选时默认做任务+领奖
        if !doTask && !doAward && !doExchange {
            doTask = true
            doAward = true
        }
        var done = 0
        if doTask {
            for id in 1...5 {
                if Task.isCancelled { break }
                var retries = 0
                while retries < 3 {
                    let (_, r) = await LedouCGI.getPetPk(
                        cmd: "newAct",
                        extra: ["subtype": "165", "task_id": "\(id)", "op": "2"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let msg = CombatLog.fromBody(r)
                    if msg.contains("系统繁忙") || r.contains("系统繁忙") {
                        retries += 1
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        continue
                    }
                    if !msg.isEmpty { onLog("任务\(id):\(msg)") }
                    if r.contains("不在活动") || msg.contains("不在活动")
                        || r.contains("登陆校验") || msg.contains("登陆校验")
                    {
                        onLog("游记不在活动期，结束")
                        return "游记不在活动期"
                    }
                    done += 1
                    break
                }
            }
        }
        if doAward {
            var retries = 0
            while retries < 3 {
                let (_, r) = await LedouCGI.getPetPk(
                    cmd: "newAct", extra: ["subtype": "165", "op": "6"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let msg = CombatLog.fromBody(r)
                if msg.contains("系统繁忙") || r.contains("系统繁忙") {
                    retries += 1
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                onLog("领奖：\(msg.ifBlankMe("已请求"))")
                done += 1
                break
            }
        }
        if doExchange {
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "newAct", extra: ["subtype": "165", "op": "3", "num": "1"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let em = CombatLog.fromBody(r)
            if !em.isEmpty && !em.contains("溢出积分不足") {
                onLog("兑换：\(em)")
            } else if !em.isEmpty {
                onLog(String(em.prefix(40)))
            }
            done += 1
        }
        let tip = "游记完成\(done)步"
        onLog(tip)
        return tip
    }

    static func farmJiTan(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let pay = FeatureToggleStore.shared.getBool("more_settings", "cb_jitan_fufei")
        onLog("帮派祭坛开始\(pay ? "（含转转券）" : "（仅免费）")")
        var spins = 0
        var loops = 0
        while loops < 40 {
            if Task.isCancelled { break }
            loops += 1
            let (_, page) = await LedouCGI.getPetPk(cmd: "altar", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            if page.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            let lastMat = CombatLog.jsonField(page, "last_reward_materials") ?? ""
            if !lastMat.isEmpty && lastMat != "0" {
                let (_, draw) = await LedouCGI.getPetPk(
                    cmd: "altar", extra: ["op": "drawreward"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(draw).ifBlankMe("领奖"))
                continue
            }
            let free = CombatLog.jsonInt(page, "left_free_wheel_times") ?? 0
            let quan = CombatLog.jsonInt(page, "zhuan_zhuan_quan_num") ?? 0
            let action = CombatLog.jsonInt(page, "current_action_id") ?? 0
            onLog("免费=\(free)，转转券=\(quan)，动作=\(action)")
            if !pay && free == 0 && action == 0 { break }
            switch action {
            case 0:
                if !pay && free <= 0 { break }
                let (_, spin) = await LedouCGI.getPetPk(
                    cmd: "altar", extra: ["op": "spinwheel"], cookie: cookie
                )
                spins += 1
                try? await Task.sleep(nanoseconds: gapNs)
                let sm = CombatLog.fromBody(spin)
                if !sm.isEmpty { onLog(sm) }
                if sm.contains("入帮24小时") || sm.contains("转转券不足") || sm.contains("已达转转券") {
                    break
                }
            case 1003, 1004:
                let op = action == 1004 ? "steal" : "rob"
                let (_, targets) = await LedouCGI.getPetPk(
                    cmd: "altar", extra: ["op": "showspecialtargets"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let tid: String? = {
                    if let m = targets.range(of: #""id"\s*:\s*"?(\d+)"#, options: .regularExpression) {
                        let s = String(targets[m])
                        if let r = s.range(of: #"\d+"#, options: .regularExpression) { return String(s[r]) }
                    }
                    return nil
                }()
                if let tid {
                    let (_, act) = await LedouCGI.getPetPk(
                        cmd: "altar", extra: ["id": tid, "op": op], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(act).ifBlankMe(op))
                } else {
                    onLog("无特殊目标，跳过\(op)")
                    _ = await LedouCGI.getPetPk(cmd: "altar", extra: ["op": "drawreward"], cookie: cookie)
                    try? await Task.sleep(nanoseconds: gapNs)
                }
            default:
                onLog("不支持的动作\(action)")
                _ = await LedouCGI.getPetPk(cmd: "altar", extra: ["op": "drawreward"], cookie: cookie)
                try? await Task.sleep(nanoseconds: gapNs)
            }
        }
        onLog("帮派祭坛结束")
        return "祭坛转\(spins)"
    }

    // MARK: - 微端

    static func weiDuanJingYan(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("微端经验礼包")
        let (_, r) = await LedouCGI.getPetPk(cmd: "weiduangift", extra: ["op": "2"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(r).ifBlankMe("已请求")
        onLog(msg)
        return msg
    }

    static func weiDuanGuaJi(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("【微端挂机】获取挂机数据中")
        let q = await microendUntilSettled(cookie: cookie, op: "0", tries: 6)
        let qMsg = CombatLog.fromBody(q)
        let result = CombatLog.jsonInt(q, "result") ?? -1
        let hours = CombatLog.jsonInt(q, "left_hours") ?? 0
        let minutes = CombatLog.jsonInt(q, "left_minutes") ?? 0
        onLog("【微端挂机】查询 result=\(result) left=\(hours)h\(minutes)m")
        if result == 0 {
            return await startWeiDuanHang(cookie: cookie, onLog: onLog)
        }
        if qMsg.contains("系统繁忙") || q.contains("系统繁忙") {
            let startMsg = await startWeiDuanHang(cookie: cookie, onLog: onLog)
            if startMsg.contains("已处于挂机") || startMsg.contains("成功") { return startMsg }
            onLog("【微端挂机】已在挂机中（查询系统繁忙）")
            return "已在挂机"
        }
        let tip = qMsg.ifBlankMe("不是微端登录")
        onLog("【微端挂机】\(tip)")
        return tip
    }

    static func weiDuanStop(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("【微端结束挂机】获取挂机数据中")
        let qq = SessionStore.shared.qq
        if !qq.isEmpty {
            _ = await LedouCGI.getPetPk(cmd: "visit", extra: ["puin": qq, "kind": "1"], cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
        }
        let (_, r) = await LedouCGI.getPetPk(cmd: "microend", extra: ["op": "2"], cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(r).ifBlankMe("已请求")
        onLog("【微端结束挂机】\(msg)")
        return msg
    }

    private static func startWeiDuanHang(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let start = await microendUntilSettled(cookie: cookie, op: "1", tries: 6)
        let sm = CombatLog.fromBody(start).ifBlankMe("已请求")
        if sm.contains("已处于挂机") || sm.contains("成功") {
            onLog("【微端开始挂机】\(sm)====期间如果查询信息会导致挂机结束")
            return sm
        }
        if sm.contains("系统繁忙") || start.contains("系统繁忙") {
            onLog("【微端挂机】已在挂机中（开始接口繁忙）")
            return "已在挂机"
        }
        onLog("【微端挂机】\(sm)")
        return sm
    }

    private static func microendUntilSettled(cookie: String, op: String, tries: Int) async -> String {
        var last = ""
        for i in 0..<max(1, tries) {
            let (_, body) = await LedouCGI.getPetPk(cmd: "microend", extra: ["op": op], cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            last = body
            let msg = CombatLog.fromBody(body)
            if CombatLog.jsonInt(body, "result") == 0 { return body }
            if !msg.contains("系统繁忙") && !body.contains("系统繁忙") { return body }
            if i < tries - 1 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        return last
    }

    // MARK: - helpers

    private static func saiquOf(_ id: String) -> String {
        id.count == 8 ? String(id.dropFirst(4).prefix(2)) : ""
    }

    private static func parseShowWuLinIds(_ body: String) -> [String] {
        let re = try? NSRegularExpression(pattern: #""id"\s*:\s*"(\d{8})""#)
        let ns = body as NSString
        var out: [String] = []
        re?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 2 else { return }
            let id = ns.substring(with: m.range(at: 1))
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    private static func wulinResult(_ body: String) -> String {
        let json = CombatLog.fromBody(body)
        if !json.isEmpty { return json }
        let plain = body
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = plain.range(of: #"报名状态[：:]\S{0,24}|已报\S{0,32}|赛场\S{0,24}"#, options: .regularExpression) {
            return String(plain[m])
        }
        return String(plain.prefix(48)).ifBlankMe("已请求")
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
