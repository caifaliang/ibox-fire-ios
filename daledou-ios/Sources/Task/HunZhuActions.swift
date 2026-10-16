import Foundation

/// 真源：`MoreExtraActions.farmHunZhu` — viewupgradepearl / composepearl / upgradepearls。
enum HunZhuActions {
    private static let gapNs: UInt64 = 500_000_000

    private struct HunZhu {
        let name: String
        let type: Int
        let exchangeType: String
    }

    /// 与笔记 composepearl exchangetype 对齐。帅帅=2002。
    private static let hunZhuList: [HunZhu] = [
        .init(name: "剑军", type: 1, exchangeType: "2001"),
        .init(name: "菜菜", type: 2, exchangeType: "2000"),
        .init(name: "月璇", type: 3, exchangeType: "2004"),
        .init(name: "帅帅", type: 4, exchangeType: "2002"),
        .init(name: "血灵", type: 5, exchangeType: "2005"),
        .init(name: "月影", type: 6, exchangeType: "2003"),
        .init(name: "教主", type: 7, exchangeType: "2006"),
    ]

    private static let hunZhuCosts = [5, 3, 3, 3, 6, 2, 2]

    private struct HunGem {
        let id: String
        let level: Int
        let num: Int
        let upgradeCost: Int
    }

    /// 数量与珠种在活跃设置「魂珠升级」里选。
    static func farmHunZhu(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let pearl = hunZhuSelected(t)
        let level = hunZhuLevel(t)
        let raw = t.getString("huoyue", "ed_hzsj_num").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let want = Int(raw), want > 0 else {
            let tip = "请先输入魂珠的数量"
            onLog(tip)
            return tip
        }
        onLog("魂珠升级 \(pearl.name) 目标\(level)级×\(want)")
        guard var gems = await loadHunZhu(type: pearl.type, cookie: cookie, onLog: onLog) else {
            return "没有获取到魂珠数据，请切换重试！"
        }
        if gems.contains(where: { $0.level == level && $0.num >= want }) {
            let tip = "您要升级的魂珠数量，好像已经够了呢"
            onLog(tip)
            return tip
        }
        for step in 0..<80 {
            guard let loaded = await loadHunZhu(type: pearl.type, cookie: cookie, onLog: onLog) else {
                return "魂珠升级中断"
            }
            gems = loaded
            if gems.contains(where: { $0.level == level && $0.num >= want }) {
                let tip = "升级结束"
                onLog(tip)
                return tip
            }
            guard let pickIdx = gems.indices.reversed().first(where: { i in
                let g = gems[i]
                return g.level < level && g.num >= g.upgradeCost
            }) else {
                let tip = "升级结束（材料不足）"
                onLog(tip)
                return tip
            }
            let pick = gems[pickIdx]
            // 列表第 0 项是碎片 → composepearl；其余 → upgradepearls
            let (_, body): (Int, String)
            if pickIdx == 0 {
                (_, body) = await LedouCGI.getPetPk(
                    cmd: "composepearl",
                    extra: ["exchangetype": pearl.exchangeType],
                    cookie: cookie
                )
            } else {
                (_, body) = await LedouCGI.getPetPk(
                    cmd: "upgradepearls",
                    extra: ["pearl": pick.id],
                    cookie: cookie
                )
            }
            let msg = CombatLog.fromBody(body).ifBlankMe(LedouCGI.shortBody(body, code: 200))
            onLog("魂珠步\(step + 1):\(String(msg.prefix(48)))")
            try? await Task.sleep(nanoseconds: gapNs)
        }
        return "魂珠升级步数到顶"
    }

    private static func hunZhuSelected(_ t: FeatureToggleStore) -> HunZhu {
        let keys = (1...7).map { "rb_hzsj_\($0)" }
        let idx = keys.firstIndex(where: { t.getBool("huoyue", $0) }) ?? 0
        return hunZhuList.indices.contains(idx) ? hunZhuList[idx] : hunZhuList[0]
    }

    private static func hunZhuLevel(_ t: FeatureToggleStore) -> Int {
        for lv in 1...7 where t.getBool("huoyue", "rb_hzsj_lv_\(lv)") { return lv }
        return 1
    }

    private static func loadHunZhu(
        type: Int,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> [HunGem]? {
        let (_, body) = await LedouCGI.getPetPk(
            cmd: "viewupgradepearl",
            extra: ["type": "\(type)"],
            cookie: cookie
        )
        if body.contains("系统繁忙") {
            try? await Task.sleep(nanoseconds: 800_000_000)
            return await loadHunZhu(type: type, cookie: cookie, onLog: onLog)
        }
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            onLog("魂珠解析失败")
            return nil
        }
        if let result = root["result"] {
            let code: Int
            if let i = result as? Int { code = i }
            else if let s = result as? String, let i = Int(s) { code = i }
            else { code = -1 }
            if code != 0 {
                let msg = (root["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                onLog(msg.isEmpty ? "魂珠查询失败" : msg)
                return nil
            }
        }
        var out: [HunGem] = []
        if let pieceArr = root["piece"] as? [[String: Any]], let piece = pieceArr.first {
            out.append(HunGem(
                id: stringField(piece, "id") ?? "",
                level: intField(piece, "level"),
                num: intField(piece, "num"),
                upgradeCost: hunZhuCosts[0]
            ))
        }
        let info = root["info"] as? [[String: Any]] ?? []
        for (i, o) in info.enumerated() {
            let cost: Int
            if i != 6 {
                cost = hunZhuCosts.indices.contains(i + 1) ? hunZhuCosts[i + 1] : 2
            } else {
                cost = intField(o, "upgrade_cost").nonZero(2)
            }
            out.append(HunGem(
                id: stringField(o, "id") ?? "",
                level: intField(o, "level"),
                num: intField(o, "num"),
                upgradeCost: cost
            ))
        }
        return out
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

private extension Int {
    func nonZero(_ fallback: Int) -> Int { self > 0 ? self : fallback }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
