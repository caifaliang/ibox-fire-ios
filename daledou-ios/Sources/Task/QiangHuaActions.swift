import Foundation

/// 真源：`HuanZhuangQiangHuaScreens.kt` enhance CGI（自动强化）。
enum QiangHuaActions {
    static let fid = "zidong_qianghua"
    static let slots = ["神兵", "神铠", "神羽", "神兽", "神饰", "神履"]
    static let bodyGoods = ["3573", "3574", "1100", "1200", "1201", "1205"]
    static let skillGoods = "1206"
    static let zjTypes = ["投掷", "小型", "中型", "大型"]
    static let smNames = ["夔牛经", "饕餮经", "烛龙经", "黄鸟经"]

    private static let gapNs: UInt64 = 80_000_000

    struct SlotInfo: Identifiable {
        var id: Int { index }
        let index: Int
        let name: String
        let displayName: String
        let level: Int
        let fc: String
        let goodName: String
        let goodNeed: Int
        let goodHave: Int
        let maxed: Bool
        let skillIds: [String]
    }

    // MARK: - Load

    static func loadSlots(cookie: String) async -> [SlotInfo] {
        let (_, body) = await LedouCGI.getPetPk(cmd: "outfit", extra: ["op": "0"], cookie: cookie)
        return parseOutfits(body)
    }

    // MARK: - 神装

    /// mode 0=本体 1=技能；once=true →×1 else ×10
    static func enhanceShenZhuang(
        slot: Int,
        mode: Int,
        skillIdx: Int,
        once: Bool,
        autoBuy: Bool,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let slotClamped = max(0, min(5, slot))
        let goods = mode == 0
            ? (bodyGoods.indices.contains(slotClamped) ? bodyGoods[slotClamped] : "3573")
            : skillGoods
        let need = once ? 1 : 10
        if autoBuy {
            _ = await LedouCGI.getPetPk(
                cmd: "exchange",
                extra: ["subtype": "2", "type": goods, "times": "\(need)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        let extra: [String: String]
        if mode == 0 {
            extra = ["op": once ? "1" : "5", "magic_outfit_id": "\(slotClamped)"]
        } else {
            let (_, page) = await LedouCGI.getPetPk(cmd: "outfit", extra: ["op": "0"], cookie: cookie)
            guard let skillId = resolveSkillId(page: page, outfitIdx: slotClamped, skillIdx: skillIdx) else {
                let name = slots.indices.contains(slotClamped) ? slots[slotClamped] : "?"
                return "未找到 \(name) 技能\(skillIdx + 1)"
            }
            extra = ["op": once ? "3" : "8", "magic_skill_id": skillId]
        }

        let (_, body) = await LedouCGI.getPetPk(cmd: "outfit", extra: extra, cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        if let stop = guardAutoBuy(body, autoBuy: autoBuy) {
            onLog(stop)
            return stop
        }
        let msg = CombatLog.fromBody(body).ifBlankMe(LedouCGI.shortBody(body, code: 200))
        let kind = mode == 0 ? "本体" : "技能\(skillIdx + 1)"
        let name = slots.indices.contains(slotClamped) ? slots[slotClamped] : "?"
        let line = "\(name) \(kind) \(once ? "×1" : "×10")：\(msg.ifBlankMe("已请求"))"
        onLog(line)
        return line
    }

    // MARK: - 专精

    static func enhanceZhuanJing(
        typeId: Int,
        times: Int,
        autoBuy: Bool,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let tid = max(0, min(3, typeId))
        var last = ""
        for _ in 0..<max(1, times) {
            let (_, body) = await LedouCGI.getPetPk(
                cmd: "weapon_specialize",
                extra: ["op": "1", "type_id": "\(tid)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if let stop = guardAutoBuy(body, autoBuy: autoBuy) {
                onLog(stop)
                return stop
            }
            last = CombatLog.fromBody(body).ifBlankMe(LedouCGI.shortBody(body, code: 200)).ifBlankMe("已请求")
        }
        let label = zjTypes.indices.contains(tid) ? zjTypes[tid] : "?"
        let line = times == 1 ? "专精\(label)：\(last)" : "专精×\(times)：\(last)"
        onLog(line)
        return line
    }

    // MARK: - 奥义 / 铭刻（完整 URL）

    static func enhanceByUrl(
        url: String,
        label: String,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else {
            let tip = "请先填写\(label) URL"
            onLog(tip)
            return tip
        }
        let (_, body) = await LedouCGI.getHref(u, cookie: cookie)
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(body).ifBlankMe(LedouCGI.shortBody(body, code: 200)).ifBlankMe("已请求")
        let line = "\(label)：\(msg)"
        onLog(line)
        return line
    }

    // MARK: - 神魔录

    static func queryShenMo(id: Int, cookie: String, onLog: @escaping (String) -> Void) async -> String {
        let sid = max(1, min(4, id))
        let (_, body) = await LedouCGI.getPetPk(
            cmd: "ancient_god", extra: ["op": "1", "id": "\(sid)"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(body).ifBlankMe(LedouCGI.shortBody(body, code: 200)).ifBlankMe("已查询")
        onLog("神魔查询：\(msg)")
        return msg
    }

    static func upgradeShenMo(
        id: Int,
        autoBuy: Bool,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let sid = max(1, min(4, id))
        if autoBuy {
            _ = await LedouCGI.getPetPk(
                cmd: "exchange",
                extra: ["subtype": "2", "type": "1267", "times": "1"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
        }
        let (_, body) = await LedouCGI.getPetPk(
            cmd: "ancient_god",
            extra: ["op": "3", "id": "\(sid)", "times": "1"],
            cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let msg = CombatLog.fromBody(body).ifBlankMe(LedouCGI.shortBody(body, code: 200)).ifBlankMe("已请求")
        let name = smNames.indices.contains(sid - 1) ? smNames[sid - 1] : "神魔"
        let line = "\(name)升级：\(msg)"
        onLog(line)
        return line
    }

    // MARK: - helpers

    private static func guardAutoBuy(_ body: String, autoBuy: Bool) -> String? {
        if autoBuy { return nil }
        if body.contains("auto_buy"), body.contains("\"1\"") {
            return "会自动买材料，已停（可开「自动兑材料」）"
        }
        return nil
    }

    static func parseOutfits(_ body: String) -> [SlotInfo] {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["magic_outfits"] as? [Any]
        else { return padSlots([]) }

        var indices: [Int] = []
        var i = 0
        while i < arr.count {
            indices.append(i)
            i += 2
        }
        if indices.isEmpty {
            indices = Array(0..<arr.count)
        }
        indices = Array(indices.prefix(6))

        var out: [SlotInfo] = []
        for (slotIdx, arrIdx) in indices.enumerated() {
            guard arrIdx < arr.count, let o = arr[arrIdx] as? [String: Any] else { continue }
            var skillIds: [String] = []
            if let skills = o["skills"] as? [[String: Any]] {
                for s in skills {
                    if let sid = stringField(s, "skill_id"), !sid.isEmpty, sid != "0" {
                        skillIds.append(sid)
                    }
                }
            }
            let lv = intField(o, "level")
            let rate = stringField(o, "update_success_rate") ?? ""
            out.append(SlotInfo(
                index: slotIdx,
                name: slots.indices.contains(slotIdx) ? slots[slotIdx] : "部位",
                displayName: (stringField(o, "magic_outfit_name") ?? stringField(o, "name") ?? "")
                    .ifBlankMe(slots.indices.contains(slotIdx) ? slots[slotIdx] : "部位"),
                level: lv,
                fc: stringField(o, "fighting_capacity") ?? "",
                goodName: stringField(o, "update_good_name") ?? "",
                goodNeed: intField(o, "update_consume"),
                goodHave: intField(o, "update_good_have"),
                maxed: lv >= 10 || rate.contains("最高"),
                skillIds: skillIds
            ))
        }
        return padSlots(out)
    }

    private static func padSlots(_ list: [SlotInfo]) -> [SlotInfo] {
        var out = list
        while out.count < 6 {
            let i = out.count
            out.append(SlotInfo(
                index: i, name: slots[i], displayName: slots[i],
                level: 0, fc: "", goodName: "", goodNeed: 0, goodHave: 0,
                maxed: false, skillIds: []
            ))
        }
        return out
    }

    private static func resolveSkillId(page: String, outfitIdx: Int, skillIdx: Int) -> String? {
        let slots = parseOutfits(page)
        guard outfitIdx < slots.count else { return nil }
        let ids = slots[outfitIdx].skillIds
        guard skillIdx < ids.count else { return nil }
        return ids[skillIdx]
    }

    private static func stringField(_ o: [String: Any], _ key: String) -> String? {
        if let s = o[key] as? String { return s }
        if let n = o[key] as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intField(_ o: [String: Any], _ key: String) -> Int {
        if let i = o[key] as? Int { return i }
        if let s = o[key] as? String, let i = Int(s) { return i }
        if let n = o[key] as? NSNumber { return n.intValue }
        return 0
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
