import Foundation
import CryptoKit

struct IbSaleItem: Identifiable, Equatable {
    var id: Int64
    var name: String
    var cover: String = ""
    var goodsType: Int = 2
    var batchId: Int64 = 0
    var startTime: String = ""
    var price: String = ""
}

struct IbMarketItem: Identifiable, Equatable {
    var id: Int64
    var name: String
    var cover: String = ""
    var floor: String = ""
    var goodsType: Int = 2
    var key: String = ""
    var batchPay: Bool = false
}

struct IbApiResult {
    var ok: Bool
    var code: Int
    var msg: String
    var data: [String: Any] = [:]
    var httpStatus: Int = 0
    var raw: [String: Any] = [:]
}

/// ibPro 官方直连 https://api.iboxart.cn/api（token + deviceType + deviceId）
final class IbproClient: @unchecked Sendable {
    private let base = "https://api.iboxart.cn/api"
    private let token: String
    private let deviceId: String
    private let http: ProxyURLSession

    init(token: String, deviceId: String, proxyUrl: String = "", readMs: TimeInterval = 12) {
        self.token = token
        self.deviceId = deviceId
        http = ProxyURLSession(proxyLine: proxyUrl.isEmpty ? nil : proxyUrl, timeout: readMs)
    }

    static func stableDeviceId(seed: String = "") -> String {
        let raw = seed.isEmpty ? UUID().uuidString : seed
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    static func isAuthFail(_ r: IbApiResult) -> Bool {
        if r.code == 401 || r.httpStatus == 401 { return true }
        let t = r.msg
        return t.contains("请登录") || t.contains("未登录") || t.contains("登录失效") ||
            (t.localizedCaseInsensitiveContains("token") && (t.contains("过期") || t.contains("无效")))
    }

    static func extractTokenFromLogin(_ r: IbApiResult) -> String {
        if let info = r.data["userinfo"] as? [String: Any] {
            let t = JSONX.stringVal(info["token"])
            if !t.isEmpty { return t }
        }
        return JSONX.stringVal(r.data["token"])
    }

    func saleList() async throws -> [IbSaleItem] {
        let r = try await get("/box/blind_box/list")
        guard r.ok else { throw NSError(domain: "ibpro", code: r.code, userInfo: [NSLocalizedDescriptionKey: r.msg]) }
        return Self.parseSaleList(r.data)
    }

    func createOrder(goodsId: Int64, goodsType: Int = 2, batchId: Int64 = 0, num: Int = 1, payWay: String = "huifu") async -> IbApiResult {
        var body: [String: Any] = [
            "pay_way": payWay,
            "num": max(1, num),
            "goods_id": goodsId,
            "goods_type": goodsType,
            "price": "",
        ]
        // 公售/权益购买必须带 batch_id；缺参会回「缺少批次参数」
        if batchId > 0 { body["batch_id"] = batchId }
        return await post("/order/pay/CreateOrder", body: body)
    }

    func doPay(orderId: Any?, orderSn: String, payPassword: String, payWay: String = "huifu", orderType: Int = 1) async -> IbApiResult {
        var body: [String: Any] = [
            "pay_way": payWay,
            "order_type": orderType,
            "pay_scene": "H5",
            "pay_password": payPassword,
            "returnurl": Data("/pages/order/payReslut/index".utf8).base64EncodedString(),
        ]
        if let orderId {
            let s = "\(orderId)"
            if !s.isEmpty { body["order_id"] = orderId }
        }
        if !orderSn.isEmpty { body["order_number"] = orderSn }
        return await post("/order/pay/doPay", body: body)
    }

    func marketList(tab: String = "hot", page: Int = 1, listRows: Int = 30, goodsType: Int = 2) async throws -> [IbMarketItem] {
        let body: [String: Any]
        if tab == "hot" {
            body = ["hot_status": 1, "goods_type": goodsType, "page": page, "list_rows": listRows]
        } else {
            body = ["series_id": -2, "goods_type": goodsType, "page": page, "list_rows": listRows]
        }
        let r = await post("/market/market/getMarketList", body: body)
        guard r.ok else { throw NSError(domain: "ibpro", code: r.code, userInfo: [NSLocalizedDescriptionKey: r.msg]) }
        return Self.parseMarketList(r.data)
    }

    func marketGoodsDetail(goodsId: Int64, goodsType: Int = 2) async -> IbApiResult {
        await post("/market/market/marketGoodsDetail", body: ["id": goodsId, "type": goodsType])
    }

    func hangList(goodsId: Int64, goodsType: Int = 2, page: Int = 1) async -> IbApiResult {
        await post("/market/market/getMarketGoodsListByGoodsId", body: [
            "id": goodsId, "type": goodsType, "page": page, "sort": "price", "order": "asc",
        ])
    }

    func fastOrderNew(goodsId: Int64, key: String, payWay: String = "huifu") async -> IbApiResult {
        await post("/order/pay/fastOrderNew", body: [
            "goods_id": goodsId, "key": key, "pay_way": payWay,
        ])
    }

    func createMarketOrder(marketGoodsId: Int64, payWay: String = "huifu") async -> IbApiResult {
        await post("/order/pay/CreateMarketOrder", body: [
            "market_goods_id": marketGoodsId, "pay_way": payWay, "pay_type": "4",
        ])
    }

    func batchBuy(goodsId: Int64, key: String, maxPrice: Double, num: Int = 1, payWay: String = "huifu") async -> IbApiResult {
        await post("/order/pay/batchBuy", body: [
            "goods_id": goodsId,
            "key": key,
            "pay_way": payWay,
            "price": String(format: "%.2f", maxPrice),
            "num": max(1, min(30, num)),
        ])
    }

    /// 求购列表 · collection_id + page + sort
    func begBuyList(collectionId: Int64, page: Int = 1, sort: String = "desc") async -> IbApiResult {
        await post("/market/trade/begBuyList", body: [
            "collection_id": collectionId,
            "page": max(1, page),
            "sort": sort.lowercased() == "asc" ? "asc" : "desc",
        ])
    }

    func getSellCollectionInfo(
        collectionId: Int64,
        buyId: Int64,
        orderId: Int64 = 0,
        number: Int = 1,
        payWay: String = "huifu",
        goodsType: Int = 2
    ) async -> IbApiResult {
        var body: [String: Any] = [
            "id": collectionId,
            "collection_id": collectionId,
            "type": goodsType,
            "number": max(1, number),
            "buy_id": buyId,
            "pay_way": payWay,
        ]
        if orderId > 0 { body["order_id"] = orderId }
        return await post("/market/trade/getSellCollectionInfo", body: body)
    }

    /// 卖给求购 · sell_data = base64(JSON [{buy_id, user_collection_id}])
    func sellToBeg(pairs: [(buyId: Int64, userCollectionId: Int64)], payWay: String, payPassword: String) async -> IbApiResult {
        let arr: [[String: Any]] = pairs.compactMap { p in
            guard p.buyId > 0, p.userCollectionId > 0 else { return nil }
            return ["buy_id": p.buyId, "user_collection_id": p.userCollectionId]
        }
        guard !arr.isEmpty,
              let raw = try? JSONSerialization.data(withJSONObject: arr) else {
            return IbApiResult(ok: false, code: -1, msg: "无可售配对")
        }
        return await post("/market/trade/sell", body: [
            "sell_data": raw.base64EncodedString(),
            "pay_way": payWay,
            "pay_password": payPassword,
        ])
    }

    func loginAccount(account: String, password: String) async -> IbApiResult {
        let bare = IbproClient(token: "", deviceId: deviceId)
        return await bare.post("/user/login", body: ["account": account, "password": password])
    }

    private func headers() -> [String: String] {
        var h = [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json;charset=UTF-8",
            "deviceType": "ios",
            "deviceId": deviceId,
        ]
        if !token.isEmpty { h["token"] = token.trimmingCharacters(in: .whitespacesAndNewlines) }
        return h
    }

    private func get(_ path: String) async throws -> IbApiResult {
        var req = URLRequest(url: URL(string: base + (path.hasPrefix("/") ? path : "/\(path)"))!)
        req.httpMethod = "GET"
        for (k, v) in headers() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await http.data(for: req)
        return Self.execute(data: data, status: (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func post(_ path: String, body: [String: Any]) async -> IbApiResult {
        do {
            var req = URLRequest(url: URL(string: base + (path.hasPrefix("/") ? path : "/\(path)"))!)
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            for (k, v) in headers() { req.setValue(v, forHTTPHeaderField: k) }
            let (data, resp) = try await http.data(for: req)
            return Self.execute(data: data, status: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return IbApiResult(ok: false, code: -1, msg: error.localizedDescription, httpStatus: 0)
        }
    }

    private static func execute(data: Data, status: Int) -> IbApiResult {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (json["code"] as? NSNumber)?.intValue ?? (json["code"] as? Int) ?? (status == 200 ? 1 : -1)
        let msg = (json["msg"] as? String) ?? (json["message"] as? String) ?? ""
        let dataObj: [String: Any]
        if let d = json["data"] as? [String: Any] {
            dataObj = d
        } else if let arr = json["data"] as? [Any] {
            dataObj = ["list": arr]
        } else {
            dataObj = [:]
        }
        return IbApiResult(ok: code == 1, code: code, msg: msg, data: dataObj, httpStatus: status, raw: json)
    }

    static func parseSaleList(_ data: [String: Any]) -> [IbSaleItem] {
        let arr = (data["list"] as? [Any]) ?? (data["data"] as? [Any]) ?? (data["items"] as? [Any]) ?? []
        var out: [IbSaleItem] = []
        for raw in arr {
            guard let it = raw as? [String: Any] else { continue }
            let id = JSONX.int64Val(it["id"]) ?? JSONX.int64Val(it["goods_id"]) ?? 0
            guard id > 0 else { continue }
            // 对齐网站 / Android：优先顶层 batch_id，再 batch.id（batch.id==0 时不能挡住顶层）
            let batch = it["batch"] as? [String: Any]
            let topBatch = JSONX.int64Val(it["batch_id"]) ?? 0
            let nestedBatch = JSONX.int64Val(batch?["id"]) ?? 0
            let batchId = topBatch > 0 ? topBatch : nestedBatch
            var start = JSONX.stringVal(it["release_date_time_text"])
            if start.isEmpty { start = JSONX.stringVal(it["release_time_date_text"]) }
            if start.isEmpty { start = JSONX.stringVal(it["start_time"]) }
            if start.isEmpty { start = JSONX.stringVal(batch?["start_time"]) }
            var name = JSONX.stringVal(it["name"])
            if name.isEmpty { name = JSONX.stringVal(it["title"]) }
            if name.isEmpty { name = "ID \(id)" }
            var price = JSONX.stringVal(it["price"])
            if price.isEmpty, let n = it["price"] as? NSNumber { price = n.stringValue }
            var cover = JSONX.stringVal(it["listimg"])
            if cover.isEmpty { cover = JSONX.stringVal(it["cover"]) }
            out.append(IbSaleItem(
                id: id, name: name,
                cover: coverUrl(cover),
                goodsType: Int(JSONX.int64Val(it["goods_type"]) ?? JSONX.int64Val(it["model"]) ?? 2),
                batchId: batchId, startTime: start, price: price
            ))
        }
        return out
    }

    static func parseMarketList(_ data: [String: Any]) -> [IbMarketItem] {
        let arr = (data["list"] as? [Any]) ?? (data["data"] as? [Any]) ?? []
        var out: [IbMarketItem] = []
        for raw in arr {
            guard let it = raw as? [String: Any] else { continue }
            let product = it["product"] as? [String: Any] ?? [:]
            let id = JSONX.int64Val(it["id"]) ?? JSONX.int64Val(product["id"]) ?? 0
            guard id > 0 else { continue }
            let floor: String
            if let v = it["min_price"], "\(v)" != "null" { floor = "\(v)" }
            else if let v = it["price"] { floor = "\(v)" }
            else { floor = "" }
            var name = JSONX.stringVal(it["name"])
            if name.isEmpty { name = JSONX.stringVal(product["name"]) }
            if name.isEmpty { name = "ID \(id)" }
            var cover = JSONX.stringVal(it["listimg"])
            if cover.isEmpty { cover = JSONX.stringVal(it["cover"]) }
            if cover.isEmpty { cover = JSONX.stringVal(product["listimg"]) }
            out.append(IbMarketItem(
                id: id,
                name: name,
                cover: coverUrl(cover),
                floor: floor,
                goodsType: Int(JSONX.int64Val(it["goods_type"]) ?? JSONX.int64Val(it["model"]) ?? 2),
                key: JSONX.stringVal(it["key"]),
                batchPay: (it["batch_pay"] as? Bool == true) || (it["product_batch_buy"] as? Bool == true)
            ))
        }
        return out
    }

    static func coverUrl(_ raw: String) -> String {
        var c = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasPrefix("//") { c = "https:" + c }
        else if c.hasPrefix("/"), !c.hasPrefix("/static/") { c = "https://cache.iboxart.cn" + c }
        else if !c.isEmpty, !c.hasPrefix("http"), !c.hasPrefix("/") { c = "https://cache.iboxart.cn/\(c)" }
        return c
    }
}

