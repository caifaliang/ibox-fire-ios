import Foundation
import CryptoKit

/// 真源：`MoreExtraActions.kt` — 悬浮窗「报名 / 更多 / 电脑」简易项。
enum MoreExtraActions {
    private static let gapNs: UInt64 = 80_000_000
    private static let pcSaiqu: Set<String> = ["01", "02", "03", "04", "05"]

    /// UI 写入后由 `pcSuo` 消费。
    static var pendingPcPassword: String?
    static var pendingPcFlag: String?

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

    // MARK: - 武器充能

    private static let wuQiNameKeys: [(String, String)] = [
        ("龙舌弓", "cb_wqcn_lsg"), ("轩辕剑", "cb_wqcn_xyj"), ("金箍棒", "cb_wqcn_jgb"),
        ("玄铁磁石", "cb_wqcn_xtcs"), ("啤酒瓶", "cb_wqcn_pjp"), ("黑桃A", "cb_wqcn_hta"),
        ("绣花针", "cb_wqcn_xhz"), ("圣诞棒棒糖", "cb_wqcn_sdbbt"), ("乐斗拳套", "cb_wqcn_ldqt"),
        ("劳动节扫把", "cb_wqcn_ldjsb"), ("新春鞭炮", "cb_wqcn_xcbp"), ("冰镇西瓜", "cb_wqcn_bzxg"),
    ]

    static func farmWuQiChongNeng(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var enabled = Set(wuQiNameKeys.filter { t.getBool("more_settings", $0.1) }.map(\.0))
        // 悬浮窗一键：未勾选时尝试全部已知武器
        if enabled.isEmpty {
            enabled = Set(wuQiNameKeys.map(\.0))
        }
        onLog("武器充能开始（\(enabled.sorted().joined(separator: "、"))）")
        var charged = 0
        var loops = 0
        while loops < 40 {
            loops += 1
            if Task.isCancelled { break }
            let (_, list) = await LedouCGI.getPetPk(
                cmd: "exchange", extra: ["subtype": "15"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if list.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            let items = parseExchangeNameTypes(list)
            var did = false
            for (name, type) in items {
                guard enabled.contains(where: { name.contains($0) || $0.contains(name) }) else { continue }
                if list.contains("尚未充能完毕"),
                   list.range(of: "\(name)[\\s\\S]{0,120}尚未充能完毕", options: .regularExpression) != nil
                {
                    continue
                }
                let esc = NSRegularExpression.escapedPattern(for: name)
                if let block = firstMatch(list, "\\{[^{}]*\(esc)[^{}]*\\}"),
                   block.contains("\"open\":\"0\"") || block.contains("\"open\":0")
                {
                    continue
                }
                let (_, r) = await LedouCGI.getPetPk(
                    cmd: "exchange",
                    extra: ["subtype": "2", "type": type, "times": "1"],
                    cookie: cookie
                )
                charged += 1
                did = true
                try? await Task.sleep(nanoseconds: gapNs)
                let msg = CombatLog.fromBody(r).ifBlankMe("充能\(name)")
                onLog(msg)
                if r.contains("系统繁忙") || msg.contains("恭喜您充能成功") || msg.contains("充能成功") {
                    break
                }
            }
            if !did { break }
        }
        onLog("武器充能结束")
        return "武器充能\(charged)"
    }

    // MARK: - 遗迹 / 龙吟 / 天地宝匣

    static func farmYiJiZhengFa(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var cave = t.getBool("more_settings", "cb_yjzf_1")
        let caveAuto = t.getBool("more_settings", "cb_yjzf_auto")
        var unionDaily = t.getBool("more_settings", "cb_yjzf_2")
        let unionThu = t.getBool("more_settings", "cb_yjzf_3")
        // 悬浮窗：未勾选时默认洞穴+每日联合
        if !cave && !caveAuto && !unionDaily && !unionThu {
            cave = true
            unionDaily = true
        }
        onLog("遗迹征伐开始")
        var steps = 0
        if caveAuto || cave {
            _ = await LedouCGI.getPetPk(cmd: "spacerelic", extra: ["op": "finishtime"], cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            let layers = caveAuto ? Array((1...5).reversed()) : [5]
            for id in layers {
                if Task.isCancelled { break }
                onLog("异兽洞穴第\(id)层")
                _ = await LedouCGI.getPetPk(
                    cmd: "spacerelic", extra: ["id": "\(id)", "op": "monster"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let (_, sao) = await LedouCGI.getPetPk(
                    cmd: "spacerelic", extra: ["id": "\(id)", "op": "saodang"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let sm = CombatLog.fromBody(sao)
                if !sm.isEmpty { onLog("扫荡:\(sm)") }
                let (_, fight) = await LedouCGI.getPetPk(
                    cmd: "spacerelic", extra: ["id": "\(id)", "op": "monsterfight"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let fm = CombatLog.fromBody(fight)
                if !fm.isEmpty { onLog("挑战:\(fm)") }
                steps += 1
                if sao.contains("不足") && fight.contains("不足") { break }
            }
        }
        let dow = DailyListenActions.weekdayMon1()
        let hour = DailyListenActions.hourGmt8()
        let thuWindow = (dow == 4 && hour >= 6) || (dow == 5 && hour < 6)
        if unionDaily || (unionThu && thuWindow) {
            let tag = unionDaily ? "联合征伐-每日" : "联合征伐-周四"
            onLog(tag)
            _ = await LedouCGI.getPetPk(cmd: "spacerelic", extra: ["op": "showunion"], cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            let (_, bf) = await LedouCGI.getPetPk(
                cmd: "spacerelic", extra: ["op": "bossfight"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog(CombatLog.fromBody(bf).ifBlankMe(tag))
            steps += 1
        }
        onLog("遗迹征伐结束")
        return "遗迹\(steps)"
    }

    static func farmLongYin(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("龙吟破阵开始（十连×10）")
        var draws = 0
        var tidy = false
        var guard = 0
        while draws < 10 && guard < 16 {
            guard += 1
            if Task.isCancelled { break }
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "dragon", extra: ["times": "10", "op": "lottery"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = (CombatLog.jsonField(r, "msg") ?? "").ifBlankMe(CombatLog.fromBody(r))
            let have = CombatLog.jsonField(r, "have") ?? ""
            let result = CombatLog.jsonInt(r, "result")
            onLog(have.isEmpty ? msg.ifBlankMe("十连") : "剩余龙玉\(have)，\(msg)")
            if msg.contains("系统繁忙") || r.contains("系统繁忙") { continue }
            if let result, result != 0 {
                onLog("龙吟破阵结束")
                return "龙吟十连\(draws)"
            }
            if msg.contains("龙玉不足") {
                tidy = true
                break
            }
            if msg.contains("不在活动") || msg.contains("等级不够") { break }
            draws += 1
            if draws >= 10 { tidy = true }
        }
        if tidy {
            await tidyLongYin(cookie: cookie, onLog: onLog)
        }
        onLog("龙吟破阵结束")
        return "龙吟十连\(draws)"
    }

    private static func tidyLongYin(cookie: String, onLog: @escaping (String) -> Void) async {
        var op = "config"
        var id = 0
        var steps = 0
        while steps < 40 {
            steps += 1
            if Task.isCancelled { break }
            let (_, body) = await LedouCGI.getPetPk(
                cmd: "dragon", extra: ["id": "\(id)", "op": op], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if body.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            let result = CombatLog.jsonInt(body, "result")
            if let result, result != 0 {
                onLog(CombatLog.fromBody(body).ifBlankMe("整理结束"))
                break
            }
            let star = CombatLog.jsonInt(body, "star") ?? 0
            let desc = CombatLog.jsonField(body, "desc") ?? ""
            let have = CombatLog.jsonInt(body, "have") ?? 0
            if star >= 5 && !desc.contains("(0)") {
                let (_, resolve) = await LedouCGI.getPetPk(
                    cmd: "dragon", extra: ["id": "\(id)", "op": "resolve"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("分解\(id)：\(CombatLog.fromBody(resolve).ifBlankMe("ok"))")
                op = "config"
                continue
            }
            if have > 0 {
                let (_, up) = await LedouCGI.getPetPk(
                    cmd: "dragon", extra: ["id": "\(id)", "op": "upstar"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let um = CombatLog.fromBody(up)
                if um.contains("不足") || um.contains("没有") {
                    id += 1
                    op = "config"
                    continue
                }
                onLog("升星\(id)：\(um.ifBlankMe("ok"))")
                op = "config"
                continue
            }
            id += 1
            if id > 30 { break }
            op = "config"
        }
    }

    static func farmTianDiBaoXia(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("天地宝匣开始")
        var opened = 0
        for _ in 0..<30 {
            if Task.isCancelled { break }
            let (_, view) = await LedouCGI.getPetPk(
                cmd: "career", extra: ["op": "treasureview"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if view.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: gapNs)
                continue
            }
            let result = CombatLog.jsonInt(view, "result")
            let msg = CombatLog.jsonField(view, "msg") ?? ""
            if let result, result != 0 {
                onLog(msg.ifBlankMe("查询失败"))
                return "天地宝匣失败"
            }
            let anima = CombatLog.jsonInt(view, "anima_num") ?? 0
            let animaMax = CombatLog.jsonInt(view, "anima_max") ?? 0
            if animaMax > 0 && anima >= animaMax {
                let (_, claim) = await LedouCGI.getPetPk(
                    cmd: "career", extra: ["op": "mclaim"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog((CombatLog.jsonField(claim, "msg") ?? "")
                    .ifBlankMe(CombatLog.fromBody(claim).ifBlankMe("领取灵气")))
                continue
            }
            guard let box = firstBoxWithNum(view) else {
                onLog("天地宝匣结束")
                return "开匣\(opened)"
            }
            let count: Int = {
                if box.1 >= 100 { return 100 }
                if box.1 >= 10 { return 10 }
                return 1
            }()
            let (_, open) = await LedouCGI.getPetPk(
                cmd: "career",
                extra: ["op": "boxopen", "count": "\(count)", "boxId": box.0],
                cookie: cookie
            )
            opened += 1
            try? await Task.sleep(nanoseconds: gapNs)
            onLog((CombatLog.jsonField(open, "msg") ?? "").ifBlankMe("开匣\(box.0)×\(count)"))
            if open.contains("不足") || open.contains("没有") { return "开匣\(opened)" }
        }
        onLog("天地宝匣结束")
        return "开匣\(opened)"
    }

    private static func firstBoxWithNum(_ body: String) -> (String, Int)? {
        let re = try? NSRegularExpression(
            pattern: #""id"\s*:\s*"?(\d+)"?[^}]*"num"\s*:\s*"?(\d+)""#
        )
        let ns = body as NSString
        var hit: (String, Int)?
        re?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m, m.numberOfRanges >= 3 else { return }
            let id = ns.substring(with: m.range(at: 1))
            let num = Int(ns.substring(with: m.range(at: 2))) ?? 0
            if num > 0 {
                hit = (id, num)
                stop.pointee = true
            }
        }
        return hit
    }

    // MARK: - 五行 / 符石 / 遗迹商店

    static func farmWuXing(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var gameType = -1
        if t.getBool("more_settings", "rb_wx_db_1") { gameType = 0 }
        else if t.getBool("more_settings", "rb_wx_db_2") { gameType = 1 }
        else if t.getBool("more_settings", "rb_wx_db_3") { gameType = 2 }
        else if t.getBool("more_settings", "rb_wx_db_4") { gameType = 3 }
        // 悬浮窗：未勾选默认沙漠
        if gameType < 0 { gameType = 0 }
        let names = ["沙漠", "海底", "密林", "太空"]
        onLog("五行夺宝开始（\(names[gameType])）")
        var rounds = 0
        while rounds < 30 {
            rounds += 1
            if Task.isCancelled { break }
            let (_, status) = await LedouCGI.getPetPk(
                cmd: "element", extra: ["subtype": "5"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(status)
            if !msg.isEmpty { onLog(msg) }
            if status.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            let inGame = status.contains("\"gameIngFlag\":1")
                || status.contains("\"gameIngFlag\":\"1\"")
                || status.contains("要走完") || status.contains("进行中")
            let next: String
            if inGame {
                next = await LedouCGI.getPetPk(cmd: "element", extra: ["subtype": "6"], cookie: cookie).1
            } else {
                next = await LedouCGI.getPetPk(
                    cmd: "element",
                    extra: ["gameType": "\(gameType)", "subtype": "9"],
                    cookie: cookie
                ).1
            }
            try? await Task.sleep(nanoseconds: gapNs)
            let nmsg = CombatLog.fromBody(next)
            if !nmsg.isEmpty { onLog(nmsg) }
            if next.contains("不足") || next.contains("用完") || next.contains("上限")
                || next.contains("没有") || next.contains("结束") || next.contains("已达")
            {
                break
            }
            if msg.contains("不足") || msg.contains("用完") || msg.contains("上限") { break }
        }
        onLog("五行夺宝结束")
        return "五行夺宝\(rounds)"
    }

    static func farmDaZaoFuShi(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var do1 = t.getBool("more_settings", "cb_fs_1")
        var do2 = t.getBool("more_settings", "cb_fs_2")
        // 悬浮窗：未勾选时只打造不分解
        if !do1 && !do2 {
            do1 = false
            do2 = false
        }
        onLog("打造符石开始")
        var loops = 0
        while loops < 12 {
            loops += 1
            if Task.isCancelled { break }
            let (_, craft) = await LedouCGI.getPetPk(
                cmd: "weapongod",
                extra: ["sub": "7", "times": "1", "produce_type": "1"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let cmsg = CombatLog.fromBody(craft)
            if !cmsg.isEmpty { onLog(cmsg) }
            if craft.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            if craft.contains("不足") || craft.contains("没有") || craft.contains("无法") { break }
            var qualities: [Int] = []
            if do1 { qualities.append(1) }
            if do2 { qualities.append(2) }
            if qualities.isEmpty { break }
            var did = false
            for q in qualities {
                for page in 1...3 {
                    let (_, list) = await LedouCGI.getPetPk(
                        cmd: "weapongod",
                        extra: ["quality": "\(q)", "sub": "10", "type": "0", "page": "\(page)"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    let stoneIds = collectStoneIds(list)
                    for sid in stoneIds.prefix(5) {
                        let (_, d) = await LedouCGI.getPetPk(
                            cmd: "weapongod",
                            extra: ["sub": "9", "decom_array": sid],
                            cookie: cookie
                        )
                        try? await Task.sleep(nanoseconds: gapNs)
                        let dm = CombatLog.fromBody(d)
                        if !dm.isEmpty { onLog("分解\(q):\(dm)") }
                        did = true
                    }
                    for sid in stoneIds.prefix(5) {
                        let (_, c) = await LedouCGI.getPetPk(
                            cmd: "weapongod",
                            extra: ["opt": "0", "sub": "11", "stone_id": sid],
                            cookie: cookie
                        )
                        try? await Task.sleep(nanoseconds: gapNs)
                        let cm = CombatLog.fromBody(c)
                        if !cm.isEmpty { onLog("合成\(q):\(cm)") }
                        did = true
                    }
                    if list.contains("不足") || !list.contains("stone") { break }
                }
            }
            if !did { break }
        }
        onLog("打造符石结束")
        return "打造符石\(loops)"
    }

    private static let yjsdDefaultIds = ["4", "1", "2", "3", "8", "5", "6", "7"]

    static func farmYiJiShangDian(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        onLog("遗迹商店兑换开始")
        let t = FeatureToggleStore.shared
        let picked = yjsdDefaultIds.filter { t.getBool("more_settings", "cb_yjsd_\($0)") }
        let want = picked.isEmpty ? yjsdDefaultIds : picked
        var buys = 0
        for _ in 0..<40 {
            if Task.isCancelled { break }
            let (_, shop) = await LedouCGI.getPetPk(
                cmd: "spacerelic", extra: ["op": "shop"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if shop.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: gapNs)
                continue
            }
            if let result = CombatLog.jsonInt(shop, "result"), result != 0 {
                onLog((CombatLog.jsonField(shop, "msg") ?? "").ifBlankMe("商店查询失败"))
                return "兑换失败"
            }
            let score = CombatLog.jsonInt(shop, "score")
                ?? firstMatchInt(shop, #""score"\s*:\s*"?(\d+)""#)
                ?? 0
            guard let hit = want.compactMap({ shopOffer(shop, id: $0) }).first else {
                onLog("遗迹商店兑换结束")
                return "兑换\(buys)"
            }
            let (id, remain, price) = hit
            let num: Int
            if remain >= 10 && score >= price * 10 {
                num = 10
            } else if remain >= 1 && score >= price {
                num = 1
            } else {
                onLog("积分不足")
                return "兑换\(buys)"
            }
            let (_, buy) = await LedouCGI.getPetPk(
                cmd: "spacerelic",
                extra: ["id": id, "num": "\(num)", "op": "buy"],
                cookie: cookie
            )
            buys += 1
            try? await Task.sleep(nanoseconds: gapNs)
            onLog((CombatLog.jsonField(buy, "msg") ?? "").ifBlankMe("兑换\(id)×\(num)"))
            if buy.contains("积分不足") || buy.contains("不足") { return "兑换\(buys)" }
        }
        onLog("遗迹商店兑换结束")
        return "兑换\(buys)"
    }

    private static func shopOffer(_ shop: String, id: String) -> (String, Int, Int)? {
        let esc = NSRegularExpression.escapedPattern(for: id)
        guard let block = firstMatch(shop, "\"id\"\\s*:\\s*\"\(esc)\"\\s*,[^}]*") else { return nil }
        let remain = firstMatchInt(block, #""remain"\s*:\s*"?(\d+)""#) ?? 0
        if remain <= 0 { return nil }
        let price = firstMatchInt(block, #""score"\s*:\s*"?(\d+)""#) ?? 0
        return (id, remain, price)
    }

    private static func collectStoneIds(_ body: String) -> [String] {
        var out: [String] = []
        let re = try? NSRegularExpression(pattern: #""stone_id"\s*:\s*"?(\d+)""#)
        let ns = body as NSString
        re?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 2 else { return }
            let id = ns.substring(with: m.range(at: 1))
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    // MARK: - 帮派远征 / 黄金联赛 / 长梦 / PC 锁

    static func farmBangPaiYuanZheng(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var minP = Int(t.getString("more_settings", "ed_bpyz_zl_min").trimmingCharacters(in: .whitespaces)) ?? 0
        var maxP = Int(t.getString("more_settings", "ed_bpyz_zl_max").trimmingCharacters(in: .whitespaces)) ?? 0
        // 悬浮窗：未填战力时放宽区间
        if minP == 0 && maxP == 0 {
            minP = 0
            maxP = 9_999_999
            onLog("未填战力，默认 0–9999999")
        }
        onLog("帮派远征开始（战力\(minP)–\(maxP)）")
        for i in 0..<15 {
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "factionarmy", extra: ["op": "getPointAward", "point_id": "\(i)"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = (CombatLog.jsonField(r, "msg") ?? "").ifBlankMe(CombatLog.fromBody(r))
            if !msg.isEmpty && !msg.contains("没有") && !msg.contains("已领") {
                onLog("节点\(i):\(msg)")
            }
        }
        for i in 0..<5 {
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "factionarmy", extra: ["op": "getIslandAward", "island_id": "\(i)"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = (CombatLog.jsonField(r, "msg") ?? "").ifBlankMe(CombatLog.fromBody(r))
            if !msg.isEmpty && !msg.contains("没有") && !msg.contains("已领") {
                onLog("岛屿\(i):\(msg)")
            }
        }
        var fights = 0
        let (_, index) = await LedouCGI.getPetPk(
            cmd: "factionarmy", extra: ["island_id": "-1", "op": "viewIndex"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let idxMsg = CombatLog.jsonField(index, "msg") ?? ""
        if !idxMsg.isEmpty { onLog(idxMsg) }
        if index.contains("revive"),
           (try? NSRegularExpression(pattern: #""revive"\s*:\s*"?([1-9]\d*)""#))?
            .firstMatch(in: index, range: NSRange(index.startIndex..., in: index)) != nil
        {
            onLog("当前状态不能挑战")
            return "不能挑战"
        }
        guard let pointId = firstMatch(index, #""pointStatus"\s*:\s*"?1"?[^}]*"pointId"\s*:\s*"?(\d+)""#)
            ?? firstMatch(index, #""pointId"\s*:\s*"?(\d+)"?[^}]*"pointStatus"\s*:\s*"?1""#)
        else {
            onLog("没有找到需要挑战的帮派")
            return "无可挑战点"
        }
        onLog("挑战点\(pointId)")
        var page = 1
        let hi = max(maxP, minP)
        while fights < 8 && page <= 6 {
            if Task.isCancelled { break }
            let (_, view) = await LedouCGI.getPetPk(
                cmd: "factionarmy",
                extra: ["point_id": pointId, "op": "viewpoint", "page": "\(page)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if let opp = firstOppInPower(view, minP: minP, maxP: hi) {
                let (_, f) = await LedouCGI.getPetPk(
                    cmd: "factionarmy",
                    extra: ["point_id": pointId, "opp_uin": opp, "op": "fightWithUsr"],
                    cookie: cookie
                )
                fights += 1
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("[\(opp)]\((CombatLog.jsonField(f, "msg") ?? "").ifBlankMe(CombatLog.fromBody(f).ifBlankMe("挑战")))")
                if f.contains("体力") || (f.contains("次数") && f.contains("不足")) { break }
                continue
            }
            let pages = CombatLog.jsonInt(view, "totalPages") ?? page
            if page >= pages {
                onLog("没有找到需要挑战的人员")
                break
            }
            page += 1
        }
        return "远征战斗\(fights)"
    }

    static func farmHuangJinLianSai(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var minP = Int(t.getString("more_settings", "ed_hjls_zl_min").trimmingCharacters(in: .whitespaces)) ?? 0
        var maxP = Int(t.getString("more_settings", "ed_hjls_zl_max").trimmingCharacters(in: .whitespaces)) ?? 0
        if minP == 0 && maxP == 0 {
            minP = 0
            maxP = 9_999_999
            onLog("未填战力，默认 0–9999999")
        }
        onLog("黄金联赛开始（战力\(minP)–\(maxP)）")
        var fights = 0
        let hi = max(maxP, minP)
        for _ in 0..<8 {
            if Task.isCancelled { break }
            let (_, page) = await LedouCGI.getPetPk(
                cmd: "factionleague", extra: ["op": "2"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if let result = CombatLog.jsonInt(page, "result"), result != 0 {
                onLog((CombatLog.jsonField(page, "msg") ?? "").ifBlankMe("联赛查询失败"))
                return "查询失败"
            }
            guard let uin = firstLeagueOpp(page, minP: minP, maxP: hi) else {
                onLog("没有符合条件的对手")
                return "黄金联赛战斗\(fights)"
            }
            let (_, f) = await LedouCGI.getPetPk(
                cmd: "factionleague", extra: ["op": "4", "opp_uin": uin], cookie: cookie
            )
            fights += 1
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("[\(uin)]\((CombatLog.jsonField(f, "msg") ?? "").ifBlankMe(CombatLog.fromBody(f).ifBlankMe("挑战")))")
        }
        return "黄金联赛战斗\(fights)"
    }

    static func farmChangMeng(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        var allMax = t.getBool("more_settings", "cb_fb_max_all")
        var one = t.getBool("more_settings", "cb_fb_count_1")
        var max = t.getBool("more_settings", "cb_fb_count_max")
        if !allMax && !one && !max {
            one = true
            onLog("未勾选次数，默认只刷一次")
        }
        let preferFight = !t.getBool("more_settings", "rb_fb_type_2")
        let stopOnLose = !t.getBool("more_settings", "rb_fb_zhan_bai_2")
        let mode: String = {
            if allMax { return "刷完所有副本" }
            if one { return "只刷一次" }
            return "刷完单副本"
        }()
        onLog("长梦副本开始（\(mode)，\(preferFight ? "优先战斗" : "优先奇遇")）")
        let (_, list) = await LedouCGI.getPetPk(
            cmd: "jianghudream", extra: ["op": "showCopyInfo"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let copies = parseDreamCopies(list)
        let running = copies.filter { $0.2 == 2 }
        let ready = copies.filter { $0.2 == 1 }
        let targets: [(String, String, Int)] = {
            if !running.isEmpty { return Array(running.prefix(1)) }
            if allMax { return ready }
            return Array(ready.prefix(1))
        }()
        if targets.isEmpty {
            let msg = (CombatLog.jsonField(list, "msg") ?? "").ifBlankMe(CombatLog.fromBody(list))
            onLog(msg.ifBlankMe("没有可打副本"))
            return "无副本"
        }
        var steps = 0
        for (id, name, _) in targets {
            onLog("开启副本 \(name)")
            var begun = await LedouCGI.getPetPk(
                cmd: "jianghudream",
                extra: ["op": "beginInstance", "copyid": id],
                cookie: cookie
            ).1
            try? await Task.sleep(nanoseconds: gapNs)
            onLog((CombatLog.jsonField(begun, "msg") ?? "").ifBlankMe("已请求开本"))
            let cap = (one && !allMax && !max) ? 1 : 24
            var inner = 0
            while inner < cap && steps < 40 {
                inner += 1
                steps += 1
                if Task.isCancelled { break }
                let day = CombatLog.jsonInt(begun, "curDays")
                let maxDay = CombatLog.jsonInt(begun, "maxDays")
                let line = (CombatLog.jsonField(begun, "msg") ?? "").ifBlankMe(CombatLog.fromBody(begun))
                if !line.isEmpty && inner > 1 {
                    onLog("第\(day.map(String.init) ?? "?")天 \(line)")
                }
                if begun.contains("香炉") && begun.contains("不足") {
                    onLog("香炉数量不足")
                    return "长梦\(steps)"
                }
                if line.contains("战败") || begun.contains("\"win\":0") || begun.contains("\"win\":\"0\"") {
                    if stopOnLose {
                        let (_, end) = await LedouCGI.getPetPk(
                            cmd: "jianghudream", extra: ["op": "endInstance"], cookie: cookie
                        )
                        try? await Task.sleep(nanoseconds: gapNs)
                        onLog(CombatLog.fromBody(end).ifBlankMe("战败后停止"))
                        return "长梦\(steps)"
                    }
                    _ = await LedouCGI.getPetPk(
                        cmd: "jianghudream", extra: ["op": "endInstance"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog("战败后重开")
                    begun = await LedouCGI.getPetPk(
                        cmd: "jianghudream",
                        extra: ["op": "beginInstance", "copyid": id],
                        cookie: cookie
                    ).1
                    try? await Task.sleep(nanoseconds: gapNs)
                    continue
                }
                if !preferFight && begun.contains("eventChoose") {
                    let adv = firstMatch(begun, #""id"\s*:\s*"?(\d+)""#) ?? "0"
                    begun = await LedouCGI.getPetPk(
                        cmd: "jianghudream",
                        extra: ["op": "chooseAdventure", "adventure_id": adv],
                        cookie: cookie
                    ).1
                    try? await Task.sleep(nanoseconds: gapNs)
                    continue
                }
                if let day, let maxDay, day >= maxDay {
                    let (_, reward) = await LedouCGI.getPetPk(
                        cmd: "jianghudream",
                        extra: ["op": "getFirstReward", "copyid": id],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(reward).ifBlankMe("领首通"))
                    let (_, end) = await LedouCGI.getPetPk(
                        cmd: "jianghudream", extra: ["op": "endInstance"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(end).ifBlankMe("副本结束"))
                    break
                }
                begun = await LedouCGI.getPetPk(
                    cmd: "jianghudream", extra: ["op": "goNextDay"], cookie: cookie
                ).1
                try? await Task.sleep(nanoseconds: gapNs)
                if begun.contains("进入下一天异常") {
                    onLog("请手动结束该副本后再试")
                    return "长梦\(steps)"
                }
            }
            if one && !max && !allMax { break }
        }
        onLog("长梦副本结束")
        return "长梦\(steps)"
    }

    static func pcSuo(action: String, cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let pwd = (pendingPcPassword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let flagTrim = pendingPcFlag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let flagOverride: String? = {
            guard flagTrim.count == 11, flagTrim.allSatisfy({ $0 == "0" || $0 == "1" }) else { return nil }
            return flagTrim
        }()
        pendingPcPassword = nil
        pendingPcFlag = nil

        switch action {
        case "重置PC锁":
            onLog("申请强制解除 PC 锁（约 7 天）…")
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "safelock", extra: ["type": "2"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(r)
                .ifBlankMe((CombatLog.jsonField(r, "msg") ?? "").ifBlankMe("已请求 type=2"))
            onLog(msg)
            return msg
        case "PC解锁":
            if pwd.isEmpty {
                onLog("未输入密码")
                return "未输入密码"
            }
            let md5 = safelockMd5(pwd, cookie: cookie)
            onLog("PC解锁…")
            let (_, r) = await LedouCGI.getPetPk(
                cmd: "safelock", extra: ["type": "6", "md5": md5], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(r).ifBlankMe("已请求 type=6")
            onLog(msg)
            return msg
        case "修改PC锁", "设置PC锁密码":
            if pwd.isEmpty {
                onLog("未输入密码")
                return "未输入密码"
            }
            onLog("\(action)：查询当前锁定项…")
            let (_, q) = await LedouCGI.getPetPk(
                cmd: "safelock", extra: ["type": "1"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let flag = flagOverride ?? parseProtectedFlag(q) ?? "11111111111"
            let md5 = safelockMd5(pwd, cookie: cookie)
            if action == "设置PC锁密码" {
                onLog("设置密码 type=4…")
                let (_, set) = await LedouCGI.getPetPk(
                    cmd: "safelock",
                    extra: ["pwd": pwd, "md5": md5, "type": "4"],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog(CombatLog.fromBody(set).ifBlankMe("type=4 已请求"))
            }
            onLog("应用锁定项 type=7 flag=\(flag)…")
            let (_, apply) = await LedouCGI.getPetPk(
                cmd: "safelock",
                extra: ["type": "7", "protectedflag": flag, "md5": md5],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(apply).ifBlankMe("已请求 type=7")
            onLog(msg)
            return msg
        default:
            let tip = "未知 PC 锁操作：\(action)"
            onLog(tip)
            return tip
        }
    }

    private static func firstOppInPower(_ body: String, minP: Int, maxP: Int) -> String? {
        let re = try? NSRegularExpression(
            pattern: #""isDead"\s*:\s*"?0"?[^}]*"fightCapacity"\s*:\s*"?(\d+)"?[^}]*"oppUin"\s*:\s*"?(\d+)""#
        )
        let ns = body as NSString
        var hit: String?
        re?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m, m.numberOfRanges >= 3 else { return }
            let p = Int(ns.substring(with: m.range(at: 1))) ?? 0
            if p >= minP && p <= maxP {
                hit = ns.substring(with: m.range(at: 2))
                stop.pointee = true
            }
        }
        return hit
    }

    private static func firstLeagueOpp(_ body: String, minP: Int, maxP: Int) -> String? {
        let re = try? NSRegularExpression(
            pattern: #""uin"\s*:\s*"?(\d+)"?[^}]*"cur_hp"\s*:\s*"?(\d+)"?[^}]*"atk_power"\s*:\s*"?(\d+)""#
        )
        let ns = body as NSString
        var hit: String?
        re?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m, m.numberOfRanges >= 4 else { return }
            let hp = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let atk = Int(ns.substring(with: m.range(at: 3))) ?? 0
            if hp != 0 && atk >= minP && atk <= maxP {
                hit = ns.substring(with: m.range(at: 1))
                stop.pointee = true
            }
        }
        return hit
    }

    private static func parseDreamCopies(_ body: String) -> [(String, String, Int)] {
        var out: [(String, String, Int)] = []
        let ns = body as NSString
        let re1 = try? NSRegularExpression(
            pattern: #""id"\s*:\s*"?(\d+)"?[^}]*"name"\s*:\s*"([^"]*)"[^}]*"status"\s*:\s*"?(\d+)""#
        )
        re1?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 4 else { return }
            out.append((
                ns.substring(with: m.range(at: 1)),
                ns.substring(with: m.range(at: 2)),
                Int(ns.substring(with: m.range(at: 3))) ?? 0
            ))
        }
        if out.isEmpty {
            let re2 = try? NSRegularExpression(
                pattern: #""name"\s*:\s*"([^"]*)"[^}]*"status"\s*:\s*"?(\d+)"?[^}]*"id"\s*:\s*"?(\d+)""#
            )
            re2?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 4 else { return }
                out.append((
                    ns.substring(with: m.range(at: 3)),
                    ns.substring(with: m.range(at: 1)),
                    Int(ns.substring(with: m.range(at: 2))) ?? 0
                ))
            }
        }
        return out
    }

    private static func parseProtectedFlag(_ body: String) -> String? {
        if let f = firstMatch(body, #""protectedflag"\s*:\s*"([01]{11})""#) { return f }
        if let raw = firstMatch(body, #""protectedflag"\s*:\s*"([^"]+)""#) {
            let filtered = raw.filter { $0 == "0" || $0 == "1" }
            if filtered.count == 11 { return filtered }
        }
        return nil
    }

    private static func cookieSalt(_ cookie: String) -> String {
        LoginURLs.cookieValue(cookie, names: ["accessToken", "access_token", "openkey"]) ?? ""
    }

    private static func md5Hex(_ raw: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func safelockMd5(_ password: String, cookie: String) -> String {
        md5Hex(md5Hex(password) + cookieSalt(cookie))
    }

    // MARK: - 新春对联 / 道聚城

    static func farmXinChunDuiLian(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let raw = FeatureToggleStore.shared.getString("more_settings", "ed_xcdl_answers")
        let answers = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if answers.isEmpty {
            onLog("请去更多设置填写春联答案（每行：题目关键字|答案文本）")
            return "未设置答案"
        }
        onLog("新春对联开始（答案\(answers.count)条）")
        var answered = 0
        var rounds = 0
        while rounds < 20 {
            rounds += 1
            if Task.isCancelled { break }
            let (_, q) = await LedouCGI.getPetPk(
                cmd: "newAct", extra: ["subtype": "137", "op": "1"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(q)
            if q.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            if msg.contains("今日答题数已满") || q.contains("今日答题数已满") {
                onLog(msg.ifBlankMe("今日答题数已满"))
                break
            }
            if q.contains("\"result\"")
                && !q.contains("\"result\":0")
                && !q.contains("\"result\":\"0\"")
            {
                if !msg.isEmpty { onLog(msg) }
                break
            }
            let question = CombatLog.jsonField(q, "cur_question") ?? ""
            let status = CombatLog.jsonInt(q, "cur_status") ?? 0
            if status >= 3 || question.isEmpty {
                if !msg.isEmpty { onLog(msg) }
                break
            }
            let options = parseDuiLianOptions(q)
            var index: String?
            var pickedAns = ""
            for line in answers {
                let parts = line.split(separator: "|", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let key = parts.first ?? line
                let want = parts.count > 1 ? parts[1] : line
                if !line.contains(question) && !question.contains(key) { continue }
                for (opt, ans, idx) in options {
                    if line.contains(ans) || ans == want || opt == want || idx == want {
                        index = idx
                        pickedAns = "\(opt):\(ans)"
                        break
                    }
                }
                if index != nil { break }
                for (opt, ans, idx) in options {
                    if line.contains(question) && line.contains(ans) {
                        index = idx
                        pickedAns = "\(opt):\(ans)"
                        break
                    }
                }
                if index != nil { break }
            }
            guard let index else {
                onLog("题目：\(question) ，答案不全，请去设置春联答案")
                break
            }
            onLog("题目：\(question) ，答案：\(pickedAns)")
            let (_, submit) = await LedouCGI.getPetPk(
                cmd: "newAct",
                extra: ["op": "3", "subtype": "137", "index": index],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let smsg = CombatLog.fromBody(submit)
            if !smsg.isEmpty { onLog(smsg) }
            if submit.contains("系统繁忙") { continue }
            if submit.contains("\"result\":0") || submit.contains("\"result\":\"0\"")
                || smsg.contains("正确") || smsg.contains("成功") || smsg.isEmpty
            {
                answered += 1
                let (_, next) = await LedouCGI.getPetPk(
                    cmd: "newAct", extra: ["subtype": "137", "op": "2"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let nmsg = CombatLog.fromBody(next)
                if !nmsg.isEmpty { onLog(nmsg) }
            } else {
                break
            }
        }
        for id in 1...3 {
            let (_, claim) = await LedouCGI.getPetPk(
                cmd: "newAct",
                extra: ["op": "4", "subtype": "137", "id": "\(id)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let cmsg = CombatLog.fromBody(claim)
            if !cmsg.isEmpty { onLog(cmsg) }
        }
        onLog("新春对联结束")
        return "新春对联答\(answered)"
    }

    /// 掌上道聚城：独立 Cookie（扫码道聚城），不使用大乐斗 cookie。
    static func farmDaoJuCheng(cookie: String, onLog: @escaping (String) -> Void) async -> String {
        _ = cookie
        return await DaoJuActions.farm(onLog: onLog)
    }

    // MARK: - 换装

    /// 应用装扮方案 id（phonepk outfit op=1）。
    static func applyOutfitPlan(
        planId: Int,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let id = max(1, min(5, planId))
        onLog("应用装扮方案\(id)…")
        let (_, body) = await LedouCGI.getPhonePk(
            cmd: "outfit", extra: ["op": "1", "id": "\(id)"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(body).ifBlankMe(LedouCGI.shortBody(body, code: 200))
        onLog("装扮\(id):\(msg.ifBlankMe("已请求"))")
        return "装扮\(id)"
    }

    /// 真源：`farmYiJianHuanZhuang` — 装扮槽 + 可选星盘（星盘镶嵌下一切片再加深）。
    static func farmYiJianHuanZhuang(
        onLog: @escaping (String) -> Void
    ) async -> String {
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            onLog("请先登录")
            return "未登录"
        }
        let t = FeatureToggleStore.shared
        let plan = (1...5).first(where: { t.getBool("huoyue", "rb_yjhz_\($0)") }) ?? 1
        onLog("一键自动换装 方案\(plan)")
        var parts: [String] = []
        parts.append(await applyOutfitPlan(planId: plan, cookie: cookie, onLog: onLog))
        if t.getBool("huoyue", "cb_yjhz_xp") {
            onLog("星盘换装：请先在活跃设置填写目标数；完整镶嵌循环下一切片接入")
            parts.append("星盘待加深")
        }
        onLog("神将/佣兵/专精/头像等方案编辑器尚未接入，已跳过")
        return parts.joined(separator: "；")
    }

    private static func parseDuiLianOptions(_ body: String) -> [(String, String, String)] {
        var out: [(String, String, String)] = []
        let ns = body as NSString
        let re1 = try? NSRegularExpression(
            pattern: #"\{[^{}]*"option"\s*:\s*"([^"]*)"[^{}]*"answer"\s*:\s*"([^"]*)"[^{}]*"index"\s*:\s*"?(\d+)"?[^{}]*\}"#
        )
        re1?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 4 else { return }
            out.append((
                ns.substring(with: m.range(at: 1)),
                ns.substring(with: m.range(at: 2)),
                ns.substring(with: m.range(at: 3))
            ))
        }
        if out.isEmpty {
            let re2 = try? NSRegularExpression(
                pattern: #"\{[^{}]*"answer"\s*:\s*"([^"]*)"[^{}]*"option"\s*:\s*"([^"]*)"[^{}]*"index"\s*:\s*"?(\d+)"?[^{}]*\}"#
            )
            re2?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 4 else { return }
                out.append((
                    ns.substring(with: m.range(at: 2)),
                    ns.substring(with: m.range(at: 1)),
                    ns.substring(with: m.range(at: 3))
                ))
            }
        }
        return out
    }

    // MARK: - helpers

    private static func parseExchangeNameTypes(_ body: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let ns = body as NSString
        let re1 = try? NSRegularExpression(
            pattern: #"\{[^{}]*"name"\s*:\s*"([^"]*)"[^{}]*"type"\s*:\s*"?([^",}\s]+)[^{}]*\}"#
        )
        re1?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 3 else { return }
            out.append((ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2))))
        }
        if out.isEmpty {
            let re2 = try? NSRegularExpression(
                pattern: #"\{[^{}]*"type"\s*:\s*"?([^",}\s]+)[^{}]*"name"\s*:\s*"([^"]*)"[^{}]*\}"#
            )
            re2?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 3 else { return }
                out.append((ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 1))))
            }
        }
        return out
    }

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
