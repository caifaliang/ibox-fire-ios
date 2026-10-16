import Foundation

/// 真源：`MoreExtraActions.farmBangPaiWaKuang` — 本号挖矿一轮。
enum BangPaiWaKuangActions {
    static let fid = "bangpai_wakuang"
    private static let gapNs: UInt64 = 80_000_000

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        func on(_ key: String) -> Bool { t.getBool(fid, key) }

        let (_, info) = await LedouCGI.getPhonePk(
            cmd: "totalinfo", extra: ["type": "1"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)

        if buffZero(info, "大力丸") {
            if on("cb_dlw_z") { await useItem("3020", "大力丸(赠)", cookie: cookie, onLog: onLog) }
            else if on("cb_dlw") { await useItem("3016", "大力丸", cookie: cookie, onLog: onLog) }
        }
        if buffZero(info, "迅捷珠") {
            if on("cb_xjz_z") { await useItem("3021", "迅捷珠(赠)", cookie: cookie, onLog: onLog) }
            else if on("cb_xjz") { await useItem("3017", "迅捷珠", cookie: cookie, onLog: onLog) }
        }
        if buffZero(info, "风之息") {
            if on("cb_fzx_z") { await useItem("3022", "风之息(赠)", cookie: cookie, onLog: onLog) }
            else if on("cb_fzx") { await useItem("3018", "风之息", cookie: cookie, onLog: onLog) }
        }

        if on("cb_da_tie") {
            let (_, iron) = await LedouCGI.getPetPk(
                cmd: "blacksmith", extra: ["op": "5"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("打铁：\(CombatLog.fromBody(iron).ifBlankMe("已请求"))")
        }

        if on("cb_yong_bing") {
            let n1 = t.getString(fid, "yb_wk_1")
            let n2 = t.getString(fid, "yb_wk_2")
            if n1.isEmpty && n2.isEmpty {
                onLog("已勾选挖矿佣兵，请填写佣兵名")
            } else {
                if !n1.isEmpty { _ = await equipMercenary(n1, trigger: 1, cookie: cookie, onLog: onLog) }
                if !n2.isEmpty { _ = await equipMercenary(n2, trigger: 2, cookie: cookie, onLog: onLog) }
            }
        }

        let (_, members) = await LedouCGI.getPetPk(cmd: "viewmember", cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let selfUin = LoginURLs.extractQq(cookie) ?? ""
        let memberRows = jsonChunks(members, "list")
        if let first = memberRows.first {
            let guardian = field(first, "name")
            onLog("守护神：\(guardian)")
            if !guardian.isEmpty, guardian != "青龙" {
                onLog("守护神不是青龙，跳过开矿")
            } else {
                let me = memberRows.first(where: { field($0, "uin") == selfUin })
                let pos = Int(field(me ?? "", "pos")) ?? -1
                if me != nil, pos <= 0 || pos >= 4 {
                    onLog("职位不符（需帮主/副帮/护法），仅做已开矿洞与周边")
                }
            }
        }

        var st = await LedouCGI.getPetPk(cmd: "factionmine", cookie: cookie).1
        try? await Task.sleep(nanoseconds: gapNs)
        var msg = CombatLog.fromBody(st).ifBlankMe(field(st, "msg"))
        let idle = msg.contains("未开始") || msg.contains("未开启") || msg.contains("尚未")
            || (jsonInt(st, "current_hp") == nil && !msg.contains("挑战") && !st.contains("npc_name"))
        if idle || (jsonInt(st, "current_hp") == nil && !st.contains("\"npc_name\"")) {
            let (_, started) = await LedouCGI.getPetPk(
                cmd: "factionmine",
                extra: ["op": "start", "floor": "1", "mode": "1"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("开启简单矿洞：\(CombatLog.fromBody(started).ifBlankMe("已请求开矿"))")
            st = await LedouCGI.getPetPk(cmd: "factionmine", cookie: cookie).1
            try? await Task.sleep(nanoseconds: gapNs)
            msg = CombatLog.fromBody(st).ifBlankMe(field(st, "msg"))
        }

        var fights = 0
        while fights < 30 {
            let hp = jsonInt(st, "current_hp") ?? 0
            let npc = field(st, "npc_name")
            if hp <= 0 && npc.isEmpty { break }
            if hp <= 0 {
                onLog(npc.isEmpty ? "Boss 已击败" : "\(npc) 已击败")
                break
            }
            onLog("挑战 \(npc) 血量\(hp)")
            let (_, fight) = await LedouCGI.getPhonePk(
                cmd: "factionmine", extra: ["op": "fight"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: 200_000_000)
            let fm = CombatLog.fromBody(fight).ifBlankMe("已挑战")
            onLog(fm)
            fights += 1
            if (fm.contains("次数") && (fm.contains("用尽") || fm.contains("不足")))
                || fm.contains("没有权限") || fm.contains("登陆校验")
            {
                break
            }
            st = await LedouCGI.getPetPk(cmd: "factionmine", cookie: cookie).1
            try? await Task.sleep(nanoseconds: gapNs)
        }

        let (_, reward) = await LedouCGI.getPhonePk(
            cmd: "factionmine", extra: ["op": "reward"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let rm = CombatLog.fromBody(reward)
        if !rm.isEmpty { onLog("领奖：\(rm)") }

        if on("cb_yong_bing_ct") {
            let n1 = t.getString(fid, "yb_ct_1")
            let n2 = t.getString(fid, "yb_ct_2")
            if !n1.isEmpty { _ = await equipMercenary(n1, trigger: 1, cookie: cookie, onLog: onLog) }
            if !n2.isEmpty { _ = await equipMercenary(n2, trigger: 2, cookie: cookie, onLog: onLog) }
        }
        if on("cb_ji_tan") {
            _ = await MoreExtraActions.farmJiTan(cookie: cookie, onLog: onLog)
        }
        if on("cb_shang_hui") {
            await claimCorpGifts(cookie: cookie, onLog: onLog)
        }

        let tip = "帮派挖矿本轮结束"
        onLog(tip)
        return tip
    }

    // MARK: - helpers

    private static func claimCorpGifts(cookie: String, onLog: @escaping (String) -> Void) async {
        var claimed = 0
        var done = false
        var loops = 0
        while !done, loops < 8 {
            loops += 1
            let (_, corp) = await LedouCGI.getPetPk(
                cmd: "fac_corp", extra: ["page": "1", "op": "0"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let gifts = jsonChunks(corp, "giftInfo")
            if gifts.isEmpty {
                if claimed == 0 {
                    onLog("商会：\(CombatLog.fromBody(corp).ifBlankMe("无可领礼包"))")
                }
                done = true
                continue
            }
            let g = gifts[0]
            let type = field(g, "type")
            let giftId = field(g, "giftId")
            if type.isEmpty || giftId.isEmpty {
                done = true
                continue
            }
            let (_, take) = await LedouCGI.getPetPk(
                cmd: "fac_corp",
                extra: ["op": "3", "type": type, "giftId": giftId],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let tm = CombatLog.fromBody(take).ifBlankMe("已领取")
            onLog("商会：\(tm)")
            claimed += 1
            if tm.contains("入帮24小时") || tm.contains("登陆校验") || tm.contains("没有") {
                done = true
            }
        }
    }

    private static func equipMercenary(
        _ wantName: String,
        trigger: Int,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> Bool {
        let name = wantName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return false }
        let (_, list) = await LedouCGI.getPetPk(
            cmd: "newmercenary", extra: ["sub": "0"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let chunks = jsonChunks(list, "array")
        let hit = chunks.first(where: {
            field($0, "name").contains(name) && (Int(field($0, "trigger")) ?? -1) == trigger
        }) ?? chunks.first(where: { field($0, "name").contains(name) })
        guard let hit else {
            onLog("佣兵未找到：\(name)")
            return false
        }
        let id = field(hit, "id")
        if id.isEmpty { return false }
        if (Int(field(hit, "status")) ?? 0) == 1 {
            onLog("佣兵已装备：\(field(hit, "name"))")
            return true
        }
        let (_, r) = await LedouCGI.getPetPk(
            cmd: "newmercenary", extra: ["sub": "1", "id": id], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        onLog("\(field(hit, "name"))：\(CombatLog.fromBody(r).ifBlankMe("已换装"))")
        return true
    }

    private static func useItem(
        _ id: String,
        _ label: String,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async {
        let uin = LoginURLs.extractQq(cookie) ?? ""
        if uin.isEmpty {
            onLog("\(label)：未识别 selfuin")
            return
        }
        let (_, r) = await LedouCGI.getPetPk(
            cmd: "use", extra: ["selfuin": uin, "id": id], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        onLog("\(label)：\(CombatLog.fromBody(r).ifBlankMe("已请求\(id)"))")
    }

    private static func buffZero(_ html: String, _ name: String) -> Bool {
        let line = html.split(whereSeparator: { $0 == "\n" || $0 == "<" })
            .map(String.init)
            .first(where: { $0.contains(name) })
            ?? (html.contains(name) ? html : nil)
        guard let line else { return false }
        return line.contains("剩0次") || line.contains("剩 0 次")
    }

    private static func jsonChunks(_ body: String, _ arrayName: String) -> [String] {
        guard let keyAt = body.range(of: "\"\(arrayName)\"")?.lowerBound,
              let openRel = body[keyAt...].firstIndex(of: "[")
        else { return [] }
        var depth = 0
        var end = openRel
        var i = openRel
        while i < body.endIndex {
            let c = body[i]
            if c == "[" { depth += 1 }
            if c == "]" {
                depth -= 1
                if depth == 0 {
                    end = i
                    break
                }
            }
            i = body.index(after: i)
        }
        let arr = String(body[openRel...end])
        var out: [String] = []
        let re = try? NSRegularExpression(pattern: #"\{[^{}]*\}"#)
        let ns = arr as NSString
        re?.enumerateMatches(in: arr, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            out.append(ns.substring(with: m.range))
        }
        return out
    }

    private static func field(_ body: String, _ key: String) -> String {
        let re = try? NSRegularExpression(
            pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"([^\"]*)\""
        )
        let ns = body as NSString
        if let m = re?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        let re2 = try? NSRegularExpression(
            pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*([^,\"}\\s]+)"
        )
        if let m = re2?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        return ""
    }

    private static func jsonInt(_ body: String, _ key: String) -> Int? {
        let re = try? NSRegularExpression(
            pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"?(-?\\d+)\"?"
        )
        let ns = body as NSString
        if let m = re?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return Int(ns.substring(with: m.range(at: 1)))
        }
        return nil
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
