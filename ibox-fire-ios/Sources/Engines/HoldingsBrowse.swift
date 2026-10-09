import Foundation

struct HoldingGroup: Identifiable, Equatable {
    var id: Int64
    var name: String
    var holdNum: Int
    var consignNum: Int
    var lockCount: Int
    var floorHint: Double = 0
    var unit: Double? = nil
}

enum HoldingsBrowse {
    static func page(token: String, pageNo: Int, keyword: String = "") async throws -> (items: [HoldingGroup], hasMore: Bool, total: Int, page: Int) {
        guard let uid = JwtUtil.uid(token) else { throw NSError(domain: "holdings", code: 1, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"]) }
        let p = max(1, pageNo)
        var path = "/personal-center-service/users/digital-collection-groups?pageNo=\(p)&pageSize=50&groupType=0&uid=\(uid)"
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty, let enc = kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&groupName=\(enc)"
        }
        let client = IboxClient(token: token, deviceIdMode: .stableMD5)
        let data = await client.get(path)
        let code = JSONX.code(data)
        if code != 0 {
            throw NSError(domain: "holdings", code: Int(code), userInfo: [NSLocalizedDescriptionKey: String(JSONX.message(data).prefix(200))])
        }
        let payload = JSONX.dataDict(data)
        let list = payload["list"] as? [[String: Any]] ?? []
        let items: [HoldingGroup] = list.compactMap { it in
            let id = JSONX.int64Val(it["id"]) ?? 0
            guard id > 0 else { return nil }
            let floor = ["floorPrice", "lowestPrice", "consignmentPrice", "referencePrice", "price"]
                .compactMap { JSONX.doubleVal(it[$0]) }.first { $0 > 0 } ?? 0
            return HoldingGroup(
                id: id,
                name: JSONX.stringVal(it["name"]),
                holdNum: Int(JSONX.int64Val(it["holdNum"]) ?? 0),
                consignNum: Int(JSONX.int64Val(it["consignmentNum"]) ?? 0),
                lockCount: Int(JSONX.int64Val(it["lockCount"]) ?? 0),
                floorHint: floor
            )
        }
        return (items, payload["hasMore"] as? Bool ?? false, Int(JSONX.int64Val(payload["total"]) ?? 0), p)
    }

    static func quote(token: String, gid: Int64, floorHint: Double = 0) async -> Double? {
        let uid = JwtUtil.uid(token) ?? 0
        let client = IboxClient(token: token, deviceIdMode: .stableMD5)
        var floor: Double? = floorHint > 0 ? floorHint : nil
        if floor == nil {
            let path = "/public-market-service/digital-collection-groups/\(gid)/consignment-orders?pageNo=1&pageSize=1&sortField=1&sortType=1&uid=\(uid)"
            let data = await client.get(path)
            if let first = JSONX.dataList(data).first, let p = JSONX.doubleVal(first["price"]), p > 0 {
                floor = p
            }
        }
        var purchaseMax: Double?
        let ppath = "/public-market-service/digital-collection-groups/\(gid)/purchase-orders?pageNo=1&pageSize=20&sortField=1&sortType=2&uid=\(uid)"
        let pdata = await client.get(ppath)
        var mx = 0.0
        for it in JSONX.dataList(pdata) {
            if let p = JSONX.doubleVal(it["price"]), p > mx { mx = p }
        }
        if mx > 0 { purchaseMax = mx }
        let candidates = [floor, purchaseMax].compactMap { $0 }
        return candidates.max()
    }
}
