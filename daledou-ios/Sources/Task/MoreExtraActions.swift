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
        let doExchange = t.getBool("renwu", "cb_youji_3")
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
        let qq = await MainActor.run { SessionStore.shared.qq }
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

    // MARK: - 开锦囊 / 梦想之旅 / 仙武

    private static let jinNangKeyIds: [(String, String)] = [
        ("cb_jn_znfd", "8599"), ("cb_jn_cyhb", "8603"), ("cb_jn_fyhb", "8602"),
        ("cb_jn_jxmh", "8226"), ("cb_jn_zjrdsh", "8227"), ("cb_jn_zzjn", "8225"),
        ("cb_jn_jqjn", "8218"), ("cb_jn_lslb", "5299"), ("cb_jn_jxjn", "6779"),
        ("cb_jn_xjz", "5763"), ("cb_jn_jhw", "5162"), ("cb_jn_shih", "5160"),
        ("cb_jn_xhz", "5158"), ("cb_jn_hdz", "5159"), ("cb_jn_hhf", "5161"),
        ("cb_jn_hys", "3790"), ("cb_jn_sm", "3400"), ("cb_jn_hz_s", "3371"),
        ("cb_jn_hz_1", "3047"), ("cb_jn_hz_2", "3048"), ("cb_jn_hz_3", "3049"),
        ("cb_jn_hz_4", "3050"), ("cb_jn_xys", "3447"), ("cb_jn_yb_x", "5875"),
        ("cb_jn_yb_z", "5876"), ("cb_jn_yb_d", "5877"), ("cb_jn_dj_x", "5710"),
        ("cb_jn_dj_d", "5712"), ("cb_jn_sj", "5878"), ("cb_jn_zybj", "3671"),
    ]

    static func farmKaiJinNang(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var scanPage = t.getBool("more_settings", "cb_jn_jn")
        let picked = jinNangKeyIds.filter { t.getBool("more_settings", $0.0) }.map(\.1)
        // 悬浮窗一键：未勾选时默认扫锦囊页
        if !scanPage && picked.isEmpty {
            scanPage = true
        }
        onLog("开锦囊开始")
        var opened = 0
        let selfuin = LoginURLs.extractQq(cookie) ?? ""
        if selfuin.isEmpty {
            onLog("未识别 selfuin，将优先走手机 use")
        } else {
            onLog("selfuin=\(selfuin)")
        }

        func useOne(_ id: String) async -> String {
            var body = ""
            var msg = ""
            if !selfuin.isEmpty {
                let (_, r) = await LedouCGI.getPetPk(
                    cmd: "use", extra: ["selfuin": selfuin, "id": id], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                body = r
                msg = CombatLog.fromBody(r)
                if msg.contains("号码不允许") || r.contains("号码不允许") {
                    let (_, phoneBody) = await LedouCGI.getPhonePk(
                        cmd: "use", extra: ["id": id, "store_type": "5"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    body = phoneBody
                    msg = CombatLog.fromBody(phoneBody)
                }
            } else {
                let (_, r) = await LedouCGI.getPhonePk(
                    cmd: "use", extra: ["id": id, "store_type": "5"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                body = r
                msg = CombatLog.fromBody(r)
            }
            if msg.isEmpty { msg = "使用\(id)" }
            onLog(msg)
            if body.contains("系统繁忙") || msg.contains("系统繁忙") { return "busy" }
            if msg.contains("号码不允许") || body.contains("号码不允许")
                || msg.contains("重新登录") || msg.contains("重新登陆")
            {
                return "stop"
            }
            let result0 = body.contains("\"result\":0") || body.contains("\"result\": 0")
                || (try? NSRegularExpression(pattern: #""result"\s*:\s*0"#))?
                .firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil
            let ok = msg.contains("成功")
                || (!body.contains("\"result\":") && !msg.contains("不足") && !msg.contains("没有")
                    && !msg.contains("无法") && !msg.contains("不存在") && !msg.contains("等级不够")
                    && !body.contains("不足") && !body.contains("没有") && !body.contains("无法"))
            if result0 || (ok && !msg.contains("等级不够")) {
                opened += 1
                return "ok"
            }
            if msg.contains("等级不够") || body.contains("等级不够") { return "level" }
            return "skip"
        }

        func drainId(_ id: String, max: Int = 30) async -> Bool {
            var n = 0
            while n < max && opened < 80 {
                n += 1
                if Task.isCancelled { return false }
                switch await useOne(id) {
                case "ok": break
                case "busy":
                    try? await Task.sleep(nanoseconds: 200_000_000)
                case "stop":
                    onLog("使用被拒绝，已停止")
                    return false
                default:
                    return true
                }
            }
            return true
        }

        if scanPage {
            var page = 1
            var emptyStreak = 0
            while page <= 10 && opened < 80 {
                if Task.isCancelled { break }
                let (_, html) = await LedouCGI.getPhonePk(
                    cmd: "store", extra: ["store_type": "5", "page": "\(page)"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                if html.contains("系统繁忙") {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                guard let id = firstStoreUseId(html) else {
                    emptyStreak += 1
                    let h = html.replacingOccurrences(of: "&amp;", with: "&")
                    let hasNext = h.contains("下一页") || h.contains("page=\(page + 1)")
                    if !hasNext || emptyStreak >= 2 { break }
                    page += 1
                    continue
                }
                emptyStreak = 0
                if !(await drainId(id, max: 1)) { break }
                page = 1
            }
        }

        for id in picked {
            if opened >= 80 { break }
            if !(await drainId(id)) { break }
        }

        if opened == 0 {
            onLog("勾选的锦囊背包里没有或已用完")
        }
        onLog("开锦囊结束")
        return "开锦囊\(opened)"
    }

    static func farmMengXiangZhiLv(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("梦想之旅开始")
        let t = FeatureToggleStore.shared
        let minCount = Int(t.getString("more_settings", "ed_mxzl_min").trimmingCharacters(in: .whitespaces))
            .flatMap { $0 > 0 ? $0 : nil } ?? 5
        // lingjiang 勾选；悬浮窗默认全开
        let doPutong = t.getBool("lingjiang", "cb_lvyou_putong", default: true)
        let doQuyu = t.getBool("lingjiang", "cb_lvyou_quyu", default: true)
        let doZong = t.getBool("lingjiang", "cb_lvyou_zong", default: true)

        if doPutong {
            let (_, ordinary) = await LedouCGI.getPetPk(
                cmd: "dreamtrip", extra: ["smapid": "0", "sub": "1"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let om = CombatLog.fromBody(ordinary)
            if !om.isEmpty { onLog("普通旅行:\(om)") }
        }

        let dow = DailyListenActions.weekdayMon1()
        if dow == 4 {
            onLog("今日周四，开始补机票")
            var loops = 0
            while loops < 20 {
                loops += 1
                if Task.isCancelled { break }
                let (_, page) = await LedouCGI.getPetPk(
                    cmd: "dreamtrip", extra: ["bmapid": "0", "sub": "0"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                if page.contains("系统繁忙") {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                let msg = CombatLog.fromBody(page)
                if page.contains("\"result\"")
                    && !page.contains("\"result\":0")
                    && !page.contains("\"result\":\"0\"")
                {
                    if !msg.isEmpty { onLog(msg) }
                    break
                }
                let tickets = CombatLog.jsonInt(page, "dreamticket") ?? 0
                let maps = parseDreamMaps(page)
                let done = maps.filter { $0.1 == 1 }.count
                let todo = maps.filter { $0.1 == 0 }
                if todo.isEmpty {
                    onLog("小地图已全部完成")
                    break
                }
                if done < minCount || tickets < todo.count {
                    onLog("不满足补机票条件（完成\(done)/\(minCount)，机票\(tickets)，待打\(todo.count)）")
                    break
                }
                let smap = todo[0].0
                onLog("已完成\(done)，梦幻机票\(tickets)，旅行\(smap)")
                let (_, travel) = await LedouCGI.getPetPk(
                    cmd: "dreamtrip", extra: ["smapid": smap, "sub": "1"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let tm = CombatLog.fromBody(travel)
                if !tm.isEmpty { onLog("梦幻旅行:\(tm)") }
                if travel.contains("不足") || travel.contains("没有") { break }
            }
        } else {
            onLog("今日周\(dow)，不补机票")
        }

        if doQuyu {
            for i in 1...4 {
                let (_, r) = await LedouCGI.getPetPk(
                    cmd: "dreamtrip", extra: ["sub": "2", "bmapid": "\(i)"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let m = CombatLog.fromBody(r)
                if !m.isEmpty { onLog("区域\(i):\(m)") }
            }
        }
        if doZong {
            let (_, total) = await LedouCGI.getPetPk(
                cmd: "dreamtrip", extra: ["sub": "2", "bmapid": "0"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("总奖励：\(CombatLog.fromBody(total).ifBlankMe("已请求"))")
        }
        onLog("梦想之旅结束")
        return "梦想之旅完成"
    }

    static func farmXianWu(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var mountain = 0
        if t.getBool("more_settings", "rg_xwxz_1") { mountain = 1 }
        else if t.getBool("more_settings", "rg_xwxz_2") { mountain = 2 }
        else if t.getBool("more_settings", "rg_xwxz_3") { mountain = 3 }
        let autoRate = t.getBool("more_settings", "cb_xwxz_auto")
        let autoRefresh = t.getBool("more_settings", "cb_xwxz_auto_shuaxin")
        // 悬浮窗：未勾选时默认力量山
        if mountain <= 0 && !autoRate { mountain = 1 }
        onLog("仙武修真开始")
        for taskid in 1...3 {
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "immortals", extra: ["op": "getreward", "taskid": "\(taskid)"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let m = CombatLog.fromBody(r)
            if !m.isEmpty { onLog("任务\(taskid):\(m)") }
        }
        var mid = max(mountain, 1)
        if autoRate {
            let (_, cfg) = await LedouCGI.getPetPk(
                cmd: "immortals", extra: ["op": "findimmortals"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if let hit = firstMatchInt(cfg, #"爆率提升[\s\S]{0,80}?mountainId[=:](\d+)"#)
                ?? firstMatchInt(cfg, #""index"\s*:\s*"?(\d+)[^}]*爆率"#)
            {
                mid = hit
                onLog("按爆率自动选山\(mid)")
            }
        }
        var fights = 0
        while fights < 20 {
            if Task.isCancelled { break }
            let (_, find) = await LedouCGI.getPetPk(
                cmd: "immortals", extra: ["op": "findimmortals"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let left = CombatLog.jsonInt(find, "leftNum")
                ?? CombatLog.jsonInt(find, "left_num")
                ?? CombatLog.jsonInt(find, "leftTimes")
            if let left, left <= 0 {
                onLog("没次数了")
                break
            }
            let (_, visit) = await LedouCGI.getPetPk(
                cmd: "immortals",
                extra: ["op": "visitimmortals", "mountainId": "\(mid)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let vmsg = CombatLog.fromBody(visit)
            if !vmsg.isEmpty { onLog(vmsg) }
            let ifFree = CombatLog.jsonInt(visit, "ifFree") ?? 0
            let ifUp = CombatLog.jsonInt(visit, "ifUp") ?? 0
            if autoRefresh && ifFree > 0 && ifUp == 0 {
                let (_, ref) = await LedouCGI.getPetPk(
                    cmd: "immortals", extra: ["op": "refreshimmortals"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(ref).ifBlankMe("免费刷新"))
                continue
            }
            let (_, fight) = await LedouCGI.getPetPk(
                cmd: "immortals", extra: ["op": "fightimmortals"], cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            let fmsg = CombatLog.fromBody(fight)
            if !fmsg.isEmpty { onLog(fmsg) }
            if fight.contains("不足") || fight.contains("没有") || fight.contains("上限")
                || fight.contains("明天") || fmsg.contains("没次数")
            {
                break
            }
        }
        onLog("仙武修真结束")
        return "仙武\(fights)"
    }

    // MARK: - helpers

    private static func firstStoreUseId(_ html: String) -> String? {
        let lines = html.components(separatedBy: CharacterSet(charactersIn: "\n"))
            .flatMap { $0.components(separatedBy: "<br />") }
            .flatMap { $0.components(separatedBy: "<br/>") }
            .flatMap { $0.components(separatedBy: "<br>") }
        for line in lines where line.contains("使用") {
            if let id = firstMatch(line, #"cmd=use[^"'\s>]*[?&]id=(\d+)"#)
                ?? firstMatch(line, #"[?&]id=(\d+)[^"'\s>]*cmd=use"#)
            {
                return id
            }
        }
        return firstMatch(html, #"cmd=use[^"'>\s]*[?&]id=(\d+)"#)
    }

    private static func parseDreamMaps(_ body: String) -> [(String, Int)] {
        var out: [(String, Int)] = []
        let re1 = try? NSRegularExpression(
            pattern: #"\{[^{}]*"id"\s*:\s*"?(\d+)[^{}]*"status"\s*:\s*"?(\d+)[^{}]*\}"#
        )
        let ns = body as NSString
        re1?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 3 else { return }
            let id = ns.substring(with: m.range(at: 1))
            let st = Int(ns.substring(with: m.range(at: 2))) ?? 0
            out.append((id, st))
        }
        if out.isEmpty {
            let re2 = try? NSRegularExpression(
                pattern: #"\{[^{}]*"status"\s*:\s*"?(\d+)[^{}]*"id"\s*:\s*"?(\d+)[^{}]*\}"#
            )
            re2?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 3 else { return }
                let st = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let id = ns.substring(with: m.range(at: 2))
                out.append((id, st))
            }
        }
        return out
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func firstMatchInt(_ text: String, _ pattern: String) -> Int? {
        firstMatch(text, pattern).flatMap(Int.init)
    }

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
