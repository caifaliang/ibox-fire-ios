import Foundation

/// 真源：`SettingsWorkers.PaoMaDengWorker` — 黄历/乱斗/客栈等定时项。
enum PaoMaDengActions {
    static let fid = "paomadeng"
    private static let gapNs: UInt64 = 80_000_000

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        func on(_ key: String) -> Bool { t.getBool(fid, key) }

        var parts: [String] = []

        if on("cb_hl_dst") {
            let (_, cal) = await LedouCGI.getPhonePk(cmd: "calender", cookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            let brief = CombatLog.fromBody(cal).ifBlankMe(String(cal.prefix(35)))
            parts.append("黄历:\(brief)")
            onLog("黄历：\(brief)")
            if cal.contains("双倍") || cal.contains("斗神塔") || cal.count > 40 {
                let msg = await HuoYueCombat.farmDouShenTa(cookie: cookie, onLog: onLog)
                parts.append("斗神塔:\(msg)")
            }
        }

        if on("cb_hl_pldy") || on("cb_hl_pldy_not_x") {
            let msg = await PiLiangDouYouActions.farm(
                forceModes: ["stqb", "hy", "by"],
                onLog: onLog
            )
            parts.append("黄历斗友:\(msg)")
        }

        if on("cb_rc_lq") {
            let (_, body) = await LedouCGI.getPhonePk(
                cmd: "task", extra: ["sub": "7"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let brief = CombatLog.fromBody(body).ifBlankMe(String(body.prefix(25)))
            parts.append("日常:\(brief)")
            onLog("日常领奖：\(brief)")
        }

        if on("cb_ld_lq") {
            let (_, list) = await LedouCGI.getPhonePk(
                cmd: "luandou", extra: ["op": "0"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let brief = CombatLog.fromBody(list).ifBlankMe(String(list.prefix(25)))
            parts.append("乱斗:\(brief)")
            onLog("乱斗：\(brief)")
            if let id = firstGroup(#"id=(\d+)"#, in: list) {
                _ = await LedouCGI.getPhonePk(
                    cmd: "luandou", extra: ["op": "8", "id": id], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
            }
        }

        if on("cb_ld_qdp") {
            let msg = await HuoYueCombat.farmQiangDiPan(cookie: cookie, onLog: onLog)
            parts.append("抢地盘:\(msg)")
        }

        if on("cb_kz_xxzs") || on("cb_kz_jhdj") || on("cb_kz_tjdj") || on("cb_kz_fq_jhdj") {
            let (_, body) = await LedouCGI.getPhonePk(
                cmd: "knight", extra: ["op": "23"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let brief = CombatLog.fromBody(body).ifBlankMe(String(body.prefix(25)))
            parts.append("客栈:\(brief)")
            onLog("客栈：\(brief)")
        }

        let tip = parts.isEmpty ? "未开启子项（请在跑马灯设置勾选）" : parts.joined(separator: " | ")
        onLog(tip)
        return tip
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
