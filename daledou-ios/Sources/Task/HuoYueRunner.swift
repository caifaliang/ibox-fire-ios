import Foundation

/// 一键活跃编排骨架（M13）：对齐 Android HuoYueRunner 阶段顺序，逐步接线 CGI。
@MainActor
final class HuoYueRunner: ObservableObject {
    static let shared = HuoYueRunner()

    @Published private(set) var running = false

    private let store = HuoYueStore.shared
    private let log = TaskLogStore.shared
    private var job: Task<Void, Never>?

    private init() {}

    func stop() {
        job?.cancel()
        job = nil
        running = false
        log.append("活跃", "已停止")
    }

    func start(cookie: String) {
        guard !running else {
            log.append("活跃", "已在运行中")
            return
        }
        guard LoginURLs.hasGameSession(cookie) else {
            log.append("活跃", "请先登录")
            return
        }
        job = Task { await runAll(cookie: cookie) }
    }

    /// 供 DaiWan L4「一键活跃代玩」转交。
    func runOnceAwait(cookie: String) async -> String {
        if running {
            log.append("活跃", "已在运行中，本轮跳过")
            return "活跃运行中，已跳过"
        }
        guard LoginURLs.hasGameSession(cookie) else {
            log.append("活跃", "请先登录")
            return "未登陆"
        }
        await runAll(cookie: cookie)
        return "活跃编排完成"
    }

    private func runAll(cookie: String) async {
        running = true
        defer { running = false; job = nil }
        log.append("活跃", "--开始")
        let enabled = store.enabledLabels()
        if enabled.isEmpty {
            log.append("活跃", "没有任何勾选项：请到「活跃代玩」勾选后再点")
            log.append("活跃", "--完成")
            return
        }
        log.append("活跃", "将执行 \(enabled.count) 项：\(enabled.joined(separator: "、"))")
        if Task.isCancelled { return }
        await phasePre(cookie: cookie)
        if Task.isCancelled { return }
        await phaseArcade(cookie: cookie)
        if Task.isCancelled { return }
        await phaseLivenessScore(cookie: cookie)
        if Task.isCancelled { return }
        await phaseRenWuHints(cookie: cookie)
        if Task.isCancelled { return }
        await phaseGift(cookie: cookie)
        log.append("活跃", "--完成")
    }

    private func on(_ key: String) -> Bool { store.on(key) }

    private func phasePre(cookie: String) async {
        if on("cb_save_beibao") {
            log.append("活跃", "[保存背包] 快照未接（M10 可复用 BeiBaoService）")
        }
        if on("cb_dy_dt") {
            let msg = await pet(cookie, cmd: "blacksmith", extra: ["op": "5"])
            log.append("打铁", msg)
        }
    }

    private func phaseArcade(cookie: String) async {
        let flags = ["cb_lj_smzp", "cb_lj_wwj", "cb_lj_cds", "cb_lj_symb", "cb_lj_djtm", "cb_lj_bc"]
        guard flags.contains(where: { on($0) }) else { return }
        _ = await phone(cookie, cmd: "pacfg")
        if on("cb_lj_smzp") {
            _ = await pet(cookie, cmd: "newAct", extra: ["op": "0", "subtype": "81"])
            let r = await pet(cookie, cmd: "newAct", extra: ["op": "1", "subtype": "81"])
            log.append("神魔转盘", r)
        }
        if on("cb_lj_wwj") {
            _ = await pet(cookie, cmd: "newAct", extra: ["op": "0", "subtype": "114"])
            let r = await pet(cookie, cmd: "newAct", extra: ["op": "1", "subtype": "114"])
            log.append("娃娃机", r)
        }
        if on("cb_lj_cds") {
            _ = await pet(cookie, cmd: "oddeven")
            let r = await pet(cookie, cmd: "oddeven", extra: ["value": "1"])
            log.append("猜单双", r)
        }
        if on("cb_lj_symb") {
            let r = await pet(cookie, cmd: "newAct", extra: ["op": "0", "subtype": "164"])
            log.append("深渊秘宝", r)
        }
        if on("cb_lj_djtm") {
            let r = await pet(cookie, cmd: "newAct", extra: ["subtype": "166"])
            log.append("斗境探秘", r)
        }
        if on("cb_lj_bc") {
            let r = await phone(cookie, cmd: "cargo", extra: ["op": "16"])
            log.append("镖车奖励", r)
        }
    }

    private func phaseLivenessScore(cookie: String) async {
        if on("lv_fight20") || on("lv_fight10") {
            let n = on("lv_fight20") ? 20 : 10
            log.append("乐斗", "乐斗\(n)次目标池战斗未接（下一切片）")
        }
        if on("lv_tongmen") {
            let msg = await farmTongMen(cookie: cookie)
            log.append("同门切磋", msg)
        }
        if on("lv_wulin") {
            let msg = await farmWuLin(cookie: cookie)
            log.append("武林", msg)
        }
        if on("lv_share") {
            let msg = await farmShare(cookie: cookie)
            log.append("分享", msg)
        }
        if on("lv_inlay") {
            let msg = await farmInlay(cookie: cookie)
            log.append("镶嵌", msg)
        }
        if on("cb_rw_yb") {
            let r = await phone(cookie, cmd: "cargo", extra: ["op": "7"])
            log.append("护送押镖", r)
        }
        if on("cb_rw_cg12") {
            let r = await pet(cookie, cmd: "intfmerid", extra: ["sub": "3"])
            log.append("传功", r)
        }
        // 转交已有 L4 名
        let matrix: [(String, String)] = [
            ("cb_dw_ll", "历练"),
            ("cb_dw_hj", "画卷迷踪"),
            ("cb_dw_hjpm", "飘渺幻境"),
            ("cb_gd_sy", "深渊秘境"),
            ("cb_dw_hw", "会武"),
            ("cb_dw_boss", "Boss"),
        ]
        for (key, name) in matrix where on(key) {
            log.append(name, "转交代玩子类型（多为 stub）")
            let msg = await DaiWanRunner.shared.executeTypePublic(name, cookie: cookie)
            log.append(name, msg)
        }
    }

    private func phaseRenWuHints(cookie: String) async {
        if on("cb_rw_rc") {
            let r = await phone(cookie, cmd: "task", extra: ["sub": "7"])
            log.append("日常任务", r)
        }
        if on("cb_rw_bp") {
            let r = await phone(cookie, cmd: "factiontask", extra: ["sub": "1"])
            log.append("帮派任务", r)
        }
        if on("cb_rw_mp") {
            let r = await phone(cookie, cmd: "sect_task")
            log.append("门派任务", r)
        }
    }

    private func phaseGift(cookie: String) async {
        guard on("cb_lj_hy") else { return }
        for id in 1...4 {
            if Task.isCancelled { return }
            let r = await phone(
                cookie,
                cmd: "liveness_getgiftbag",
                extra: ["giftbagid": "\(id)", "action": "1"]
            )
            log.append("活跃礼包", "id=\(id) \(r)")
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    // MARK: - Score helpers

    private func farmTongMen(cookie: String, need: Int = 2) async -> String {
        var n = 0
        for _ in 0..<(need + 2) {
            if n >= need { break }
            _ = await phone(cookie, cmd: "sect", extra: ["op": "showtraining"])
            let r = await phone(cookie, cmd: "sect", extra: ["op": "trainingwithmember"])
            if r.contains("次数已用尽") || r.contains("用完") { break }
            n += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return "同门切磋\(n)/\(need)"
    }

    private func farmWuLin(cookie: String) async -> String {
        let page = await phone(cookie, cmd: "showwulin")
        if page.contains("已报名") { return "武林已报名" }
        return await phone(cookie, cmd: "fastSignWulin", extra: ["ifFirstSign": "1"])
    }

    private func farmShare(cookie: String, need: Int = 5) async -> String {
        var last = ""
        for _ in 0..<(need + 1) {
            let page = await phone(cookie, cmd: "sharegame", extra: ["subtype": "1"])
            let re = try? NSRegularExpression(pattern: #"今日分享次数[：:]\s*(\d+)\s*/\s*(\d+)"#)
            if let mm = re?.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
               let r1 = Range(mm.range(at: 1), in: page),
               let r2 = Range(mm.range(at: 2), in: page),
               let cur = Int(page[r1]),
               let max = Int(page[r2]),
               cur >= min(need, max) {
                _ = await phone(cookie, cmd: "sharegame", extra: ["subtype": "3"])
                return "分享已满 \(cur)/\(max)"
            }
            last = await phone(cookie, cmd: "sharegame", extra: ["subtype": "6"])
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return last.isEmpty ? "分享完成" : last
    }

    private func farmInlay(cookie: String) async -> String {
        let page = await phone(cookie, cmd: "inlaypearl", extra: ["subcmd": "index"])
        let re = try? NSRegularExpression(pattern: #"weapon_id=(\d+)"#)
        guard let m = re?.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
              let r = Range(m.range(at: 1), in: page) else {
            return "无可入魂武器"
        }
        let wid = String(page[r])
        return await phone(
            cookie,
            cmd: "inlaypearl",
            extra: ["subcmd": "pearlofweapon", "weapon_id": wid]
        )
    }

    // MARK: - HTTP

    private func phone(_ cookie: String, cmd: String, extra: [String: String] = [:]) async -> String {
        let (code, body) = await LedouCGI.getPhonePk(cmd: cmd, extra: extra, cookie: cookie)
        return Self.short(body, code: code)
    }

    private func pet(_ cookie: String, cmd: String, extra: [String: String] = [:]) async -> String {
        var comps = URLComponents(string: LedouCGI.petpkBase)!
        var items = [URLQueryItem(name: "cmd", value: cmd)]
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) {
            items.append(.init(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else { return "URL 错误" }
        let (code, body) = await LedouCGI.get(url: url, cookie: cookie, referer: LedouCGI.petpkBase)
        return Self.short(body, code: code)
    }

    private static func short(_ body: String, code: Int) -> String {
        if code == -2 { return "拒绝非腾讯域名" }
        if code < 0 { return "网络失败(\(code))" }
        if body.contains("登陆校验失败") || body.contains("请先登录") { return "会话失效" }
        let plain = body
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.isEmpty { return "HTTP \(code) 空体" }
        return String(plain.prefix(80))
    }
}
