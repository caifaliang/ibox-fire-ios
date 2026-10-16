import Foundation

/// 真源：`MoreExtraActions.farmXingPanHuanZhuang` — astrolabe 拆卸再镶嵌。
enum XingPanActions {
    private static let gapNs: UInt64 = 80_000_000

    // MARK: - Public

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
