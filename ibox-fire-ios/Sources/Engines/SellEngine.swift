import Foundation

struct SellConfig {
    var token: String
    var groupId: Int64
    var collectionName: String = ""
    var targetPrice: Double
    var quantity: Int
    var consignPassword: String
    var proxy: String = ""
    var durationS: Double = 3600
}

final class SellEngine: @unchecked Sendable {
    private let cfg: SellConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: SellConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async throws -> Int {
        guard let uid = JwtUtil.uid(cfg.token) else { throw NSError(domain: "sell", code: 1, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"]) }
        if cfg.consignPassword.isEmpty { throw NSError(domain: "sell", code: 2, userInfo: [NSLocalizedDescriptionKey: "请填写寄售密码"]) }
        let client = IboxClient(token: cfg.token, proxyLine: nil, connectMs: 10000, readMs: 15000, deviceIdMode: .stableMD5)
        let qty = max(1, cfg.quantity)
        onLog("⚡本地直连模式（私人节奏）")
        onLog("卖求购启动 \(cfg.collectionName.isEmpty ? "-" : cfg.collectionName) gid=\(cfg.groupId) ≥¥\(cfg.targetPrice) x\(qty)")

        var holdings = await fetchHoldings(client, uid: uid)
        if holdings.isEmpty { throw NSError(domain: "sell", code: 3, userInfo: [NSLocalizedDescriptionKey: "无可用藏品"]) }
        onLog("持仓 \(holdings.count) 件")

        var sold = 0
        var soldOrderIds = Set<Int64>()
        let deadline = Date().timeIntervalSince1970 + cfg.durationS
        var lastBest = -1.0

        while !stop && sold < qty && !holdings.isEmpty && Date().timeIntervalSince1970 < deadline {
            let poPath = "/public-market-service/digital-collection-groups/\(cfg.groupId)/purchase-orders?pageNo=1&pageSize=20&uid=\(uid)"
            let poData = await client.get(poPath)
            let poCode = JSONX.code(poData)
            if poCode == 401 { onLog("Token 失效"); break }
            if poCode == 403 || poCode == 429 {
                try await Task.sleep(nanoseconds: 2_000_000_000); continue
            }
            let poItems = JSONX.dataList(poData)
            if poItems.isEmpty {
                try await Task.sleep(nanoseconds: 200_000_000); continue
            }
            var candidates = poItems.filter { row in
                let id = JSONX.int64Val(row["id"]) ?? 0
                let price = JSONX.doubleVal(row["price"]) ?? 0
                return id > 0 && price >= cfg.targetPrice && !soldOrderIds.contains(id)
            }.sorted { (JSONX.doubleVal($0["price"]) ?? 0) > (JSONX.doubleVal($1["price"]) ?? 0) }

            if candidates.isEmpty {
                let best = poItems.compactMap { JSONX.doubleVal($0["price"]) }.max() ?? 0
                if best != lastBest { onLog("求购最高¥\(best) 未达目标"); lastBest = best }
                try await Task.sleep(nanoseconds: 500_000_000); continue
            }

            for po in candidates {
                if stop || sold >= qty || holdings.isEmpty { break }
                let poId = JSONX.int64Val(po["id"]) ?? 0
                let price = JSONX.doubleVal(po["price"]) ?? 0
                let poRel = JSONX.int64Val(po["orderRelationId"]).flatMap { $0 > 0 ? $0 : nil }
                    ?? JSONX.int64Val(po["groupId"]).flatMap { $0 > 0 ? $0 : nil }
                    ?? cfg.groupId
                let myDid = holdings[0]
                let body: [String: Any] = [
                    "paymentPlatformCode": 30,
                    "digitalCollectionId": myDid,
                    "consignPassword": cfg.consignPassword
                ]
                let deal = await client.postJson("/order-create-service/advance-orders/\(poId)/relation/\(poRel)/deal?uid=\(uid)", body: body)
                let dc = JSONX.code(deal)
                let msg = JSONX.message(deal)
                if dc == 0 {
                    soldOrderIds.insert(poId)
                    holdings.removeFirst()
                    sold += 1
                    onLog("卖出成功! ¥\(price) (\(sold)/\(qty))")
                    try await Task.sleep(nanoseconds: 300_000_000)
                } else if dc == 401 {
                    onLog("Token 失效"); return sold
                } else if msg.contains("密码") {
                    onLog("寄售密码错误"); return sold
                } else {
                    onLog("卖出失败 c=\(dc) \(msg.prefix(40))")
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    break
                }
            }
        }
        onLog("卖求购结束 成交 \(sold)/\(qty)")
        return sold
    }

    private func fetchHoldings(_ client: IboxClient, uid: Int64) async -> [Int64] {
        let variants = [
            "?pageSize=100&pageNo=%d&lockStatus=0&uid=\(uid)",
            "?pageSize=100&pageNo=%d&lockStatus=0"
        ]
        for qs in variants {
            var out: [Int64] = []
            var hp = 1
            var failed = false
            while hp <= 50 {
                let path = "/personal-center-service/users/digital-collection-groups/\(cfg.groupId)" + String(format: qs, hp)
                let data = await client.get(path)
                let code = JSONX.code(data)
                if code != 0 {
                    onLog("持仓失败 c=\(code) \(JSONX.message(data).prefix(80))")
                    failed = true; break
                }
                let list = JSONX.dataList(data)
                if list.isEmpty { break }
                for it in list {
                    if let id = JSONX.int64Val(it["id"]), id > 0 { out.append(id) }
                }
                let hasMore = JSONX.dataDict(data)["hasMore"] as? Bool ?? false
                if !hasMore { break }
                hp += 1
            }
            if !failed { return out }
        }
        return []
    }
}
