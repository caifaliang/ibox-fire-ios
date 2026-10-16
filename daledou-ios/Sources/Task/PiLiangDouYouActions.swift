import Foundation

/// 真源：`PiLiangDouYouActions` — 师徒情拜 / 好友 / 帮友 批量挑战。
enum PiLiangDouYouActions {
    private static let fid = "piliang_douyou"
    private static let gapNs: UInt64 = 80_000_000

    private struct Mode {
        let key: String
        let tag: String
        let type: String
    }

    @MainActor
    static func farm(
        forceModes: [String]? = nil,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            onLog("请先登录")
            return "未登录"
        }
        let t = FeatureToggleStore.shared
        let modes = resolveModes(forceModes)
        if modes.isEmpty {
            onLog("请选择分类：师徒情拜 / 好友 / 帮友 / 陌生人")
            return "未选分类"
        }
        let onlyShenQuan = t.getBool(fid, "cb_sq")
        let stopOnGongXian = t.getBool(fid, "cb_gmt")
        let skipLose = t.getBool(fid, "cb_sb")
        let autoShare = t.getBool(fid, "cb_fx")
        let autoTiLi = t.getBool(fid, "cb_tl_zd")
        let autoGongXian = t.getBool(fid, "cb_gx_zd")
        let sortByLevel = t.getBool(fid, "cb_djpx")
        let minDj = Int(t.getString(fid, "min_dj", default: "1")) ?? 1
        let maxDj = Int(t.getString(fid, "max_dj", default: "300")) ?? 300
        let maxZl = Int(t.getString(fid, "max_zl", default: "5000")) ?? 5000
        let limit = PldyRoster.loadLimit()

        onLog("批量斗友开始（\(modes.map(\.tag).joined(separator: "/"))，最多\(limit)条）")
        var fights = 0
        var wins = 0
        var busy = 0

        for mode in modes {
            if fights >= limit { break }
            let cached = t.getString(fid, "last_targets")
            let cachedMode = t.getString(fid, "last_mode")
            let rows: [PldyRoster.Row]
            if !cached.isEmpty && cachedMode == mode.key {
                rows = cached.split(separator: "|")
                    .map(String.init)
                    .filter { $0.count >= 5 }
                    .map { PldyRoster.Row(qq: $0, name: $0, level: minDj, zhanli: 0) }
            } else {
                let raw = await PldyRoster.fetch(mode: mode.key, cookie: cookie, onLog: onLog)
                try? await Task.sleep(nanoseconds: gapNs)
                rows = PldyRoster.filter(
                    raw, minDj: minDj, maxDj: maxDj, maxZl: maxZl,
                    onlyShenQuan: onlyShenQuan, sortByLevel: sortByLevel, limit: limit
                )
            }
            let already = foughtSet()
            var targets = [String]()
            for row in rows where !row.isFight && !already.contains(row.qq) && row.qq.count >= 5 {
                if !targets.contains(row.qq) { targets.append(row.qq) }
            }
            onLog("\(mode.tag)可打\(targets.count)人")
            for uin in targets {
                if fights >= limit { break }
                var busyRetry = 0
                var doneThis = false
                while !doneThis && fights < limit && busyRetry < 5 {
                    if Task.isCancelled { return "批量斗友\(fights)/胜\(wins)" }
                    var extra = ["B_UID": uin, "type": mode.type]
                    if mode.type == "2" { extra["page"] = "1" }
                    let (_, f) = await LedouCGI.getPhonePk(cmd: "fight", extra: extra, cookie: cookie)
                    fights += 1
                    try? await Task.sleep(nanoseconds: gapNs)
                    let line = prefer(f, ["打翻在地", "贡献度", "你干掉了", "惜败", "体力值不足"])
                        .ifBlankPldy(CombatLog.fromBody(f))
                    onLog("[\(mode.tag)]\(uin) \(line.isEmpty ? "挑战" : line)")

                    if f.contains("系统繁忙") || line.contains("系统繁忙") {
                        busy += 1
                        busyRetry += 1
                        if busy >= 8 {
                            onLog("系统繁忙过多，结束")
                            return "批量斗友\(fights)"
                        }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    } else if f.contains("体力值不足") || f.contains("请好好休息") {
                        if autoTiLi, await tryTiLi(cookie: cookie, onLog: onLog) {
                            fights -= 1
                            continue
                        }
                        onLog("体力不足，结束")
                        return "批量斗友\(fights)/胜\(wins)"
                    } else if f.contains("挑战次数") && (f.contains("上限") || f.contains("用完")) {
                        onLog("挑战次数上限")
                        return "批量斗友\(fights)/胜\(wins)"
                    } else if stopOnGongXian && f.contains("贡献") && f.contains("满") {
                        onLog("贡献已满，停止")
                        return "批量斗友\(fights)/胜\(wins)"
                    } else if f.contains("挑战书") && f.contains("不足") {
                        onLog("挑战书不足")
                        return "批量斗友\(fights)/胜\(wins)"
                    } else if f.contains("打翻在地") || f.contains("贡献度") || f.contains("你干掉了") {
                        wins += 1
                        busy = 0
                        if autoGongXian { await tryGongXian(cookie: cookie, onLog: onLog) }
                        if autoShare && wins % 5 == 0 {
                            _ = await LedouCGI.getPhonePk(
                                cmd: "sharegame",
                                extra: ["subtype": "2", "shareinfo": "5"],
                                cookie: cookie
                            )
                            try? await Task.sleep(nanoseconds: gapNs)
                        }
                        markFought(uin)
                        doneThis = true
                    } else if skipLose && (f.contains("惜败") || f.contains("战败") || f.contains("被打翻")) {
                        markFought(uin)
                        doneThis = true
                    } else {
                        markFought(uin)
                        doneThis = true
                    }
                }
            }
        }
        onLog("批量斗友结束")
        return "批量斗友\(fights)/胜\(wins)"
    }

    private static func resolveModes(_ force: [String]?) -> [Mode] {
        let t = FeatureToggleStore.shared
        let keys: [String] = {
            if let force, !force.isEmpty { return force }
            let mode = t.getString(fid, "mode")
            switch mode {
            case "stqb": return ["stqb"]
            case "hy": return ["hy"]
            case "by": return ["by"]
            case "msr": return ["msr"]
            default:
                var fromHy: [String] = []
                if t.getBool("huoyue", "cb_dy_stqb") || t.getBool("daiwan", "cb_dy_stqb") {
                    fromHy.append("stqb")
                }
                if t.getBool("huoyue", "cb_dy_hy") || t.getBool("daiwan", "cb_dy_hy") {
                    fromHy.append("hy")
                }
                if t.getBool("huoyue", "cb_dy_by") || t.getBool("daiwan", "cb_dy_by") {
                    fromHy.append("by")
                }
                return fromHy.isEmpty ? ["hy"] : fromHy
            }
        }()
        return keys.compactMap {
            switch $0 {
            case "stqb", "师徒": return Mode(key: "stqb", tag: "师徒情拜", type: "10")
            case "hy", "好友": return Mode(key: "hy", tag: "好友", type: "1")
            case "by", "帮友": return Mode(key: "by", tag: "帮友", type: "2")
            case "msr", "陌生人": return Mode(key: "msr", tag: "陌生人", type: "9")
            default: return nil
            }
        }
    }

    private static func foughtSet() -> Set<String> {
        Set(
            FeatureToggleStore.shared.getString(fid, "fought_uins")
                .split(separator: "|")
                .map(String.init)
                .filter { $0.count >= 5 }
        )
    }

    private static func markFought(_ uin: String) {
        guard uin.count >= 5 else { return }
        let t = FeatureToggleStore.shared
        let next = foughtSet().union([uin]).joined(separator: "|")
        t.setString(fid, "fought_uins", next)
        let left = t.getString(fid, "last_targets")
            .split(separator: "|")
            .map(String.init)
            .filter { $0.count >= 5 && $0 != uin }
        t.setString(fid, "last_targets", left.joined(separator: "|"))
    }

    private static func tryTiLi(cookie: String, onLog: @escaping (String) -> Void) async -> Bool {
        let t = FeatureToggleStore.shared
        var ids: [String] = []
        if t.getBool(fid, "cb_tl_zhen") || t.getBool(fid, "cb_tl_zhen_jh") { ids.append("3041") }
        if t.getBool(fid, "cb_tl_da") || t.getBool(fid, "cb_tl_da_jh") { ids.append(contentsOf: ["3003", "8205"]) }
        if t.getBool(fid, "cb_tl_zhong") || t.getBool(fid, "cb_tl_zhong_jh") { ids.append(contentsOf: ["3002", "8204"]) }
        if t.getBool(fid, "cb_tl_xiao") || t.getBool(fid, "cb_tl_xiao_jh") { ids.append(contentsOf: ["3001", "8203"]) }
        if ids.isEmpty { ids = ["3041", "3003", "3002", "3001"] }
        for id in ids {
            let (_, r) = await LedouCGI.getPhonePk(
                cmd: "use", extra: ["id": id, "store_type": "1"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(r)
            if !msg.isEmpty { onLog("体力:\(msg)") }
            if r.contains("成功") || msg.contains("成功") || msg.contains("恢复") { return true }
            if r.contains("不足") || r.contains("没有") { continue }
        }
        return false
    }

    private static func tryGongXian(cookie: String, onLog: @escaping (String) -> Void) async {
        let (_, r) = await LedouCGI.getPetPk(
            cmd: "newAct", extra: ["subtype": "100", "op": "0"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(r)
        if !msg.isEmpty { onLog("贡献:\(msg)") }
    }

    private static func prefer(_ body: String, _ keys: [String]) -> String {
        for k in keys where body.contains(k) {
            if let msg = CombatLog.jsonField(body, "msg"), msg.contains(k) { return msg }
            return k
        }
        return ""
    }
}

private extension String {
    func ifBlankPldy(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
