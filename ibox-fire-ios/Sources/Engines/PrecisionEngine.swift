import Foundation

struct PrecisionOrder: Identifiable, Equatable {
    var id: Int64
    var orderRelationId: Int64
    var price: Double
    var orderUuid: String
    var createdAt: String
    var orderStatus: Int = 0
}

struct PrecisionHolding: Identifiable, Equatable {
    var id: Int64
    var name: String
    var tokenId: String
    var ownedAt: String = ""
}

/// 本地精准射：直连 iBox，对齐网站 purchase-orders / holdings-detail / precision-sell。
enum PrecisionBrowse {
    static func client(_ token: String, randomDevice: Bool = false) -> IboxClient {
        IboxClient(token: token, deviceIdMode: randomDevice ? .random : .stableMD5)
    }

    static func purchaseOrders(token: String, groupId: Int64, page: Int) async throws -> (orders: [PrecisionOrder], total: Int, page: Int) {
        let uid = JwtUtil.uid(token) ?? 0
        let p = max(1, page)
        let path = "/public-market-service/digital-collection-groups/\(groupId)/purchase-orders?pageNo=\(p)&pageSize=20&sortField=1&sortType=2&uid=\(uid)"
        let data = await client(token).get(path)
        let code = JSONX.code(data)
        if code != 0 {
            let msg = String(JSONX.message(data).prefix(200))
            throw NSError(domain: "precision", code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "API error code=\(code)" : msg])
        }
        let payload = JSONX.dataDict(data)
        var items: [PrecisionOrder] = []
        for it in JSONX.dataList(data) {
            if let o = parseOrder(it) { items.append(o) }
        }
        let total = (payload["total"] as? Int)
            ?? (payload["total"] as? NSNumber)?.intValue
            ?? items.count
        return (items, total, p)
    }

    /// 按 orderUuid 翻页匹配，最多 200 页。
    static func findByUuid(token: String, groupId: Int64, uuid: String, page1Cache: [PrecisionOrder] = []) async throws -> (PrecisionOrder?, Int) {
        let want = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        if want.isEmpty { return (nil, 1) }
        var page = 1
        while page <= 200 {
            let orders: [PrecisionOrder]
            if page == 1 && !page1Cache.isEmpty {
                orders = page1Cache
            } else {
                orders = try await purchaseOrders(token: token, groupId: groupId, page: page).orders
            }
            if orders.isEmpty { break }
            if let hit = orders.first(where: { $0.orderUuid == want }) {
                return (hit, page)
            }
            page += 1
        }
        return (nil, 1)
    }

    static func holdings(token: String, groupId: Int64) async throws -> [PrecisionHolding] {
        guard let uid = JwtUtil.uid(token) else {
            throw NSError(domain: "precision", code: 1, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"])
        }
        var out: [PrecisionHolding] = []
        var page = 1
        while page <= 50 {
            let path = "/personal-center-service/users/digital-collection-groups/\(groupId)?pageSize=100&pageNo=\(page)&uid=\(uid)"
            let data = await client(token).get(path)
            let code = JSONX.code(data)
            if code != 0 && page == 1 {
                let msg = String(JSONX.message(data).prefix(200))
                throw NSError(domain: "precision", code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "持仓失败" : msg])
            }
            let payload = JSONX.dataDict(data)
            let list = JSONX.dataList(data)
            if list.isEmpty { break }
            for it in list {
                let id = JSONX.int64Val(it["id"]) ?? 0
                guard id > 0 else { continue }
                out.append(PrecisionHolding(
                    id: id,
                    name: JSONX.stringVal(it["name"]),
                    tokenId: JSONX.stringVal(it["tokenId"]),
                    ownedAt: JSONX.stringVal(it["ownedAt"])
                ))
            }
            let hasMore = payload["hasMore"] as? Bool ?? false
            if !hasMore { break }
            page += 1
        }
        return out
    }

    static func sell(
        token: String,
        orderId: Int64,
        orderRelationId: Int64,
        digitalCollectionId: Int64,
        consignPassword: String
    ) async -> (ok: Bool, message: String) {
        guard let uid = JwtUtil.uid(token) else { return (false, "JWT 无 userId") }
        if orderId <= 0 || orderRelationId <= 0 { return (false, "请选择求购单") }
        if digitalCollectionId <= 0 { return (false, "请选择要卖出的藏品") }
        if consignPassword.trimmingCharacters(in: .whitespaces).isEmpty { return (false, "请输入寄售密码") }
        let path = "/order-create-service/advance-orders/\(orderId)/relation/\(orderRelationId)/deal?uid=\(uid)"
        let body: [String: Any] = [
            "paymentPlatformCode": 30,
            "digitalCollectionId": digitalCollectionId,
            "consignPassword": consignPassword,
        ]
        let data = await client(token, randomDevice: true).postJson(path, body: body)
        let code = JSONX.code(data)
        let msg = JSONX.message(data)
        if code == 0 { return (true, "精准卖出成功") }
        if [3_600_000, 3_600_002].contains(Int(code)) { return (false, "该求购已失效") }
        if code == 2100001 { return (false, "物品冷却中，请稍后再试") }
        if msg.contains("密码") { return (false, String(msg.prefix(100)).isEmpty ? "寄售密码错误" : String(msg.prefix(100))) }
        let fallback = msg.isEmpty ? "失败 c=\(code)" : msg
        return (false, String(fallback.prefix(100)))
    }

    private static func parseOrder(_ it: [String: Any]) -> PrecisionOrder? {
        let id = JSONX.int64Val(it["id"]) ?? 0
        guard id > 0 else { return nil }
        let rel = JSONX.int64Val(it["orderRelationId"]).flatMap { $0 > 0 ? $0 : nil }
            ?? JSONX.int64Val(it["groupId"]).flatMap { $0 > 0 ? $0 : nil }
            ?? 0
        return PrecisionOrder(
            id: id,
            orderRelationId: rel,
            price: JSONX.doubleVal(it["price"]) ?? 0,
            orderUuid: JSONX.stringVal(it["orderUuid"]),
            createdAt: JSONX.stringVal(it["createdAt"]),
            orderStatus: Int(JSONX.int64Val(it["orderStatus"]) ?? 0)
        )
    }
}
