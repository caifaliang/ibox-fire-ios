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
        // 动态项：本切片走 URL 表；复杂报名后续补
        switch item.key {
        case "DayDdYueKa":
            return await executeUseGoods(title, goodsId: "3645", times: 1, cookie: cookie)
        case "JY_MT":
            return await executeUseGoods(title, goodsId: "3178", times: 10, cookie: cookie)
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
