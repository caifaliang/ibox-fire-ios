import Foundation

struct TsMarketHit: Identifiable, Equatable {
    var id: Int64
    var name: String
    var floor: String = ""
    var goodsType: Int = 2
    var batchPay: Bool = false
    var batchPayNum: Int = 1
}

struct TsBuyResult {
    var ok: Bool
    var message: String
    var orderId: String = ""
    var orderSn: String = ""
    var batch: Bool = false
    var data: [String: Any] = [:]
}

/// 炬星 TOPSTAR 官方 H5 API（https://api.topstar.art/api）。
final class TopstarClient: @unchecked Sendable {
    private let base = "https://api.topstar.art/api"
    private let token: String
    private let http: ProxyURLSession

    init(token: String, proxyUrl: String = "", readMs: TimeInterval = 12) {
        self.token = token
        http = ProxyURLSession(proxyLine: proxyUrl.isEmpty ? nil : proxyUrl, timeout: readMs)
    }

    private func headers() -> [String: String] {
        [
            "token": token,
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json;charset=UTF-8",
            "Origin": "https://h5.topstar.art",
            "Referer": "https://h5.topstar.art/",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15"
        ]
    }

    private func parse(_ data: Data, status: Int) throws -> [String: Any] {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw NSError(domain: "ts", code: status, userInfo: [NSLocalizedDescriptionKey: "空响应 HTTP\(status)"])
        }
        if text.hasPrefix("<") {
            throw NSError(domain: "ts", code: status, userInfo: [NSLocalizedDescriptionKey: "接口异常(HTML HTTP\(status))"])
        }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ts", code: status, userInfo: [NSLocalizedDescriptionKey: "非JSON HTTP\(status)"])
        }
        return o
    }

    private func post(_ path: String, body: [String: Any], auth: Bool = true) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "\(base)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let hs = headers()
        for (k, v) in hs {
            if !auth && k == "token" { continue }
            req.setValue(v, forHTTPHeaderField: k)
        }
        if !auth { req.setValue(nil, forHTTPHeaderField: "token") }
        let (data, resp) = try await http.data(for: req)
        return try parse(data, status: (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func codeOf(_ o: [String: Any]) -> Int {
        (o["code"] as? NSNumber)?.intValue ?? (o["code"] as? Int) ?? -1
    }

    private func msgOf(_ o: [String: Any]) -> String {
        (o["msg"] as? String) ?? (o["message"] as? String) ?? ""
    }

    /// 账号密码登录（字段必须是 account，不是 mobile）。
    static func login(account: String, password: String) async throws -> (token: String, userId: Int64, nickname: String, mobile: String) {
        let c = TopstarClient(token: "")
        let o = try await c.post("user/login", body: ["account": account, "password": password], auth: false)
        guard c.codeOf(o) == 1 else {
            throw NSError(domain: "ts", code: 1, userInfo: [NSLocalizedDescriptionKey: c.msgOf(o).isEmpty ? "登录失败" : c.msgOf(o)])
        }
        let data = o["data"] as? [String: Any] ?? [:]
        let info = data["userinfo"] as? [String: Any] ?? data
        let token = JSONX.stringVal(info["token"])
        guard !token.isEmpty else {
            throw NSError(domain: "ts", code: 2, userInfo: [NSLocalizedDescriptionKey: "无 token"])
        }
        let uid = JSONX.int64Val(info["id"]) ?? JSONX.int64Val(info["user_id"]) ?? 0
        let nick = JSONX.stringVal(info["nickname"]).isEmpty ? JSONX.stringVal(info["username"]) : JSONX.stringVal(info["nickname"])
        let mobile = JSONX.stringVal(info["mobile"]).isEmpty ? account : JSONX.stringVal(info["mobile"])
        return (token, uid, nick, mobile)
    }

    func getUserInfo() async throws -> [String: Any] {
        let o = try await post("user/getUserInfo", body: [:])
        guard codeOf(o) == 1 else {
            throw NSError(domain: "ts", code: 1, userInfo: [NSLocalizedDescriptionKey: msgOf(o)])
        }
        return o["data"] as? [String: Any] ?? [:]
    }

    /// 市场搜索（keywords + goods_type=2）。
    func marketSearch(keyword: String) async -> [TsMarketHit] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }
        do {
            let o = try await post("market/market/getMarketList", body: [
                "page": 1,
                "keywords": kw,
                "goods_type": 2
            ])
            guard codeOf(o) == 1 else { return [] }
            let rows: [[String: Any]]
            if let arr = o["data"] as? [[String: Any]] {
                rows = arr
            } else if let d = o["data"] as? [String: Any], let arr = d["data"] as? [[String: Any]] {
                rows = arr
            } else {
                rows = []
            }
            return rows.compactMap { row in
                let prod = row["product"] as? [String: Any] ?? [:]
                let id = JSONX.int64Val(row["id"]) ?? JSONX.int64Val(prod["id"]) ?? 0
                guard id > 0 else { return nil }
                let name = JSONX.stringVal(row["name"]).isEmpty
                    ? (JSONX.stringVal(prod["name"]).isEmpty ? "GID \(id)" : JSONX.stringVal(prod["name"]))
                    : JSONX.stringVal(row["name"])
                let floor = "\(row["min_price"] ?? "")"
                let gt = Int(JSONX.int64Val(row["goods_type"]) ?? 2)
                return TsMarketHit(id: id, name: name, floor: floor, goodsType: gt)
            }
        } catch {
            return []
        }
    }

    /// 商品详情（含 batch_pay / key）。
    func productDetail(id: Int64) async throws -> [String: Any] {
        let o = try await post("market/market/marketGoodsDetail", body: ["id": id])
        guard codeOf(o) == 1 else {
            throw NSError(domain: "ts", code: 1, userInfo: [NSLocalizedDescriptionKey: msgOf(o)])
        }
        return o["data"] as? [String: Any] ?? [:]
    }

    /// 挂单列表（地板价看 list 最低价）。id + type(=goods_type) + sort=price。
    func hangList(goodsId: Int64, goodsType: Int = 2, page: Int = 1) async throws -> (list: [[String: Any]], floor: Double?) {
        let o = try await post("market/market/getMarketGoodsListByGoodsId", body: [
            "id": goodsId,
            "type": goodsType,
            "page": page,
            "sort": "price"
        ])
        guard codeOf(o) == 1 else {
            throw NSError(domain: "ts", code: 1, userInfo: [NSLocalizedDescriptionKey: msgOf(o)])
        }
        let data = o["data"] as? [String: Any] ?? [:]
        let list = data["list"] as? [[String: Any]] ?? []
        let prices = list.compactMap { JSONX.doubleVal($0["price"]) }.filter { $0 > 0 }
        return (list, prices.min())
    }

    func queryFloor(goodsId: Int64, goodsType: Int = 2) async -> (status: String, floor: Double?, message: String) {
        do {
            let r = try await hangList(goodsId: goodsId, goodsType: goodsType)
            if let f = r.floor { return ("ok", f, "挂单\(r.list.count)条") }
            return ("empty", nil, "暂无挂单")
        } catch {
            return ("error", nil, error.localizedDescription)
        }
    }

    /// 快捷下单（资格/非批量）。
    func fastBuy(goodsId: Int64, key: String, payWay: String = "huifu") async -> TsBuyResult {
        do {
            let o = try await post("order/pay/fastOrderNew", body: [
                "goods_id": goodsId,
                "key": key,
                "pay_way": payWay
            ])
            let data = o["data"] as? [String: Any] ?? [:]
            let ok = codeOf(o) == 1
            return TsBuyResult(
                ok: ok,
                message: msgOf(o).isEmpty ? (ok ? "下单成功" : "下单失败") : msgOf(o),
                orderId: "\(data["order_id"] ?? "")",
                orderSn: JSONX.stringVal(data["order_sn"]),
                batch: false,
                data: data
            )
        } catch {
            return TsBuyResult(ok: false, message: error.localizedDescription)
        }
    }

    /// 批量购买（有 batch_pay 时）。
    func batchBuy(goodsId: Int64, key: String, maxPrice: Double, num: Int, payWay: String = "huifu") async -> TsBuyResult {
        let n = max(1, min(30, num))
        do {
            let o = try await post("order/pay/batchBuy", body: [
                "goods_id": goodsId,
                "key": key,
                "pay_way": payWay,
                "price": String(format: "%.2f", maxPrice),
                "num": n
            ])
            let data = o["data"] as? [String: Any] ?? [:]
            let ok = codeOf(o) == 1
            return TsBuyResult(
                ok: ok,
                message: msgOf(o).isEmpty ? (ok ? "批量下单成功" : "批量失败") : msgOf(o),
                orderId: "\(data["order_id"] ?? "")",
                orderSn: JSONX.stringVal(data["order_sn"]),
                batch: true,
                data: data
            )
        } catch {
            return TsBuyResult(ok: false, message: error.localizedDescription)
        }
    }

    /// 汇付支付。快捷挂单 order_type=2；批量 order_type=12。字段对齐 H5：pay_type/order_number/pay_password。
    func doPay(
        orderId: String,
        orderSn: String,
        orderType: Int,
        payWay: String = "huifu",
        payPassword: String,
        payType: Int = 4
    ) async -> (ok: Bool, message: String) {
        let sn = orderSn.isEmpty ? orderId : orderSn
        guard !sn.isEmpty || !orderId.isEmpty else { return (false, "无订单号") }
        do {
            var body: [String: Any] = [
                "pay_type": payType,
                "order_number": sn,
                "order_type": orderType,
                "pay_way": payWay,
                "pay_password": payPassword,
                "pay_scene": "h5",
                "returnurl": "https://h5.topstar.art/#/pages/order/list"
            ]
            if !orderId.isEmpty { body["order_id"] = orderId }
            let o = try await post("order/pay/doPay", body: body)
            let ok = codeOf(o) == 1
            let data = o["data"] as? [String: Any] ?? [:]
            if ok, (data["balancePay"] as? Bool) == true || JSONX.stringVal(data["balancePay"]) == "1" {
                return (true, msgOf(o).isEmpty ? "支付成功" : msgOf(o))
            }
            return (ok, msgOf(o).isEmpty ? (ok ? "支付成功" : "支付失败") : msgOf(o))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
