import Foundation

struct SweepMarkerOrder: Identifiable, Equatable {
    var id: String { orderId.isEmpty ? "\(digitalCollectionId)" : orderId }
    var orderId: String
    var digitalCollectionId: Int64
    var tokenId: String
    var price: Double
    var sellerName: String
}

struct SweepSeller: Equatable {
    var sso: String
    var uid: Int64
    var name: String
    var markerOrderId: String = ""
    var markerGid: Int64 = 0
    var digitalCollectionId: Int64 = 0
}

struct SweepWhGroup: Identifiable, Equatable {
    var id: Int64 { groupId }
    var groupId: Int64
    var name: String
    var count: Int
}

struct SweepWhItem: Identifiable, Equatable {
    var id: Int64 { digitalCollectionId }
    var digitalCollectionId: Int64
    var tokenId: String
    var name: String
    var price: Double
    var groupId: Int64
    var hasPrice: Bool { price > 0 }
}

struct SweepSelectedItem: Equatable {
    var digitalCollectionId: Int64
    var tokenId: String
    var price: Double
    var groupId: Int64
}

struct SweepConfig {
    var token: String
    var sellerSso: String
    var sellerName: String = ""
    var markerGid: Int64 = 0
    var groupId: Int64 = 0
    var collectionName: String = ""
    var maxPrice: Double
    var quantity: Int
    var selected: [SweepSelectedItem]
    var autoPay: Bool = false
    var payPassword: String = ""
}

enum SweepBrowse {
    static func client(_ token: String) -> IboxClient {
        IboxClient(token: token, deviceIdMode: .stableMD5)
    }

    static func markerOrders(token: String, gid: Int64, sortValues: String, pageSize: Int = 20) async throws -> (items: [SweepMarkerOrder], nextSv: String, hasMore: Bool) {
        let uid = JwtUtil.uid(token) ?? 0
        var path = "/public-market-service/digital-collection-groups/\(gid)/consignment-orders?pageNo=1&pageSize=\(pageSize)&sortField=1&sortType=2&uid=\(uid)"
        let sv = sortValues.trimmingCharacters(in: .whitespaces)
        if !sv.isEmpty { path += "&sortValues=\(sv)" }
        let data = await client(token).get(path)
        let code = JSONX.code(data)
        if code != 0 {
            let msg = String(JSONX.message(data).prefix(200))
            throw NSError(domain: "sweep", code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "API error code=\(code)" : msg])
        }
        let payload = JSONX.dataDict(data)
        var items: [SweepMarkerOrder] = []
        for it in JSONX.dataList(data) {
            if let o = parseMarker(it) { items.append(o) }
        }
        let nextSv = formatSortValues(payload)
        let hasMore = boolVal(payload["hasMore"]) && !nextSv.isEmpty
        return (items, nextSv, hasMore)
    }

    static func resolveSeller(token: String, digitalCollectionId: Int64) async throws -> SweepSeller {
        let detail = await client(token).get("/public-service/digital-collections/\(digitalCollectionId)")
        let code = JSONX.code(detail)
        if code != 0 {
            let msg = String(JSONX.message(detail).prefix(200))
            throw NSError(domain: "sweep", code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "API error" : msg])
        }
        let data = JSONX.dataDict(detail)
        let owner = data["owner"] as? [String: Any] ?? [:]
        let sso = firstString(owner, "ssoUserId", "ssoId", "uuid", "paymentUserId")
        if sso.isEmpty { throw NSError(domain: "sweep", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析卖家，请换一单"]) }
        let name = firstString(owner, "userName", "nickname")
        let uid = firstInt64(owner, "id", "userId", "uid")
        return SweepSeller(sso: sso, uid: uid, name: name, digitalCollectionId: digitalCollectionId)
    }

    static func warehouseGroups(token: String, sellerSso: String) async throws -> [SweepWhGroup] {
        let path = "/personal-center-service/users/other/\(sellerSso)/digital-collection-groups?pageNo=1&pageSize=50&groupType=0"
        let data = await client(token).get(path)
        try throwIfWarehouseClosed(data)
        var groups: [SweepWhGroup] = []
        for it in JSONX.dataList(data) {
            let gid = firstInt64(it, "id", "groupId")
            if gid <= 0 { continue }
            groups.append(SweepWhGroup(
                groupId: gid,
                name: firstString(it, "name", "groupName"),
                count: Int(firstInt64(it, "holdCount", "holdNum", "count"))
            ))
        }
        return groups
    }

    static func warehouseItems(token: String, sellerSso: String, groupId: Int64, page: Int, pageSize: Int = 20) async throws -> (items: [SweepWhItem], hasMore: Bool) {
        let path = "/personal-center-service/users/other/\(sellerSso)/digital-collection-groups/\(groupId)?pageSize=\(pageSize)&pageNo=\(page)"
        let data = await client(token).get(path)
        try throwIfWarehouseClosed(data)
        var items: [SweepWhItem] = []
        for it in JSONX.dataList(data) {
            if let row = parseWhItem(it, groupId: groupId) { items.append(row) }
        }
        let hasMore = boolVal(JSONX.dataDict(data)["hasMore"])
        return (items, hasMore)
    }

    private static func throwIfWarehouseClosed(_ data: [String: Any]) throws {
        let code = JSONX.code(data)
        let msg = JSONX.message(data)
        if code == 200002 || ["未开放", "不对外开放", "不可见", "对外展示", "隐私设置"].contains(where: { msg.contains($0) }) {
            throw NSError(domain: "sweep", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "对方未开放持仓，无法查看仓库"])
        }
        if code != 0 {
            throw NSError(domain: "sweep", code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "API error code=\(code)" : msg])
        }
    }

    static func formatSortValues(_ payload: [String: Any]) -> String {
        let sv = payload["sortValues"] as? [String: Any] ?? [:]
        let vals = sv["values"] as? [Any] ?? []
        guard vals.count >= 3 else { return "" }
        return "\(vals[0]),\(vals[1]),\(vals[2])"
    }

    private static func parseMarker(_ it: [String: Any]) -> SweepMarkerOrder? {
        let dc = it["digitalCollection"] as? [String: Any] ?? [:]
        let pp = it["productPreview"] as? [String: Any] ?? [:]
        let dcId = firstInt64(it, "digitalCollectionId").nonZero
            ?? firstInt64(dc, "id").nonZero
            ?? firstInt64(pp, "digitalCollectionId", "id")
        if dcId <= 0 { return nil }
        var seller = ""
        for k in ["seller", "owner", "user"] {
            if let nest = it[k] as? [String: Any] {
                seller = firstString(nest, "userName", "nickname")
                if !seller.isEmpty { break }
            }
        }
        return SweepMarkerOrder(
            orderId: firstString(it, "id"),
            digitalCollectionId: dcId,
            tokenId: firstString(dc, "tokenId").ifEmpty(firstString(pp, "tokenId")).ifEmpty(firstString(it, "tokenId")),
            price: firstDouble(it, "price"),
            sellerName: seller
        )
    }

    private static func parseWhItem(_ it: [String: Any], groupId: Int64) -> SweepWhItem? {
        let dc = it["digitalCollection"] as? [String: Any] ?? [:]
        let pp = it["productPreview"] as? [String: Any] ?? [:]
        let dcId = firstInt64(it, "digitalCollectionId", "id").nonZero
            ?? firstInt64(dc, "id").nonZero
            ?? firstInt64(pp, "digitalCollectionId", "id")
        if dcId <= 0 { return nil }
        return SweepWhItem(
            digitalCollectionId: dcId,
            tokenId: firstString(dc, "tokenId").ifEmpty(firstString(pp, "tokenId")).ifEmpty(firstString(it, "tokenId")),
            name: firstString(it, "name").ifEmpty(firstString(dc, "name")).ifEmpty(firstString(pp, "name")),
            price: firstDouble(it, "price", "amount", "consignPrice"),
            groupId: groupId
        )
    }

    private static func boolVal(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return false
    }

    private static func firstString(_ obj: [String: Any], _ keys: String...) -> String {
        for k in keys {
            let s = JSONX.stringVal(obj[k]).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty && s != "null" { return s }
        }
        return ""
    }

    private static func firstInt64(_ obj: [String: Any], _ keys: String...) -> Int64 {
        for k in keys {
            if let v = JSONX.int64Val(obj[k]) { return v }
        }
        return 0
    }

    private static func firstDouble(_ obj: [String: Any], _ keys: String...) -> Double {
        for k in keys {
            if let v = JSONX.doubleVal(obj[k]) { return v }
        }
        return 0
    }
}

final class SweepEngine: @unchecked Sendable {
    private let cfg: SweepConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: SweepConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        let qty = max(1, cfg.quantity)
        let selected = Array(cfg.selected.prefix(qty))
        if selected.isEmpty { onLog("未勾选目标"); return 0 }
        let sellerLabel = cfg.sellerName.isEmpty ? String(cfg.sellerSso.prefix(8)) : cfg.sellerName
        onLog("卖家已确认：\(sellerLabel)")
        var startMsg = "已选目标 \(selected.count)/\(qty) 件，最高价 ¥\(cfg.maxPrice)"
        if cfg.markerGid > 0 { startMsg += " 暗号GID=\(cfg.markerGid)" }
        onLog(startMsg)

        let client = IboxClient(token: cfg.token, deviceIdMode: .random)
        let payer: HfpayPayer? = (cfg.autoPay && !cfg.payPassword.trimmingCharacters(in: .whitespaces).isEmpty)
            ? HfpayPayer(iboxToken: cfg.token) : nil
        var bought = 0
        var unpaid = 0
        let maxP = cfg.maxPrice

        for item in selected {
            if stop || bought >= qty { break }
            if item.price > 0 && item.price > maxP + 0.009 {
                onLog("超价跳过 Y\(item.price) > ¥\(maxP)")
                continue
            }
            onLog("下单 did=\(item.digitalCollectionId) ¥\(item.price) …")
            let ord = await client.postJson(
                "/order-create-service/purchase-consignment-orders",
                body: ["digitalCollectionId": item.digitalCollectionId, "paymentPlatformCode": 30]
            )
            let oc = JSONX.code(ord)
            let om = JSONX.message(ord)
            switch oc {
            case 0:
                let oid = JSONX.stringVal(JSONX.dataDict(ord)["orderId"])
                onLog("扫到 Y\(item.price) \(oid)")
                if let payer {
                    onLog("支付中...")
                    let pay = await payer.pay(ibox: client, orderId: oid, payPassword: cfg.payPassword)
                    if pay.ok {
                        bought += 1
                        unpaid = 0
                        onLog("支付成功 \(pay.detail)")
                    } else if pay.passwordError {
                        onLog("密码错误!")
                        break
                    } else {
                        onLog("支付失败:\(pay.detail.prefix(30))")
                        unpaid += 1
                        if unpaid >= 2 { break }
                    }
                } else {
                    bought += 1
                    onLog("下单成功 请手动支付 \(oid)")
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            case 5_100_004:
                unpaid += 1
                onLog("未付订单(\(unpaid)/2)")
                if unpaid >= 2 { break }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            case 2_600_009:
                onLog("已被抢")
            default:
                onLog("购买失败 c=\(oc) \(om.prefix(40))")
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        onLog("完成: 成功 \(bought) / 已选 \(selected.count)")
        return bought
    }
}

private extension Int64 {
    var nonZero: Int64? { self > 0 ? self : nil }
}

private extension String {
    func ifEmpty(_ alt: String) -> String { isEmpty ? alt : self }
}
