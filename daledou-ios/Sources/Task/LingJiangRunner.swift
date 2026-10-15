import Foundation

/// 一键领奖串行引擎（M14）：对齐 Android LingJiangRunner 主路径。
@MainActor
final class LingJiangRunner: ObservableObject {
    static let shared = LingJiangRunner()

    @Published private(set) var running = false

    private let store = LingJiangStore.shared
    private let log = TaskLogStore.shared
    private var job: Task<Void, Never>?

    private static let gapNs: UInt64 = 200_000_000
    private static let maxBusyRetry = 3

    private init() {}

    func stop() {
        job?.cancel()
        job = nil
        running = false
        log.append("一键领奖", "已停止")
    }

    func start(cookie: String) {
        guard !running else {
            log.append("一键领奖", "已在运行中")
            return
        }
        guard LoginURLs.hasGameSession(cookie) else {
            log.append("一键领奖", "请先登录")
            return
        }
        job = Task { await runQueue(cookie: cookie) }
    }

    func runOnceAwait(cookie: String) async -> String {
        if running {
            log.append("一键领奖", "已在运行中，本轮跳过")
            return "领奖运行中，已跳过"
        }
        guard LoginURLs.hasGameSession(cookie) else {
            log.append("一键领奖", "请先登录")
            return "未登陆"
        }
        await runQueue(cookie: cookie)
        return "领奖编排完成"
    }

    private func runQueue(cookie: String) async {
        running = true
        defer { running = false; job = nil }
        log.append("一键领奖", "--开始")
        let catalog = LingJiangCatalog.items()
        if catalog.isEmpty {
            log.append("一键领奖", "协议表未加载（检查 Bundle lingjiang_keymap.json）")
            log.append("一键领奖", "--完成")
            return
        }
        var ok = 0, skip = 0, fail = 0
        let (week, hour) = Self.notesWeekHour()
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
            case .busyRetry: fail += 1
            case .loginFail:
                log.append("一键领奖", "--中止：登陆校验失败，请重新登录")
                return
            }
            try? await Task.sleep(nanoseconds: Self.gapNs)
        }
        log.append("一键领奖", "--完成（成功 \(ok) / 跳过 \(skip) / 失败 \(fail)）")
    }

    private func executeItem(_ item: LingJiangItem, title: String, cookie: String) async -> LingJiangStepOutcome {
        if title == "【神将月卡】" {
            log.append(title, "请手动领取【神将月卡】")
            return .skip
        }
        switch item.key {
        case "DayDdYueKa":
            return await executeUseGoods(title, goodsId: "3645", times: 1, cookie: cookie)
        case "JY_MT":
            return await executeUseGoods(title, goodsId: "3178", times: 10, cookie: cookie)
        case "FeiShengBaoMing":
            return await executeFeiSheng(title, cookie: cookie)
        case "DianFengBaoMing":
            return await executeDianFeng(title, cookie: cookie)
        case "JieBaiBaoMing":
            return await executeJieBai(title, cookie: cookie)
        case "MengZhuBaoMing":
            return await executeMengZhu(title, cookie: cookie)
        case "MenPaiYaoQing", "MenPaiJinZu", "YiJiJinZu":
            log.append(title, "需填写 QQ 列表，本切片跳过")
            return .skip
        default:
            break
        }

        let plan = LingJiangUrlResolver.plan(item)
        if let first = plan.formatFirst, let tmpl = plan.formatSecondTemplate {
            return await executeFormat(title, first: first, template: tmpl, cookie: cookie)
        }
        let urls = plan.urls
        if urls.isEmpty {
            log.append(title, "无可用 URL，跳过")
            return .skip
        }
        var last: LingJiangStepOutcome = .ok
        for url in urls {
            last = await executeUrl(title, url: url, cookie: cookie)
            if last == .loginFail { return last }
            try? await Task.sleep(nanoseconds: Self.gapNs)
        }
        return last
    }

    private func executeFeiSheng(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let toggles = FeatureToggleStore.shared
        let sp = store.isChecked("cb_feisheng_baoming_sp")
        let urls: [String]
        if toggles.getBool("lingjiang", "rb_feisheng_paiwei", default: false) {
            let t = sp ? "3" : "1"
            urls = ["https://fight.pet.qq.com/cgi-bin/petpk?cmd=ascendheaven&op=signup&type=\(t)"]
        } else {
            let alt = sp ? "3" : "1"
            urls = [
                "https://fight.pet.qq.com/cgi-bin/petpk?cmd=ascendheaven&op=signup&type=2",
                "https://fight.pet.qq.com/cgi-bin/petpk?cmd=ascendheaven&op=signup&type=\(alt)",
            ]
        }
        var last: LingJiangStepOutcome = .ok
        for url in urls {
            last = await executeUrl(title, url: url, cookie: cookie)
            if last == .loginFail { return last }
            try? await Task.sleep(nanoseconds: Self.gapNs)
        }
        return last
    }

    private func executeDianFeng(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let toggles = FeatureToggleStore.shared
        let group: Int
        if toggles.getBool("lingjiang", "rb_dianfeng_bei", default: false) {
            group = 1
        } else if toggles.getBool("lingjiang", "rb_dianfeng_suiji", default: false) {
            group = 2
        } else {
            group = 0
        }
        let url = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=gvg&sub=1&group=\(group)&check=1"
        return await executeUrl(title, url: url, cookie: cookie)
    }

    private func executeJieBai(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let toggles = FeatureToggleStore.shared
        let gid: String
        if toggles.getBool("lingjiang", "rb_jb_bm_1", default: false) { gid = "1" }
        else if toggles.getBool("lingjiang", "rb_jb_bm_2", default: false) { gid = "2" }
        else if toggles.getBool("lingjiang", "rb_jb_bm_3", default: false) { gid = "3" }
        else if toggles.getBool("lingjiang", "rb_jb_bm_5", default: false) { gid = "5" }
        else { gid = "4" }
        let url = "\(LedouCGI.phonepkBase)?cmd=brofight&subtype=1&gidIdx=\(gid)&channel=0&g_ut=1"
        return await executeUrl(title, url: url, cookie: cookie)
    }

    private func executeMengZhu(_ title: String, cookie: String) async -> LingJiangStepOutcome {
        let toggles = FeatureToggleStore.shared
        let ground: Int
        if toggles.getBool("lingjiang", "rb_mengzhu_baiyin", default: false) { ground = 2 }
        else if toggles.getBool("lingjiang", "rb_mengzhu_qingtong", default: false) { ground = 3 }
        else { ground = 1 }
        let url = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=wlmz&op=signup&ground_id=\(ground)"
        return await executeUrl(title, url: url, cookie: cookie)
    }

    private func executeUseGoods(_ title: String, goodsId: String, times: Int, cookie: String) async -> LingJiangStepOutcome {
        var last: LingJiangStepOutcome = .ok
        for i in 0..<times {
            let url = "\(LedouCGI.phonepkBase)?cmd=use&id=\(goodsId)&channel=0&g_ut=1"
            last = await executeUrl(title, url: url, cookie: cookie)
            if last == .loginFail { return last }
            if i + 1 < times { try? await Task.sleep(nanoseconds: Self.gapNs) }
        }
        return last
    }

    private func executeFormat(_ title: String, first: String, template: String, cookie: String) async -> LingJiangStepOutcome {
        let firstOut = await executeUrl(title, url: first, cookie: cookie, silentOk: true)
        if firstOut == .loginFail { return firstOut }
        guard let filled = LingJiangUrlResolver.fillFormat(template: template, body: lastBody) else {
            log.append(title, "格式化第二段无法填充，跳过")
            return .skip
        }
        return await executeUrl(title, url: filled, cookie: cookie)
    }

    private var lastBody = ""

    private func executeUrl(
        _ title: String,
        url: String,
        cookie: String,
        silentOk: Bool = false
    ) async -> LingJiangStepOutcome {
        let sanitized = sanitize(url)
        guard let u = URL(string: sanitized), LedouCGI.isAllowedHost(u.host) else {
            log.append(title, "拒绝非腾讯域名或坏 URL")
            return .skip
        }
        for attempt in 1...Self.maxBusyRetry {
            let (code, body) = await LedouCGI.get(url: u, cookie: cookie, referer: LedouCGI.petpkBase)
            lastBody = body
            let msg = extractMsg(body)
            if isLoginFail(body, msg) {
                log.append(title, msg.isEmpty ? "登陆校验失败" : msg)
                return .loginFail
            }
            if code < 0 {
                log.append(title, "请求失败(\(code))")
                return .skip
            }
            if isBusy(msg) || isBusy(body) {
                log.append(title, "系统繁忙，重试 \(attempt)/\(Self.maxBusyRetry)")
                try? await Task.sleep(nanoseconds: Self.gapNs)
                continue
            }
            if !silentOk {
                log.append(title, msg.isEmpty ? "完成" : msg)
            }
            return .ok
        }
        log.append(title, "系统繁忙，已达重试上限，跳过")
        return .busyRetry
    }

    private func sanitize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”"))
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func extractMsg(_ body: String) -> String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{"),
           let data = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = obj["name"] as? String, !name.isEmpty { return String(name.prefix(48)) }
            if let msg = obj["msg"] as? String, !msg.isEmpty { return String(msg.prefix(48)) }
            return ""
        }
        let plain = t
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(plain.prefix(48))
    }

    private func isBusy(_ text: String) -> Bool {
        text.contains("系统繁忙") || text.contains("请稍后再试")
    }

    private func isLoginFail(_ body: String, _ msg: String) -> Bool {
        if msg.contains("登陆校验失败") || msg.contains("登录校验失败") || msg.contains("未登录") { return true }
        if body.contains("登陆校验失败") || body.contains("请先登录") { return true }
        return false
    }

    /// 笔记 week：1=周一 … 7=周日
    private static func notesWeekHour() -> (Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        // Apple: 1=周日 … 7=周六 → 笔记 1=周一…7=周日
        let apple = cal.component(.weekday, from: now)
        let week = apple == 1 ? 7 : apple - 1
        return (week, hour)
    }
}
