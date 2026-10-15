import Foundation

/// 一键活跃（真源 DaLedou_App_Dev HuoYueRunner / LivenessActions）。
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
        log.setRunning(false)
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

    private func runAll(cookie: String) async {
        running = true
        log.setRunning(true, name: "一键活跃")
        defer {
            running = false
            log.setRunning(false)
            job = nil
        }
        log.append("活跃", "--开始")
        let enabled = store.enabledLabels()
        if enabled.isEmpty {
            log.append("活跃", "无勾选项：请到活跃设置勾选")
            log.append("活跃", "--完成")
            return
        }
        log.append("活跃", "将执行 \(enabled.count) 项")
        if Task.isCancelled { return }
        await phasePre(cookie: cookie)
        if Task.isCancelled { return }
        await phaseArcade(cookie: cookie)
        if Task.isCancelled { return }
        await phaseScore(cookie: cookie)
        if Task.isCancelled { return }
        await phaseTasks(cookie: cookie)
        if Task.isCancelled { return }
        await phaseGift(cookie: cookie)
        log.append("活跃", "--完成")
    }

    private func on(_ k: String) -> Bool { store.on(k) }

    private func phasePre(cookie: String) async {
        if on("cb_dy_dt") {
            let (_, body) = await LedouCGI.getPetPk(cmd: "blacksmith", extra: ["op": "5"], cookie: cookie)
            log.append("打铁", LedouCGI.shortBody(body, code: 200))
        }
    }

    private func phaseArcade(cookie: String) async {
        let flags = ["cb_lj_smzp", "cb_lj_wwj", "cb_lj_cds", "cb_lj_bc"]
        guard flags.contains(where: { on($0) }) else { return }
        _ = await LedouCGI.getPhonePk(cmd: "pacfg", cookie: cookie)
        if on("cb_lj_smzp") {
            _ = await LedouCGI.getPetPk(cmd: "newAct", extra: ["op": "0", "subtype": "81"], cookie: cookie)
            let (_, b) = await LedouCGI.getPetPk(cmd: "newAct", extra: ["op": "1", "subtype": "81"], cookie: cookie)
            log.append("神魔转盘", LedouCGI.shortBody(b, code: 200))
        }
        if on("cb_lj_wwj") {
            _ = await LedouCGI.getPetPk(cmd: "newAct", extra: ["op": "0", "subtype": "114"], cookie: cookie)
            let (_, b) = await LedouCGI.getPetPk(cmd: "newAct", extra: ["op": "1", "subtype": "114"], cookie: cookie)
            log.append("娃娃机", LedouCGI.shortBody(b, code: 200))
        }
        if on("cb_lj_cds") {
            _ = await LedouCGI.getPetPk(cmd: "oddeven", cookie: cookie)
            let (_, b) = await LedouCGI.getPetPk(cmd: "oddeven", extra: ["value": "1"], cookie: cookie)
            log.append("猜单双", LedouCGI.shortBody(b, code: 200))
        }
        if on("cb_lj_bc") {
            let (_, b) = await LedouCGI.getPhonePk(cmd: "cargo", extra: ["op": "16"], cookie: cookie)
            log.append("镖车奖励", LedouCGI.shortBody(b, code: 200))
        }
    }

    private func phaseScore(cookie: String) async {
        if on("lv_fight20") || on("lv_fight10") {
            let n = on("lv_fight20") ? 20 : 10
            let msg = await farmFights(times: n, cookie: cookie)
            log.append("乐斗", msg)
        }
        if on("lv_tongmen") {
            log.append("同门切磋", await farmTongMen(cookie: cookie))
        }
        if on("lv_wulin") {
            log.append("武林", await farmWuLin(cookie: cookie))
        }
        if on("lv_share") {
            log.append("分享", await farmShare(cookie: cookie))
        }
        if on("lv_inlay") {
            log.append("镶嵌", await farmInlay(cookie: cookie))
        }
        if on("cb_rw_zz") {
            log.append("助阵", await farmFormation(cookie: cookie))
        }
        if on("cb_rw_yb") {
            let (_, b) = await LedouCGI.getPhonePk(cmd: "cargo", extra: ["op": "7"], cookie: cookie)
            log.append("护送押镖", LedouCGI.shortBody(b, code: 200))
        }
        if on("cb_rw_cg12") {
            let (_, b) = await LedouCGI.getPetPk(cmd: "intfmerid", extra: ["sub": "3"], cookie: cookie)
            log.append("传功", LedouCGI.shortBody(b, code: 200))
        }
        await phaseCombat(cookie: cookie)
    }

    /// 真源 HuoYueRunner.phaseDaiWanMatrix 战斗项。
    private func phaseCombat(cookie: String) async {
        func live(_ tag: String) -> (String) -> Void {
            { line in
                Task { @MainActor in TaskLogStore.shared.append(tag, line) }
            }
        }
        // 顺序对齐 APK matrix
        if on("cb_dw_12") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmGong12(cookie: cookie, onLog: live("12宫"))
            log.append("12宫", msg)
        }
        if on("cb_gd_jjc") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmJingJiChang(cookie: cookie, onLog: live("竞技场"))
            log.append("竞技场", msg)
        }
        if on("cb_gd_qdp") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmQiangDiPan(cookie: cookie, onLog: live("抢地盘"))
            log.append("抢地盘", msg)
        }
        if on("cb_dw_boss") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmBoss(cookie: cookie, onLog: live("Boss"))
            log.append("Boss", msg)
        }
        if on("cb_dw_df") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmDianFeng(cookie: cookie, onLog: live("巅峰"))
            log.append("巅峰", msg)
        }
        if on("cb_dw_hjpm") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmHuanJing(cookie: cookie, onLog: live("幻境"))
            log.append("幻境", msg)
        }
        if on("cb_dw_ll") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmLilian(cookie: cookie, onLog: live("历练"))
            log.append("历练", msg)
        }
        if on("cb_gd_sy") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmShenYuan(cookie: cookie, onLog: live("深渊"))
            log.append("深渊", msg)
        }
        if on("cb_dw_hj") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmHuaJuan(cookie: cookie, onLog: live("画卷"))
            log.append("画卷", msg)
        }
        if on("cb_dw_mp") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmMenPai(cookie: cookie, onLog: live("门派"))
            log.append("门派", msg)
        }
        if on("cb_dw_fxll") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmLilian(cookie: cookie, reverse: true, onLog: live("反向历练"))
            log.append("反向历练", msg)
        }
        if on("cb_dw_hw") {
            if Task.isCancelled { return }
            let msg = await HuoYueCombat.farmHuiWu(cookie: cookie, onLog: live("会武"))
            log.append("会武", msg)
        }
    }

    private func phaseTasks(cookie: String) async {
        if on("cb_rw_rc") {
            let (_, b) = await LedouCGI.getPhonePk(cmd: "task", extra: ["sub": "7"], cookie: cookie)
            log.append("日常任务", LedouCGI.shortBody(b, code: 200))
        }
        if on("cb_rw_bp") {
            let (_, b) = await LedouCGI.getPhonePk(cmd: "factiontask", extra: ["sub": "1"], cookie: cookie)
            log.append("帮派任务", LedouCGI.shortBody(b, code: 200))
        }
        if on("cb_rw_mp") {
            let (_, b) = await LedouCGI.getPhonePk(cmd: "sect_task", cookie: cookie)
            log.append("门派任务", LedouCGI.shortBody(b, code: 200))
        }
    }

    private func phaseGift(cookie: String) async {
        guard on("cb_lj_hy") else { return }
        for id in 1...4 {
            if Task.isCancelled { return }
            let (_, b) = await LedouCGI.getPhonePk(
                cmd: "liveness_getgiftbag",
                extra: ["giftbagid": "\(id)", "action": "1"],
                cookie: cookie
            )
            log.append("活跃礼包", "id=\(id) \(LedouCGI.shortBody(b, code: 200))")
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    // MARK: - Score CGI

    private func farmTongMen(cookie: String, need: Int = 2) async -> String {
        var n = 0
        for _ in 0..<(need + 2) {
            if n >= need { break }
            _ = await LedouCGI.getPhonePk(cmd: "sect", extra: ["op": "showtraining"], cookie: cookie)
            let (_, r) = await LedouCGI.getPhonePk(cmd: "sect", extra: ["op": "trainingwithmember"], cookie: cookie)
            if r.contains("次数已用尽") || r.contains("用完") { break }
            n += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return "同门切磋\(n)/\(need)"
    }

    private func farmWuLin(cookie: String) async -> String {
        let (_, page) = await LedouCGI.getPhonePk(cmd: "showwulin", cookie: cookie)
        if page.contains("已报名") { return "武林已报名" }
        let (_, sign) = await LedouCGI.getPhonePk(
            cmd: "fastSignWulin", extra: ["ifFirstSign": "1"], cookie: cookie
        )
        return LedouCGI.shortBody(sign, code: 200)
    }

    private func farmShare(cookie: String, need: Int = 5) async -> String {
        for _ in 0..<(need + 1) {
            let (_, page) = await LedouCGI.getPhonePk(cmd: "sharegame", extra: ["subtype": "1"], cookie: cookie)
            let re = try? NSRegularExpression(pattern: #"今日分享次数[：:]\s*(\d+)\s*/\s*(\d+)"#)
            if let m = re?.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
               let r1 = Range(m.range(at: 1), in: page),
               let r2 = Range(m.range(at: 2), in: page),
               let cur = Int(page[r1]), let max = Int(page[r2]),
               cur >= min(need, max) {
                _ = await LedouCGI.getPhonePk(cmd: "sharegame", extra: ["subtype": "3"], cookie: cookie)
                return "分享已满 \(cur)/\(max)"
            }
            _ = await LedouCGI.getPhonePk(cmd: "sharegame", extra: ["subtype": "6"], cookie: cookie)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return "分享完成"
    }

    private func farmInlay(cookie: String) async -> String {
        let (_, page) = await LedouCGI.getPhonePk(cmd: "inlaypearl", extra: ["subcmd": "index"], cookie: cookie)
        let re = try? NSRegularExpression(pattern: #"weapon_id=(\d+)"#)
        guard let m = re?.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
              let r = Range(m.range(at: 1), in: page) else {
            return "无可入魂武器"
        }
        let wid = String(page[r])
        let (_, body) = await LedouCGI.getPhonePk(
            cmd: "inlaypearl",
            extra: ["subcmd": "pearlofweapon", "weapon_id": wid],
            cookie: cookie
        )
        return LedouCGI.shortBody(body, code: 200)
    }

    private func farmFormation(cookie: String, need: Int = 3) async -> String {
        var n = 0
        for t in ["1", "2", "3", "4", "5"] {
            if n >= need { break }
            _ = await LedouCGI.getPhonePk(
                cmd: "formation",
                extra: ["type": "0", "formationtype": t],
                cookie: cookie
            )
            n += 1
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return "助阵提升\(n)/\(need)"
    }

    /// 乐斗目标池：friendlist / viewmem / viewxialv 刮 UIN 后 fight。
    private func farmFights(times: Int, cookie: String) async -> String {
        var done = 0
        var tried = Set<String>()

        func fight(_ uin: String, type: String, tag: String) async -> Bool {
            if done >= times || tried.contains(uin) { return false }
            tried.insert(uin)
            let (_, body) = await LedouCGI.getPhonePk(
                cmd: "fight",
                extra: ["B_UID": uin, "type": type, "page": type == "2" ? "1" : ""],
                cookie: cookie
            )
            log.append("乐斗", "[\(tag)]\(uin) \(LedouCGI.shortBody(body, code: 200))")
            if body.contains("体力值不足") || body.contains("请好好休息") { return false }
            if body.contains("不是你的好友") || body.contains("已乐斗") { return false }
            done += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
            return done >= times
        }

        func extractUins(_ html: String) -> [String] {
            var out: [String] = []
            let re = try? NSRegularExpression(pattern: #"B_UID=(\d{5,})"#)
            let ns = html as NSString
            re?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 2 else { return }
                let u = ns.substring(with: m.range(at: 1))
                if !out.contains(u) { out.append(u) }
            }
            return out
        }

        if on("lv_fight_tili") {
            _ = await LedouCGI.getPhonePk(cmd: "view", extra: ["type": "6"], cookie: cookie)
            _ = await LedouCGI.getPhonePk(cmd: "set", extra: ["type": "0"], cookie: cookie)
        }
        if on("lv_fight_boss_hy"), done < times {
            let (_, html) = await LedouCGI.getPhonePk(cmd: "friendlist", extra: ["page": "1"], cookie: cookie)
            for u in extractUins(html) {
                if await fight(u, type: "2", tag: "好友Boss") { break }
            }
        }
        if on("lv_fight_boss_bp"), done < times {
            let (_, html) = await LedouCGI.getPhonePk(cmd: "viewmem", cookie: cookie)
            for u in extractUins(html) {
                if await fight(u, type: "2", tag: "帮派Boss") { break }
            }
        }
        if (on("lv_fight_boss_xb") || on("lv_fight_shitu") || on("lv_fight_fuqi") || on("lv_fight_jiebai")),
           done < times {
            let (_, html) = await LedouCGI.getPhonePk(cmd: "viewxialv", cookie: cookie)
            for u in extractUins(html) {
                if await fight(u, type: "10", tag: "侠侣") { break }
            }
        }
        return "乐斗\(done)/\(times)"
    }
}
