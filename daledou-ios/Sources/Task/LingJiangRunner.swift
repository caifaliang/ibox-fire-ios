import Foundation

/// 一键领奖（真源 `LingJiangRunner.kt` — 本切片：URL/urlList/简单格式化）。
@MainActor
final class LingJiangRunner: ObservableObject {
    static let shared = LingJiangRunner()

    @Published private(set) var running = false
    private let store = LingJiangStore.shared
    private let log = TaskLogStore.shared
    private var job: Task<Void, Never>?
    private var lastBody = ""

    private init() {}

    func stop() {
        job?.cancel()
        job = nil
        running = false
        log.setRunning(false)
        log.append("领奖", "已停止")
    }

    func start(cookie: String) {
        guard !running else {
            log.append("领奖", "已在运行中")
            return
        }
        guard LoginURLs.hasGameSession(cookie) else {
            log.append("领奖", "请先登录")
            return
        }
        job = Task { await runAll(cookie: cookie) }
    }

    private func runAll(cookie: String) async {
        running = true
        log.setRunning(true, name: "一键领奖")
        defer {
            running = false
            log.setRunning(false)
            job = nil
        }
        log.append("领奖", "--开始")
        let catalog = LingJiangCatalog.items()
        if catalog.isEmpty {
            log.append("领奖", "协议表未加载（检查 lingjiang_keymap.json）")
            log.append("领奖", "--完成")
            return
        }
        var ok = 0, skip = 0, fail = 0
        let (week, hour) = notesWeekHour()
        for item in catalog {
            if Task.isCancelled { break }
            guard store.shouldRun(protocolKey: item.key) else { continue }
            let title = item.title.isEmpty ? item.key : item.title
            if !LingJiangUrlResolver.oneClickAllowed(type: item.type, week: week, hour: hour) {
                log.append(title, "不在可执行时段，已跳过")
                skip += 1
                continue
            }
            switch await executeItem(item, title: title, cookie: cookie) {
            case .ok: ok += 1
            case .skip: skip += 1
            case .loginFail:
                log.append("领奖", "--中止：登陆校验失败，请重新一键登陆")
                return
            case .busyRetry: fail += 1
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        log.append("领奖", "--完成（成功 \(ok) / 跳过 \(skip) / 失败 \(fail)）")
    }

    private func executeItem(_ item: LingJiangItem, title: String, cookie: String) async -> LingJiangStepOutcome {
        if title.contains("神将月卡") {
            log.append(title, "请手动领取【神将月卡】")
            return .skip
        }
        switch item.key {
        case "DayDdYueKa":
            return await executeUseGoods(title, goodsId: "3645", times: 1, cookie: cookie)
        case "JY_MT":
            return await executeUseGoods(title, goodsId: "3178", times: 10, cookie: cookie)
        case "FeiShengBaoMing":
            return await executeFeiShengBaoMing(title, cookie: cookie)
        case "DianFengBaoMing":
            return await executeDianFengBaoMing(title, cookie: cookie)
        case "JieBaiBaoMing":
            return await executeJieBaiBaoMing(title, cookie: cookie)
        case "MengZhuBaoMing":
            return await executeMengZhuBaoMing(title, cookie: cookie)
        case "ShangHuiShangDian":
            return await executeShangHuiShangDian(title, item: item, cookie: cookie)
        case "ShangHuiJiaoYi":
            return await executeShangHuiJiaoYi(title, item: item, cookie: cookie)
        case "login_dh":
            return await executeLoginDh(title, cookie: cookie)
        case "MenPaiYaoQing":
            return await executeQqList(
                title,
                baseUrls: [
                    "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=secttournament&op=signup",
                ],
                qqKey: "ed_menpai_yaoqing",
                cookie: cookie
            ) { qq in
                "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=secttournament&op=invite&invitee_type=1&invitee=\(qq)"
            }
        case "MenPaiJinZu":
            return await executeQqList(
                title,
                baseUrls: [
                    "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=secttournament&op=signup",
                ],
                qqKey: "ed_menpai_jinzu",
                requireQq: true,
                cookie: cookie
            ) { qq in
                "https://fight.pet.qq.com/cgi-bin/petpk?cmd=secttournament&op=acceptinvite&inviter=\(qq)"
            }
        case "YiJiYaoQing":
            return await executeQqList(
                title, baseUrls: [], qqKey: "ed_yiji_yaoqing", requireQq: true, cookie: cookie
            ) { qq in
                "https://fight.pet.qq.com/cgi-bin/petpk?cmd=spacerelic&op=invitefriends&opp_uin=\(qq)"
            }
        case "YiJiJinZu":
            return await executeQqList(
                title, baseUrls: [], qqKey: "ed_yiji_jinzu", requireQq: true, cookie: cookie
            ) { qq in
                "https://fight.pet.qq.com/cgi-bin/petpk?cmd=spacerelic&op=acceptivt&opp_uin=\(qq)"
            }
        case "JieBaiZhuWei":
            let plan = LingJiangUrlResolver.plan(item)
            if let first = plan.formatFirst, let second = plan.formatSecondTemplate {
                return await executeFormat(title, first: first, secondTemplate: second, cookie: cookie)
            }
            log.append(title, "无可用 URL，跳过")
            return .skip
        default:
            break
        }
        let plan = LingJiangUrlResolver.plan(item)
        if let first = plan.formatFirst, let second = plan.formatSecondTemplate {
            return await executeFormat(title, first: first, secondTemplate: second, cookie: cookie)
        }
        if plan.urls.isEmpty {
            log.append(title, "无可用 URL，跳过")
            return .skip
        }
        var last: LingJiangStepOutcome = .ok
        for url in plan.urls {
            last = await executeUrl(title, url: url, cookie: cookie)
            if last == .loginFail { return last }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        if (item.checkboxKey == "cb_day_xl_6" || item.checkboxKey == "cb_day_xl_18"),
           store.on("cb_day_xl_zdtz")
        {
            _ = await executeUrl(
                "【巡礼自动挑战】",
                url: "https://fight.pet.qq.com/cgi-bin/petpk?cmd=abyss_tide&op=addaccess",
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: 80_000_000)
            _ = await executeUrl(
                "【巡礼自动挑战】",
                url: "https://fight.pet.qq.com/cgi-bin/petpk?cmd=abyss_tide&op=beginfight",
                cookie: cookie
            )
        }
        return last
    }

    private func executeFormat(
        _ title: String, first: String, secondTemplate: String, cookie: String
    ) async -> LingJiangStepOutcome {
        if title.contains("武林报名"), first.contains("%d") || first.contains("%s") {
            return await executeWuLinBaoMing(title, first: first, secondTemplate: secondTemplate, cookie: cookie)
        }
        if first.contains("%d") || first.contains("%s") {
            log.append(title, "报名参数未设置（赛区），已跳过")
            return .skip
        }
        let firstOut = await executeUrl(title, url: first, cookie: cookie)
        if firstOut == .loginFail { return firstOut }
        if secondTemplate == "auto" || !secondTemplate.hasPrefix("http") {
            log.append(title, "后续步骤需要回包分支，已只完成查询")
            return .skip
        }
        guard let second = LingJiangUrlResolver.fillFormat(template: secondTemplate, body: lastBody) else {
            log.append(title, "首响里没有可用参数，已跳过后续")
            return .skip
        }
        return await executeUrl(title, url: second, cookie: cookie)
    }

    // MARK: - 复杂报名

    private func executeFeiShengBaoMing(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let t = FeatureToggleStore.shared
        let sp = store.on("cb_feisheng_baoming_sp")
        let urls: [String]
        if t.getBool("lingjiang", "rb_feisheng_suiji", default: true) {
            let alt = sp
                ? "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=ascendheaven&op=signup&type=3"
                : "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=ascendheaven&op=signup&type=1"
            urls = [
                "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=ascendheaven&op=signup&type=2",
                alt,
            ]
        } else if t.getBool("lingjiang", "rb_feisheng_paiwei", default: false) {
            urls = [
                sp
                    ? "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=ascendheaven&op=signup&type=3"
                    : "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=ascendheaven&op=signup&type=1",
            ]
        } else {
            urls = [
                "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=ascendheaven&op=signup&type=2",
            ]
        }
        return await runUrlList(title, urls: urls, cookie: cookie)
    }

    private func executeDianFengBaoMing(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let t = FeatureToggleStore.shared
        let group: Int = {
            if t.getBool("lingjiang", "rb_dianfeng_bei", default: false) { return 1 }
            if t.getBool("lingjiang", "rb_dianfeng_suiji", default: false) { return 2 }
            return 0
        }()
        let url =
            "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=gvg&sub=1&group=\(group)&check=1"
        return await executeUrl(title, url: url, cookie: cookie)
    }

    private func executeJieBaiBaoMing(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let t = FeatureToggleStore.shared
        let gid: String = {
            if t.getBool("lingjiang", "rb_jb_bm_1", default: false) { return "1" }
            if t.getBool("lingjiang", "rb_jb_bm_2", default: false) { return "2" }
            if t.getBool("lingjiang", "rb_jb_bm_3", default: false) { return "3" }
            if t.getBool("lingjiang", "rb_jb_bm_5", default: false) { return "5" }
            return "4"
        }()
        let url =
            "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?zapp_uin=&B_UID=0&sid=&channel=0&g_ut=1&cmd=brofight&subtype=1&gidIdx=\(gid)"
        return await executeUrl(title, url: url, cookie: cookie)
    }

    private func executeMengZhuBaoMing(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let t = FeatureToggleStore.shared
        let ground: Int = {
            if t.getBool("lingjiang", "rb_mengzhu_baiyin", default: false) { return 2 }
            if t.getBool("lingjiang", "rb_mengzhu_qingtong", default: false) { return 3 }
            return 1
        }()
        let url =
            "https://fight.pet.qq.com/cgi-bin/petpk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=wlmz&op=signup&ground_id=\(ground)"
        return await executeUrl(title, url: url, cookie: cookie)
    }

    private func executeShangHuiShangDian(
        _ title: String, item: LingJiangItem, cookie: String
    ) async -> LingJiangStepOutcome {
        let forced = FeatureToggleStore.shared.getString("lingjiang", "ed_shanghui_shangdian")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !forced.isEmpty {
            let first = await executeUrl(
                title,
                url: "https://fight.pet.qq.com/cgi-bin/petpk?cmd=fac_corp&op=2",
                cookie: cookie
            )
            if first == .loginFail { return first }
            try? await Task.sleep(nanoseconds: 80_000_000)
            return await executeUrl(
                title,
                url: "https://fight.pet.qq.com/cgi-bin/petpk?cmd=fac_corp&op=5&type_id=\(forced)",
                cookie: cookie
            )
        }
        let plan = LingJiangUrlResolver.plan(item)
        if let first = plan.formatFirst, let second = plan.formatSecondTemplate {
            return await executeFormat(title, first: first, secondTemplate: second, cookie: cookie)
        }
        log.append(title, "无可用 URL，跳过")
        return .skip
    }

    private func executeShangHuiJiaoYi(
        _ title: String, item: LingJiangItem, cookie: String
    ) async -> LingJiangStepOutcome {
        let raw = FeatureToggleStore.shared.getString("lingjiang", "ed_shanghui_jiaoyi")
        let ids = raw
            .components(separatedBy: CharacterSet(charactersIn: ",，\n "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !ids.isEmpty {
            var last = await executeUrl(
                title,
                url: "https://fight.pet.qq.com/cgi-bin/petpk?cmd=fac_corp&op=1",
                cookie: cookie
            )
            if last == .loginFail { return last }
            for id in ids {
                try? await Task.sleep(nanoseconds: 80_000_000)
                last = await executeUrl(
                    title,
                    url: "https://fight.pet.qq.com/cgi-bin/petpk?cmd=fac_corp&goods_id=\(id)&op=4&type=1",
                    cookie: cookie
                )
                if last == .loginFail { return last }
            }
            return last
        }
        let plan = LingJiangUrlResolver.plan(item)
        if let first = plan.formatFirst, let second = plan.formatSecondTemplate {
            return await executeFormat(title, first: first, secondTemplate: second, cookie: cookie)
        }
        log.append(title, "请填写商品ID或等回包可解析，已跳过")
        return .skip
    }

    private func executeLoginDh(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        var typeId = FeatureToggleStore.shared.getString("lingjiang", "ed_login_dh_type", default: "1221")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if typeId.isEmpty { typeId = "1221" }
        let first = await executeUrl(
            title,
            url: "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?zapp_uin=&B_UID=0&sid=&channel=0&g_ut=1&cmd=newAct&subtype=52",
            cookie: cookie
        )
        if first == .loginFail { return first }
        let times = CombatLog.jsonField(lastBody, "times")
            ?? CombatLog.jsonInt(lastBody, "times").map(String.init)
            ?? CombatLog.jsonField(lastBody, "left_times")
            ?? "1"
        try? await Task.sleep(nanoseconds: 80_000_000)
        return await executeUrl(
            title,
            url: "https://fight.pet.qq.com/cgi-bin/petpk?cmd=exchange&subtype=2&type=\(typeId)&times=\(times)",
            cookie: cookie
        )
    }

    private func executeQqList(
        _ title: String,
        baseUrls: [String],
        qqKey: String,
        requireQq: Bool = false,
        cookie: String,
        eachUrl: (String) -> String
    ) async -> LingJiangStepOutcome {
        let qqLines = FeatureToggleStore.shared.getString("lingjiang", qqKey)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        if requireQq && qqLines.isEmpty {
            log.append(title, "请先在领奖设置填写 QQ，已跳过")
            return .skip
        }
        let urls = baseUrls + qqLines.map(eachUrl)
        if urls.isEmpty {
            log.append(title, "无可用 URL，跳过")
            return .skip
        }
        return await runUrlList(title, urls: urls, cookie: cookie)
    }

    private func executeWuLinBaoMing(
        _ title: String, first: String, secondTemplate: String, cookie: String
    ) async -> LingJiangStepOutcome {
        let t = FeatureToggleStore.shared
        let level = t.getString("chaqu", "wlbm_type", default: "16")
            .filter(\.isNumber)
        let levelUse = level.isEmpty ? "16" : level
        let firstUrl = first.contains("%d") ? first.replacingOccurrences(of: "%d", with: levelUse) : first
        let firstOut = await executeUrl(title, url: firstUrl, cookie: cookie)
        if firstOut == .loginFail { return firstOut }
        guard let rawId = pickWuLinId(lastBody), rawId.count == 8 else {
            log.append(title, "showwulin 无可用赛区 id，已跳过")
            return .skip
        }
        let phone = title.contains("手机")
        let forced = (phone
            ? t.getString("chaqu", "wlbm_saiqu_phone")
            : t.getString("chaqu", "wlbm_saiqu_pc"))
            .trimmingCharacters(in: .whitespaces)
        let saiqu: String = {
            if forced.count == 2, forced.allSatisfy(\.isNumber) { return forced }
            return phone
                ? ["06", "07", "08", "09"].randomElement()!
                : ["01", "02", "03", "04", "05"].randomElement()!
        }()
        let signupId = String(rawId.prefix(4)) + saiqu + String(rawId.suffix(2))
        let names: [String: String] = phone
            ? ["06": "五指山", "07": "马栏坡", "08": "女儿国", "09": "水帘洞"]
            : ["01": "华东", "02": "华西", "03": "华中", "04": "华南", "05": "华北"]
        log.append(title, "预计赛区-\(names[saiqu] ?? saiqu) id=\(signupId)")
        var second: String
        if secondTemplate.contains("%s") {
            if let r = secondTemplate.range(of: "%s") {
                second = secondTemplate
                second.replaceSubrange(r, with: signupId)
            } else {
                second = secondTemplate
            }
        } else if let filled = LingJiangUrlResolver.fillFormat(template: secondTemplate, body: lastBody) {
            second = filled
        } else {
            log.append(title, "报名 URL 无法填充")
            return .skip
        }
        if levelUse == "9", !second.contains("qsinginwl") {
            second += second.contains("?") ? "&cmd=qsinginwl" : "?cmd=qsinginwl"
        }
        return await executeUrl(title, url: second, cookie: cookie)
    }

    private func pickWuLinId(_ body: String) -> String? {
        if let re = try? NSRegularExpression(pattern: #""id"\s*:\s*"(\d{8})""#),
           let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let r = Range(m.range(at: 1), in: body)
        {
            return String(body[r])
        }
        return nil
    }

    private func runUrlList(
        _ title: String, urls: [String], cookie: String
    ) async -> LingJiangStepOutcome {
        var last: LingJiangStepOutcome = .ok
        for url in urls {
            last = await executeUrl(title, url: url, cookie: cookie)
            if last == .loginFail { return last }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return last
    }

    private func executeUseGoods(
        _ title: String, goodsId: String, times: Int, cookie: String
    ) async -> LingJiangStepOutcome {
        let qq = LoginURLs.cookieValue(cookie, names: ["uin", "p_uin", "newuin"])?
            .filter(\.isNumber) ?? ""
        guard !qq.isEmpty else {
            log.append(title, "无QQ，跳过")
            return .skip
        }
        var last: LingJiangStepOutcome = .ok
        let n = min(max(times, 1), 20)
        for i in 0..<n {
            let url = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=use&selfuin=\(qq)&id=\(goodsId)"
            last = await executeUrl(title, url: url, cookie: cookie, silentOk: n > 1 && i < n - 1)
            if last == .loginFail || last != .ok { return last }
            if i < n - 1 { try? await Task.sleep(nanoseconds: 80_000_000) }
        }
        if n > 1 { log.append(title, "已使用 \(n) 次") }
        return last
    }

    private func executeUrl(
        _ title: String,
        url: String,
        cookie: String,
        silentOk: Bool = false
    ) async -> LingJiangStepOutcome {
        guard let u = URL(string: url), LedouCGI.isAllowedHost(u.host) else {
            log.append(title, "非法 URL，跳过")
            return .skip
        }
        let (_, body) = await LedouCGI.get(url: u, cookie: cookie)
        lastBody = body
        if body.contains("登陆校验失败") || body.contains("请先登录") {
            log.append(title, "会话失效")
            return .loginFail
        }
        if body.contains("系统繁忙") || body.contains("操作频繁") {
            if !silentOk { log.append(title, "系统繁忙") }
            return .busyRetry
        }
        let msg = CombatLog.fromBody(body)
        if !silentOk {
            log.append(title, msg.isEmpty ? "已请求" : msg)
        }
        return .ok
    }

    /// 笔记 H1：周一=1 … 周日=7（GMT+8）
    private func notesWeekHour() -> (Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let w = cal.component(.weekday, from: now)
        let mon1 = w == 1 ? 7 : w - 1
        let h = cal.component(.hour, from: now)
        return (mon1, h)
    }
}
