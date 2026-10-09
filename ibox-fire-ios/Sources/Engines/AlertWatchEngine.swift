import Foundation
import UserNotifications

/// 全图异动 + 单图预警：30s 扫 markets。
final class AlertWatchEngine: @unchecked Sendable {
    private let store: AlertWatchStore
    private let onLog: (String) -> Void
    private let onWxPush: (String) -> Void
    private var stop = false
    private var prevStats: [String: Stat] = [:]
    private var prev1h: [String: Double] = [:]
    private var prev1hAt: TimeInterval = 0
    private var pushed1h: [String: TimeInterval] = [:]
    private var alertDedup: [String: TimeInterval] = [:]

    private struct Stat {
        var name: String
        var floor: Double
        var volume: Int64
    }

    init(store: AlertWatchStore, onLog: @escaping (String) -> Void, onWxPush: @escaping (String) -> Void) {
        self.store = store
        self.onLog = onLog
        self.onWxPush = onWxPush
    }

    func requestStop() { stop = true }

    func run() async {
        var parts: [String] = []
        if store.marketWatchEnabled { parts.append("全图异动") }
        if store.priceAlertWatchEnabled { parts.append("单图预警") }
        onLog("监视启动 · \(parts.joined(separator: "+").isEmpty ? "无" : parts.joined(separator: "+")) · 30s · 直连 iBox")
        var round = 0
        while !stop && store.marketOrPriceEnabled {
            round += 1
            await tick(round)
            var waited: UInt64 = 0
            while waited < 30_000 && !stop && store.marketOrPriceEnabled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waited += 1_000
            }
        }
        onLog("异动监视已停止")
    }

    private func tick(_ round: Int) async {
        let doMarket = store.marketWatchEnabled
        let doPrice = store.priceAlertWatchEnabled
        if !doMarket && !doPrice { return }
        let follows = doMarket ? Set(store.loadFollows().map(\.groupId)) : []
        let blocks = doMarket ? Set(store.loadBlocks().map(\.groupId)) : []
        let alerts = doPrice ? store.loadAlerts().filter(\.enabled) : []
        let stats = await fetchMarketPool(store.iboxToken)
        if stats.isEmpty {
            onLog("巡检 #\(round) · 行情池为空")
            return
        }
        let now = Date().timeIntervalSince1970
        var burst: [String] = []
        if doMarket {
            if !prevStats.isEmpty {
                for (cid, cur) in stats {
                    guard let gid = Int64(cid), follows.contains(gid), !blocks.contains(gid),
                          let prev = prevStats[cid] else { continue }
                    let delta = cur.volume - prev.volume
                    if delta >= 5 {
                        burst.append("\(cur.name) 成交\(delta)笔，均价\(Int(cur.floor))元")
                    }
                }
            }
            if prev1h.isEmpty || now - prev1hAt > 3_600 {
                prev1h = stats.reduce(into: [:]) { acc, kv in
                    if kv.value.floor > 0 { acc[kv.key] = kv.value.floor }
                }
                prev1hAt = now
                pushed1h.removeAll()
            } else {
                for (cid, cur) in stats {
                    guard let gid = Int64(cid), follows.contains(gid), !blocks.contains(gid),
                          let base = prev1h[cid], base > 0, cur.floor > 0 else { continue }
                    let pct = (cur.floor - base) / base * 100
                    if abs(pct) < 15 { continue }
                    if now - (pushed1h[cid] ?? 0) < 1_800 { continue }
                    let d = pct > 0 ? "涨" : "跌"
                    burst.append("\(cur.name) 1小时\(d)\(Int(abs(pct)))%，现价\(Int(cur.floor))元")
                    pushed1h[cid] = now
                }
            }
            prevStats = stats
            for msg in burst.prefix(8) { emitHit(msg, priceAlert: false) }
        } else {
            prevStats = stats
        }

        if doPrice {
            var nameMap: [String: Stat] = [:]
            for s in stats.values where !s.name.isEmpty { nameMap[s.name] = s }
            for pa in alerts {
                let cid = String(pa.groupId)
                let item = stats[cid] ?? nameMap[pa.groupName]
                guard let item, item.floor > 0 else { continue }
                let name = pa.groupName.isEmpty ? item.name : pa.groupName
                if let up = pa.alertUp, item.floor >= up {
                    let msg = "\(name) 涨至\(Int(item.floor))元，触发上涨预警线\(Int(up))元"
                    if dedupOk(msg, now) { emitHit(msg, priceAlert: true) }
                }
                if let down = pa.alertDown, item.floor <= down {
                    let msg = "\(name) 跌至\(Int(item.floor))元，触发下跌预警线\(Int(down))元"
                    if dedupOk(msg, now) { emitHit(msg, priceAlert: true) }
                }
            }
        }

        if burst.isEmpty && round % 2 == 0 {
            var extra = ""
            if doMarket { extra += " · 关注\(follows.count)" }
            if doPrice { extra += " · 预警\(alerts.count)" }
            onLog("巡检 #\(round) · 池\(stats.count)\(extra) · 暂无触发")
        } else if !burst.isEmpty {
            onLog("巡检 #\(round) · 异动 \(burst.count) 条")
        }
    }

    private func dedupOk(_ msg: String, _ now: TimeInterval) -> Bool {
        let key = String(msg.prefix(40))
        if now - (alertDedup[key] ?? 0) < 600 { return false }
        alertDedup[key] = now
        if alertDedup.count > 200 {
            alertDedup = alertDedup.filter { now - $0.value <= 3_600 }
        }
        return true
    }

    private func emitHit(_ msg: String, priceAlert: Bool) {
        onLog(msg)
        LocalNotify.post(title: priceAlert ? "价格预警" : "全图异动", body: msg)
        onWxPush(msg)
    }

    private func fetchMarketPool(_ token: String) async -> [String: Stat] {
        guard !token.isEmpty else { return [:] }
        let client = IboxClient(token: token, deviceIdMode: .stableMD5)
        var out: [String: Stat] = [:]
        for seg in [-1, 54, 39] {
            let maxPages = seg == -1 ? 5 : 3
            for page in 1...maxPages {
                let path = "/public-service/markets?pageNo=\(page)&pageSize=50&sortField=2&sortType=0&segmentId=\(seg)"
                let r = await client.get(path)
                if JSONX.code(r) != 0 && r["data"] == nil { break }
                let data = JSONX.dataDict(r)
                let list = data["list"] as? [[String: Any]] ?? []
                if list.isEmpty { break }
                for it in list {
                    let id = JSONX.int64Val(it["id"]) ?? 0
                    if id <= 0 { continue }
                    let cid = String(id)
                    if out[cid] != nil { continue }
                    out[cid] = Stat(
                        name: JSONX.stringVal(it["name"]),
                        floor: JSONX.doubleVal(it["floorPrice"]) ?? 0,
                        volume: JSONX.int64Val(it["tradeVolume"]) ?? 0
                    )
                }
                if data["hasMore"] as? Bool != true { break }
            }
        }
        return out
    }
}

enum LocalNotify {
    static func post(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
