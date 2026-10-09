import Foundation

/// 发现趋势推送：1s 扫 activity-areas，上新通知 + 微信。
final class DiscoverPushEngine: @unchecked Sendable {
    private let store: AlertWatchStore
    private let onLog: (String) -> Void
    private let onHit: (String, Int64, String) -> Void
    private var stop = false
    private var seen = Set<Int64>()
    private var ready = false
    private var round = 0

    init(store: AlertWatchStore, onLog: @escaping (String) -> Void, onHit: @escaping (String, Int64, String) -> Void) {
        self.store = store
        self.onLog = onLog
        self.onHit = onHit
    }

    func requestStop() { stop = true }

    func run() async {
        onLog("发现趋势推送启动 · 间隔1s · activity-areas")
        while !stop && store.discoverPushEnabled {
            do {
                try await tick()
            } catch {
                onLog("趋势扫描异常 · \(String(error.localizedDescription.prefix(60)))")
            }
            var waited: UInt64 = 0
            while waited < 1_000 && !stop && store.discoverPushEnabled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 200
            }
        }
        onLog("发现趋势推送已停止")
    }

    private func tick() async throws {
        let token = store.iboxToken
        if token.isEmpty { onLog("趋势推送需登录 iBox"); return }
        let client = IboxClient(token: token, deviceIdMode: .stableMD5)
        round += 1
        onLog("请求 activity-areas…")
        let slots = await Self.fetchAreas(client)
        let topTip: String = {
            guard let t = slots.first else { return "-" }
            let hint = t.1.isEmpty ? "GID" : String(t.1.prefix(20))
            return "\(hint)(\(t.0))"
        }()
        onLog("巡检 #\(round) OK 已见\(seen.count) 槽\(slots.count) 最新\(topTip)")
        if slots.isEmpty { return }
        let gids = Set(slots.map(\.0))
        if !ready {
            seen = gids
            ready = true
            onLog("趋势已同步存量 \(seen.count) 个 · 之后上新才推")
            return
        }
        for (gid, hint) in slots {
            if seen.contains(gid) { continue }
            seen.insert(gid)
            let name = hint.isEmpty ? "GID\(gid)" : hint
            let floor = await Self.getFloor(client, gid: gid)
            var msg = "【发现趋势上新】\(name)（\(gid)）"
            if floor > 0 {
                if floor == floor.rounded(.towardZero) {
                    msg += "地板¥\(Int(floor))"
                } else {
                    msg += String(format: "地板¥%.2f", floor)
                }
            }
            onLog(msg)
            onHit(msg, gid, name)
        }
        if seen.count > 800 { seen = seen.intersection(gids) }
    }

    static func fetchAreas(_ client: IboxClient) async -> [(Int64, String)] {
        let r = await client.get("/public-service/home/activity-areas?areaType=1")
        if JSONX.code(r) != 0 && r["data"] == nil { return [] }
        let arr: [[String: Any]] = {
            if let a = r["data"] as? [[String: Any]] { return a }
            let d = JSONX.dataDict(r)
            if let a = d["list"] as? [[String: Any]] { return a }
            if let a = d["areas"] as? [[String: Any]] { return a }
            return []
        }()
        var out: [(Int64, String)] = []
        var dup = Set<Int64>()
        let re = try? NSRegularExpression(pattern: "/markets/(\\d+)")
        for it in arr {
            let link = JSONX.stringVal(it["link"]).isEmpty ? JSONX.stringVal(it["jumpUrl"]) : JSONX.stringVal(it["link"])
            guard let re,
                  let m = re.firstMatch(in: link, range: NSRange(link.startIndex..., in: link)),
                  let r1 = Range(m.range(at: 1), in: link),
                  let gid = Int64(link[r1]), gid > 0, !dup.contains(gid) else { continue }
            dup.insert(gid)
            let hint = [it["title"], it["subTitle"], it["name"]]
                .compactMap { JSONX.stringVal($0) }
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            out.append((gid, hint.trimmingCharacters(in: .whitespaces)))
        }
        return out
    }

    static func getFloor(_ client: IboxClient, gid: Int64) async -> Double {
        let path = "/public-market-service/digital-collection-groups/\(gid)/consignment-orders?pageNo=1&pageSize=1&sortField=1&sortType=1"
        let data = await client.get(path)
        if JSONX.code(data) != 0 { return 0 }
        let list = JSONX.dataList(data)
        guard let first = list.first else { return 0 }
        return JSONX.doubleVal(first["price"]) ?? 0
    }
}
