import Foundation

/// 真源：`MoreExtraActions.farmLongHuang` — dragon/martial + dragonphoenix/pk。
enum LongHuangActions {
    static let fid = "longhuang"
    private static let gapNs: UInt64 = 80_000_000

    private struct Target {
        let uin: String
        let name: String
        let pos: Int
        let shenQi: Int
        let chuan: Int
        let kang: Int
        let idx: String
    }

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        func b(_ key: String, _ def: Bool = false) -> Bool { t.getBool(fid, key, default: def) }
        func i(_ key: String, _ def: Int = 0) -> Int {
            Int(t.getString(fid, key, default: "\(def)").trimmingCharacters(in: .whitespaces)) ?? def
        }

        let usePay = b("cb_fu_fei")
        let skipLose = b("cb_not_shi_bai")
        let daTie = b("cb_da_tie")
        let closeWhenDone = b("cb_close", true)
        let after2130Free = b("cb_da_wan_mian_fei")
        let yaoLi = b("cb_li")
        let yaoMin = b("cb_min")
        let yaoSu = b("cb_su")
        let minWeiCi = max(1, i("ed_wei_ci", 1))
        let maxShen = i("ed_shen_max", 0)
        let maxChuan = i("ed_chuan_max", 0)
        let maxKang = i("ed_kang_max", 0)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let day = cal.component(.day, from: now)
        if !(8...21).contains(hour) || !(4...25).contains(day) {
            let tip = "不在龙凰论武时段（每月4–25日 8:00–22:00）"
            onLog(tip)
            if closeWhenDone { t.setEnabled(fid, false) }
            return tip
        }
        if usePay && after2130Free {
            let tip = "使用付费不能和21:30打完免费次数同时勾选"
            onLog(tip)
            return tip
        }

        let selfUin = LoginURLs.extractQq(cookie) ?? ""
        var zhanBai = Set<String>()
        var fought = 0

        for round in 0..<40 {
            if Task.isCancelled { break }
            let (_, page) = await LedouCGI.getPetPk(
                cmd: "dragon", extra: ["op": "martial"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)

            let result = CombatLog.jsonInt(page, "result")
            let times = CombatLog.jsonInt(page, "times") ?? 0
            let remain = CombatLog.jsonInt(page, "remain") ?? 0
            let position = CombatLog.jsonInt(page, "position") ?? 0
            let msg0 = CombatLog.jsonField(page, "msg") ?? ""
            if let result, result != 0, !msg0.isEmpty {
                onLog(msg0)
                if msg0.contains("系统繁忙") {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
            }
            onLog("轮次\(round + 1) 次数=\(times) 剩余=\(remain) 位次=\(position)")

            if minWeiCi > 0, position > 0, minWeiCi > position {
                let tip = "当前位次 \(position) 已优于目标 \(minWeiCi)，停止"
                onLog(tip)
                if closeWhenDone { t.setEnabled(fid, false) }
                return tip
            }

            let needFreeOnly = after2130Free && (hour > 21 || (hour == 21 && minute >= 30))
            if times <= 0 {
                if usePay && !needFreeOnly {
                    onLog("兑换付费次数…")
                    let (_, add) = await LedouCGI.getPetPk(
                        cmd: "dragon", extra: ["op": "addremain"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                    onLog(CombatLog.fromBody(add).ifBlankMe("addremain"))
                    let t2 = CombatLog.jsonInt(add, "times") ?? 0
                    if t2 <= 0, CombatLog.jsonInt(add, "result") != 0 {
                        let tip = "付费次数兑换失败，停止"
                        onLog(tip)
                        if closeWhenDone { t.setEnabled(fid, false) }
                        return tip
                    }
                    continue
                }
                let tip = "次数用完"
                onLog(tip)
                if closeWhenDone { t.setEnabled(fid, false) }
                return tip
            }

            let targets = parseTargets(page)
            if targets.isEmpty {
                onLog("对手列表为空")
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            guard let pick = targets.first(where: { tgt in
                if skipLose, zhanBai.contains(tgt.uin) { return false }
                if maxShen > 0, tgt.shenQi > maxShen { return false }
                if maxChuan > 0, tgt.chuan >= 0, tgt.chuan > maxChuan { return false }
                if maxKang > 0, tgt.kang >= 0, tgt.kang > maxKang { return false }
                return true
            }) else {
                onLog("无符合筛选的对手，刷新…")
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            if yaoLi || yaoMin || yaoSu, !selfUin.isEmpty {
                if yaoLi {
                    _ = await LedouCGI.getPetPk(
                        cmd: "use", extra: ["selfuin": selfUin, "id": "3020"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                }
                if yaoMin {
                    _ = await LedouCGI.getPetPk(
                        cmd: "use", extra: ["selfuin": selfUin, "id": "3021"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                }
                if yaoSu {
                    _ = await LedouCGI.getPetPk(
                        cmd: "use", extra: ["selfuin": selfUin, "id": "3022"], cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                }
            }
            if daTie {
                _ = await LedouCGI.getPetPk(
                    cmd: "blacksmith", extra: ["op": "5"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
            }

            let zone: String = {
                if let rank = CombatLog.jsonField(page, "rank") {
                    let digits = rank.filter(\.isNumber)
                    if !digits.isEmpty { return digits }
                }
                if let z = firstGroup(#""zone"\s*:\s*"?(\d+)"?"#, in: page) { return z }
                return "1"
            }()
            let idx = pick.idx.isEmpty ? "\(pick.pos)" : pick.idx
            onLog("挑战 \(pick.name.isEmpty ? pick.uin : pick.name)@\(pick.uin)")
            let (_, fight) = await LedouCGI.getPhonePk(
                cmd: "dragonphoenix",
                extra: [
                    "op": "pk",
                    "zone": zone,
                    "uin": pick.uin,
                    "idx": idx,
                    "self": selfUin.isEmpty ? "1" : selfUin,
                ],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            var fmsg = CombatLog.fromBody(fight)
            if fmsg.isEmpty {
                fmsg = CombatLog.prefer(fight, "打翻在地", "你干掉了", "惜败", "战胜")
            }
            onLog(fmsg.isEmpty ? "已挑战" : fmsg)
            fought += 1
            if skipLose, fmsg.contains("惜败") || fmsg.contains("不敌") || fmsg.contains("战败") {
                zhanBai.insert(pick.uin)
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        let tip = "龙凰论武结束，挑战\(fought)场"
        onLog(tip)
        return tip
    }

    private static func parseTargets(_ page: String) -> [Target] {
        guard let re = try? NSRegularExpression(
            pattern: #"\{[^{}]*?"uin"\s*:\s*"(\d+)"[^{}]*?\}"#
        ) else { return [] }
        let ns = page as NSString
        let matches = re.matches(in: page, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m -> Target? in
            let block = ns.substring(with: m.range)
            guard let uin = firstGroup(#""uin"\s*:\s*"(\d+)""#, in: block) else { return nil }
            let name = firstGroup(#""name"\s*:\s*"((?:\\.|[^"\\])*)""#, in: block) ?? ""
            let pos = Int(firstGroup(#""pos"\s*:\s*(\d+)"#, in: block) ?? "") ?? 0
            let shen = Int(firstGroup(#""shenQi"\s*:\s*(\d+)"#, in: block) ?? "") ?? 0
            let chuan = Int(firstGroup(#""chuan"\s*:\s*(-?\d+)"#, in: block) ?? "") ?? -1
            let kang = Int(firstGroup(#""kang"\s*:\s*(-?\d+)"#, in: block) ?? "") ?? -1
            let idx = firstGroup(#""id"\s*:\s*"(\d+)""#, in: block) ?? "0"
            return Target(uin: uin, name: name, pos: pos, shenQi: shen, chuan: chuan, kang: kang, idx: idx)
        }
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
