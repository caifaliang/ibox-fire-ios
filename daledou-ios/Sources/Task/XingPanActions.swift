import Foundation

/// 真源：`MoreExtraActions` 星盘换装 / 星盘升级。
enum XingPanActions {
    private static let gapNs: UInt64 = 80_000_000

    private struct XingShi {
        let name: String
        let pointCost: Int
        let exchangeId: Int
        let gemType: Int
    }

    private static let xingShiList: [XingShi] = [
        .init(name: "日曜石", pointCost: 48, exchangeId: 1237, gemType: 1),
        .init(name: "玛瑙石", pointCost: 40, exchangeId: 1234, gemType: 2),
        .init(name: "迅捷石", pointCost: 40, exchangeId: 1235, gemType: 3),
        .init(name: "月光石", pointCost: 32, exchangeId: 1238, gemType: 4),
        .init(name: "翡翠石", pointCost: 32, exchangeId: 1233, gemType: 5),
        .init(name: "紫黑玉", pointCost: 40, exchangeId: 1236, gemType: 6),
        .init(name: "狂暴石", pointCost: 60, exchangeId: 101, gemType: 7),
        .init(name: "神愈石", pointCost: 60, exchangeId: 104, gemType: 8),
    ]

    private struct XingGem {
        let id: String
        let level: Int
        let num: Int
        let upgradeCost: Int64
    }

    // MARK: - 星盘升级

    /// 真源：`farmXingPan` — 兑换一级石再逐级 upgrade（设置在活跃「星盘升级」）。
    static func farmXingPan(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let stone = xingShiSelected(t)
        let level = xingPanLevel(t)
        let raw = t.getString("huoyue", "ed_xpsj_num").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let want = Int(raw), want > 0 else {
            let tip = "请先输入星石的数量"
            onLog(tip)
            return tip
        }
        onLog("星盘升级 \(stone.name) 目标\(level)级×\(want)")
        guard let gems = await loadXingPanGems(gemType: stone.gemType, cookie: cookie, onLog: onLog),
              !gems.isEmpty
        else {
            let tip = "没有获取到星盘数据，请切换重试！"
            onLog(tip)
            return tip
        }
        let needL1 = stonesNeeded(gems: gems, want: Int64(want), level: level)
        if needL1 < 0 {
            onLog("您要兑换的石头数量，好像已经够了呢")
            return await upgradeXingPan(
                gemType: stone.gemType, level: level, want: want, cookie: cookie, onLog: onLog
            )
        }
        let points = await loadXingPanPoints(gemType: stone.gemType, cookie: cookie, onLog: onLog)
        let cost = Int64(stone.pointCost) * needL1
        let left = points - cost
        if left <= 0 {
            let tip = "您的积分不太够用哦，缺少\(left)积分！"
            onLog(tip)
            return tip
        }
        onLog("共需要兑换[\(needL1)]个一级石头，需要积分:[\(cost)],剩余积分[\(left)]")
        guard await exchangeXingPan(stone: stone, times: needL1, cookie: cookie, onLog: onLog) else {
            return "星盘兑换失败"
        }
        return await upgradeXingPan(
            gemType: stone.gemType, level: level, want: want, cookie: cookie, onLog: onLog
        )
    }

    // MARK: - 星盘换装

    /// 按活跃设置 `ed_xphz_1..6` 目标数拆卸再镶嵌；空目标且勾选 snap 则先落盘当前方案。
    static func farmXingPanHuanZhuang(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        var target = [0, 0, 0, 0, 0, 0, 0]
        for i in 1...6 {
            target[i] = Int(t.getString("huoyue", "ed_xphz_\(i)").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        let snap = t.getBool("huoyue", "cb_xphz_snap")
        let targetSum = target.dropFirst().reduce(0, +)
        if targetSum <= 0, !snap {
            let tip = "请先在一键设置「星盘换装」里填写目标数，或勾选空目标时用当前星盘覆盖"
            onLog(tip)
            return tip
        }

        onLog("星盘换装开始…")
        guard var board = await loadAstrolabeIndex(cookie: cookie, onLog: onLog) else {
            return "星盘换装：拉取失败"
        }
        let current = countXingPan(board)
        if targetSum <= 0, snap {
            for i in 1...6 {
                target[i] = current[i]
                t.setString("huoyue", "ed_xphz_\(i)", "\(current[i])")
            }
            let tip = "已记录当前星盘为方案：\(formatXpCounts(target))"
            onLog(tip)
            return "已保存当前星盘方案，请按需改数字后再点一次换装"
        }
        onLog("目标\(formatXpCounts(target)) 当前\(formatXpCounts(current))")

        var removed = 0
        for star in board.stars where star.activated == 1 {
            let last = max(0, star.sockets.count - 1)
            for si in 0..<last {
                let sock = star.sockets[si]
                if sock.desc.isEmpty { continue }
                var (_, body) = await LedouCGI.getPetPk(
                    cmd: "astrolabe",
                    extra: ["op": "removeinserted", "star": star.id, "socket": "\(si)"],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                if body.contains("系统繁忙") {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    (_, body) = await LedouCGI.getPetPk(
                        cmd: "astrolabe",
                        extra: ["op": "removeinserted", "star": star.id, "socket": "\(si)"],
                        cookie: cookie
                    )
                    try? await Task.sleep(nanoseconds: gapNs)
                }
                removed += 1
                if removed > 80 { break }
            }
            if removed > 80 { break }
        }
        onLog("已拆卸约\(removed)槽")

        guard let refreshed = await loadAstrolabeIndex(cookie: cookie, onLog: onLog) else {
            return "星盘换装：拆卸后刷新失败"
        }
        board = refreshed
        var now = countXingPan(board)
        var inserted = 0
        var fail = 0
        var guardCount = 0
        while guardCount < 90 {
            guardCount += 1
            if (1...6).allSatisfy({ now[$0] >= target[$0] }) { break }
            guard let slot = findEmptySocket(board) else { break }
            guard let gemType = pickGemType(
                kind: slot.socket.kind,
                desc: slot.socket.desc,
                target: target,
                now: now
            ) else {
                fail += 1
                slot.socket.desc = "__skip__"
                continue
            }
            let (_, view) = await LedouCGI.getPetPk(
                cmd: "astrolabe",
                extra: [
                    "op": "viewinsert",
                    "gem_kind": slot.socket.kind,
                    "star_id": slot.starId,
                    "socket": "\(slot.socketIndex)",
                    "gem_type": "\(gemType)",
                ],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if view.contains("系统繁忙") { continue }
            guard let gemId = pickInsertGemId(view), !gemId.isEmpty else {
                fail += 1
                slot.socket.desc = "__skip__"
                continue
            }
            let (_, ins) = await LedouCGI.getPetPk(
                cmd: "astrolabe",
                extra: [
                    "op": "insert",
                    "star": slot.starId,
                    "socket": "\(slot.socketIndex)",
                    "gem": gemId,
                ],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if ins.contains("系统繁忙") { continue }
            now[gemType] += 1
            inserted += 1
            slot.socket.desc = gemTypeToDesc(gemType)
            if inserted % 10 == 0 {
                onLog("镶嵌中[\(inserted)] \(formatXpCounts(now))")
            }
        }
        let ok = (1...6).allSatisfy { now[$0] >= target[$0] }
        let tip = ok
            ? "星盘换装完成！镶嵌\(inserted)"
            : "星盘换装失败，部分星石没有镶嵌成功！成\(inserted)/跳\(fail) 现\(formatXpCounts(now))"
        onLog(tip)
        return tip
    }

    // MARK: - Models

    private final class XpSock {
        let kind: String
        var desc: String
        let gem: String
        let level: String
        init(kind: String, desc: String, gem: String, level: String) {
            self.kind = kind
            self.desc = desc
            self.gem = gem
            self.level = level
        }
    }

    private struct XpStar {
        let id: String
        let activated: Int
        let sockets: [XpSock]
    }

    private struct XpBoard {
        var stars: [XpStar]
    }

    private struct XpSocket {
        let starId: String
        let socketIndex: Int
        let socket: XpSock
    }

    // MARK: - CGI / parse

    private static func loadAstrolabeIndex(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> XpBoard? {
        for _ in 0..<6 {
            let (_, body) = await LedouCGI.getPetPk(
                cmd: "astrolabe", extra: ["op": "index"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if body.contains("系统繁忙") { continue }
            if let board = parseAstrolabeIndex(body) { return board }
            let msg = CombatLog.fromBody(body)
            onLog(msg.isEmpty ? "星盘 index 解析失败" : msg)
            return nil
        }
        return nil
    }

    private static func parseAstrolabeIndex(_ body: String) -> XpBoard? {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let result = root["result"] {
            let code: Int
            if let i = result as? Int { code = i }
            else if let s = result as? String, let i = Int(s) { code = i }
            else { code = -1 }
            if code != 0 { return nil }
        }
        guard let starsArr = root["stars"] as? [[String: Any]] else { return nil }
        var stars: [XpStar] = []
        for s in starsArr {
            let socksArr = s["sockets"] as? [[String: Any]] ?? []
            let socks: [XpSock] = socksArr.map { o in
                XpSock(
                    kind: stringField(o, "kind") ?? "",
                    desc: stringField(o, "desc") ?? "",
                    gem: stringField(o, "gem") ?? "",
                    level: stringField(o, "level") ?? ""
                )
            }
            stars.append(XpStar(
                id: stringField(s, "id") ?? "",
                activated: intField(s, "activated"),
                sockets: socks
            ))
        }
        return XpBoard(stars: stars)
    }

    private static func countXingPan(_ board: XpBoard) -> [Int] {
        var c = [0, 0, 0, 0, 0, 0, 0]
        for star in board.stars {
            let last = max(0, star.sockets.count - 1)
            for i in 0..<last {
                let d = star.sockets[i].desc
                if d.contains("固定伤害") { c[1] += 1 }
                else if d.contains("命中") { c[2] += 1 }
                else if d.contains("速度") { c[3] += 1 }
                else if d.contains("固定减免") { c[4] += 1 }
                else if d.contains("闪避") { c[5] += 1 }
                else if d.contains("生命") { c[6] += 1 }
            }
        }
        return c
    }

    private static func formatXpCounts(_ c: [Int]) -> String {
        "日\(c[1])玛\(c[2])迅\(c[3])月\(c[4])翡\(c[5])紫\(c[6])"
    }

    private static func findEmptySocket(_ board: XpBoard) -> XpSocket? {
        for star in board.stars where star.activated == 1 {
            let last = max(0, star.sockets.count - 1)
            for i in 0..<last {
                let sock = star.sockets[i]
                if sock.desc.isEmpty {
                    return XpSocket(starId: star.id, socketIndex: i, socket: sock)
                }
            }
        }
        return nil
    }

    private static func pickGemType(kind: String, desc: String, target: [Int], now: [Int]) -> Int? {
        let group = kind == "1" ? [1, 2, 3] : [4, 5, 6]
        let ban: [Int: String] = [
            1: "固定伤害", 2: "命中", 3: "速度",
            4: "固定减免", 5: "闪避", 6: "生命",
        ]
        return group
            .filter { now[$0] < target[$0] }
            .filter { ban[$0].map { !desc.contains($0) } ?? true }
            .max(by: { (target[$0] - now[$0]) < (target[$1] - now[$1]) })
    }

    private static func gemTypeToDesc(_ type: Int) -> String {
        switch type {
        case 1: return "固定伤害"
        case 2: return "命中"
        case 3: return "速度"
        case 4: return "固定减免"
        case 5: return "闪避"
        case 6: return "生命"
        default: return "石"
        }
    }

    private static func pickInsertGemId(_ viewBody: String) -> String? {
        guard let data = viewBody.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gems = root["gems"] as? [[String: Any]]
        else { return nil }
        for g in gems.reversed() {
            let num = intField(g, "num")
            if num > 0 {
                let id = stringField(g, "id") ?? ""
                if !id.isEmpty { return id }
            }
        }
        return nil
    }

    // MARK: - 升级 helpers

    private static func xingShiSelected(_ t: FeatureToggleStore) -> XingShi {
        let keys = (1...8).map { "rb_xpsj_\($0)" }
        let idx = keys.firstIndex(where: { t.getBool("huoyue", $0) }) ?? 0
        return xingShiList.indices.contains(idx) ? xingShiList[idx] : xingShiList[0]
    }

    private static func xingPanLevel(_ t: FeatureToggleStore) -> Int {
        for lv in 1...7 where t.getBool("huoyue", "rb_xpsj_lv_\(lv)") { return lv }
        return 1
    }

    private static func stonesNeeded(gems: [XingGem], want: Int64, level: Int, depth: Int = 0) -> Int64 {
        if gems.isEmpty || depth > 8 { return want }
        var gem = gems.last!
        for g in gems {
            gem = g
            if g.level == level { break }
        }
        if gem.level == 1 { return want - Int64(gem.num) }
        let need = want - Int64(gem.num)
        var lower = gems.last!
        for g in gems {
            lower = g
            if g.level == level - 1 { break }
        }
        return stonesNeeded(gems: gems, want: need * lower.upgradeCost, level: lower.level, depth: depth + 1)
    }

    private static func loadXingPanGems(
        gemType: Int,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> [XingGem]? {
        for _ in 0..<6 {
            let (_, body) = await LedouCGI.getPetPk(
                cmd: "astrolabe",
                extra: ["op": "viewupgrade", "gem_type": "\(gemType)"],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if body.contains("系统繁忙") { continue }
            if let code = jsonInt(body, "result"), code != 0 {
                let msg = CombatLog.fromBody(body)
                if !msg.isEmpty { onLog(msg) }
                return nil
            }
            return parseXingGems(body)
        }
        return nil
    }

    private static func parseXingGems(_ body: String) -> [XingGem] {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["gems"] as? [[String: Any]]
        else { return [] }
        var out: [XingGem] = []
        for o in arr {
            let id = stringField(o, "id") ?? ""
            if id.isEmpty { continue }
            out.append(XingGem(
                id: id,
                level: intField(o, "level"),
                num: intField(o, "num"),
                upgradeCost: int64Field(o, "upgrade_cost")
            ))
        }
        return out
    }

    private static func loadXingPanPoints(
        gemType: Int,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> Int64 {
        for _ in 0..<6 {
            let (_, body): (Int, String)
            if gemType < 7 {
                (_, body) = await LedouCGI.getPetPk(
                    cmd: "exchange", extra: ["subtype": "13"], cookie: cookie
                )
            } else {
                (_, body) = await LedouCGI.getPetPk(
                    cmd: "wlmz", extra: ["op": "view_exchange"], cookie: cookie
                )
            }
            try? await Task.sleep(nanoseconds: gapNs)
            if body.contains("系统繁忙") { continue }
            if let code = jsonInt(body, "result"), code != 0 {
                let msg = CombatLog.fromBody(body)
                if !msg.isEmpty { onLog(msg) }
                return 0
            }
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return 0 }
            if gemType < 7 {
                if let values = root["values"] as? [String: Any] {
                    if let s = values["9"] as? String, let v = Int64(s) { return v }
                    if let n = values["9"] as? NSNumber { return n.int64Value }
                }
                return 0
            }
            return int64Field(root, "points")
        }
        return 0
    }

    private static func exchangeXingPan(
        stone: XingShi,
        times: Int64,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> Bool {
        for _ in 0..<6 {
            let (_, body): (Int, String)
            if stone.gemType < 7 {
                (_, body) = await LedouCGI.getPetPk(
                    cmd: "exchange",
                    extra: ["subtype": "2", "times": "\(times)", "type": "\(stone.exchangeId)"],
                    cookie: cookie
                )
            } else {
                (_, body) = await LedouCGI.getPetPk(
                    cmd: "wlmz",
                    extra: ["op": "exchange", "times": "\(times)", "type_id": "\(stone.exchangeId)"],
                    cookie: cookie
                )
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if body.contains("系统繁忙") { continue }
            let msg = CombatLog.fromBody(body)
            if !msg.isEmpty { onLog(msg) }
            return jsonInt(body, "result") == 0
        }
        onLog("系统繁忙")
        return false
    }

    private static func upgradeXingPan(
        gemType: Int,
        level: Int,
        want: Int,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        for _ in 0..<48 {
            guard let gems = await loadXingPanGems(gemType: gemType, cookie: cookie, onLog: onLog) else {
                return "星盘升级中断"
            }
            if let target = gems.first(where: { $0.level == level }), target.num >= want {
                let tip = "合成结束"
                onLog(tip)
                return tip
            }
            guard let pick = gems.reversed().first(where: {
                $0.level < level && Int64($0.num) >= $0.upgradeCost
            }) else {
                let tip = "没有可合成的低级星石"
                onLog(tip)
                return tip
            }
            _ = await LedouCGI.getPetPk(
                cmd: "astrolabe",
                extra: ["op": "upgrade", "gem": pick.id],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let tip = "星盘升级步数到顶"
        onLog(tip)
        return tip
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

    private static func int64Field(_ o: [String: Any], _ key: String) -> Int64 {
        if let i = o[key] as? Int64 { return i }
        if let i = o[key] as? Int { return Int64(i) }
        if let s = o[key] as? String, let i = Int64(s) { return i }
        if let n = o[key] as? NSNumber { return n.int64Value }
        return 0
    }

    private static func jsonInt(_ body: String, _ key: String) -> Int? {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let i = root[key] as? Int { return i }
        if let s = root[key] as? String, let i = Int(s) { return i }
        if let n = root[key] as? NSNumber { return n.intValue }
        return nil
    }
}
