import Foundation

struct NbMarketHit: Identifiable, Equatable {
    var id: Int64
    var name: String
    var floor: String = ""
}

struct NbPresaleItem: Identifiable, Equatable {
    var id: Int64 { pid }
    var pid: Int64
    var name: String
    var price: Double
    var startTime: String = ""
    var limit: Int? = nil
}

struct NbBuyResult {
    var ok: Bool
    var message: String
    var buyNum: Int = 1
    var data: [String: Any] = [:]
    var batch: Bool = false
}

/// NewBee 官方直连（x-token 签名，对齐 Android NewbeeClient）。
final class NewbeeClient: @unchecked Sendable {
    private static let xTokenKey = "6RNRDpjjV6wZ2ssPxqeIBeSoV1ITXDdC"
    private static let version = "9.32.21,2"
    private static let ua =
        "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/103.0.5060.53 Mobile Safari/537.36 Edg/103.0.1264.37"

    private let base = "https://api.newbee.net.cn"
    private let token: String
    private let session: URLSession
    private let readMs: TimeInterval

    init(token: String, proxyUrl: String = "", readMs: TimeInterval = 8) {
        self.token = token
        self.readMs = readMs
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = readMs
        if !proxyUrl.isEmpty, let ep = ProxyPool.parseEndpoint(ProxyPool.normalizeProxyUrl(proxyUrl)) {
            cfg.connectionProxyDictionary = [
                "HTTPEnable": 1, "HTTPProxy": ep.host, "HTTPPort": ep.port,
                "HTTPSEnable": 1, "HTTPSProxy": ep.host, "HTTPSPort": ep.port
            ]
        }
        session = URLSession(configuration: cfg)
    }

    static func xToken(path: String, params: [String: String]) -> String {
        var items = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }
        items.append("key=\(xTokenKey)")
        let raw = "\(path)?\(items.joined(separator: "&"))".lowercased()
        return md5Hex(raw)
    }

    private func headers(xt: String) -> [String: String] {
        [
            "x-token": xt,
            "token": token,
            "version": Self.version,
            "user-agent": Self.ua,
            "accept": "application/json"
        ]
    }

    private func parseJSON(_ data: Data, status: Int) throws -> [String: Any] {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw NSError(domain: "nb", code: status, userInfo: [NSLocalizedDescriptionKey: "空响应 HTTP\(status)"]) }
        if text.hasPrefix("<") {
            throw NSError(domain: "nb", code: status, userInfo: [NSLocalizedDescriptionKey: "官方接口被拦截(回了HTML HTTP\(status))"])
        }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "nb", code: status, userInfo: [NSLocalizedDescriptionKey: "非JSON HTTP\(status): \(text.prefix(80))"])
        }
        return o
    }

    private func getAllowFail(_ path: String, params: [String: String]) async -> (code: Int, data: Any?, msg: String) {
        let ts = "\(Int(Date().timeIntervalSince1970))"
        var signParams = params
        signParams["timestamp"] = ts
        let xt = Self.xToken(path: path, params: signParams)
        var comps = URLComponents(string: "\(base)/\(path)")!
        comps.queryItems = signParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        headers(xt: xt).forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let o = try parseJSON(data, status: status)
            let code = (o["code"] as? NSNumber)?.intValue ?? (o["code"] as? Int) ?? -1
            let msg = (o["msg"] as? String) ?? (o["message"] as? String) ?? ""
            return (code, o["data"], msg)
        } catch {
            return (-1, nil, error.localizedDescription)
        }
    }

    private func post(_ path: String, body: [String: String]) async throws -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970)
        var signBody = body
        signBody["timestamp"] = "\(ts)"
        let xt = Self.xToken(path: path, params: signBody)
        var jo: [String: Any] = [:]
        signBody.forEach { jo[$0.key] = $0.value }
        jo["timestamp"] = ts
        var req = URLRequest(url: URL(string: "\(base)/\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: jo)
        headers(xt: xt).forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return try parseJSON(data, status: status)
    }

    private func extractList(_ data: Any?) -> [[String: Any]] {
        if let arr = data as? [[String: Any]] { return arr }
        if let o = data as? [String: Any] {
            if let arr = o["list"] as? [[String: Any]] { return arr }
            if let arr = o["data"] as? [[String: Any]] { return arr }
        }
        return []
    }

    private func wrapBuy(_ r: [String: Any], batch: Bool, buyNum: Int) -> NbBuyResult {
        let code = (r["code"] as? NSNumber)?.intValue ?? (r["code"] as? Int) ?? -1
        let msg = (r["msg"] as? String) ?? (r["message"] as? String) ?? ""
        var data = r["data"] as? [String: Any] ?? [:]
        if batch {
            data["batch"] = true
            data["buy_num"] = buyNum
        }
        return NbBuyResult(ok: code == 1, message: msg.isEmpty ? (code == 1 ? "ok" : "请求失败") : msg, buyNum: buyNum, data: data, batch: batch)
    }

    func calendarList(page: Int = 1) async -> [NbPresaleItem] {
        let (code, data, _) = await getAllowFail("api/product/getCalendarList", params: ["page": "\(page)", "per_page": "30"])
        guard code == 1 else { return [] }
        return extractList(data).compactMap { it in
            let prod = it["product"] as? [String: Any] ?? [:]
            let pid = JSONX.int64Val(it["productId"]) ?? JSONX.int64Val(prod["id"]) ?? JSONX.int64Val(it["id"]) ?? 0
            guard pid > 0 else { return nil }
            return NbPresaleItem(
                pid: pid,
                name: (prod["subject"] as? String) ?? (it["name"] as? String) ?? "PID \(pid)",
                price: JSONX.doubleVal(prod["amount"]) ?? JSONX.doubleVal(it["amount"]) ?? 0,
                startTime: (prod["starttime"] as? String) ?? (it["starttime"] as? String) ?? "",
                limit: Int(JSONX.int64Val(prod["userMaxLimit"]) ?? JSONX.int64Val(it["userMaxLimit"]) ?? 0)
            )
        }
    }

    func buy(pid: Int64, qty: Int = 1) async -> NbBuyResult {
        do {
            let r = try await post("api/product/buy", body: ["pid": "\(pid)", "qty": "\(max(1, qty))"])
            return wrapBuy(r, batch: false, buyNum: qty)
        } catch {
            return NbBuyResult(ok: false, message: error.localizedDescription)
        }
    }

    func fastBuy(productId: Int64) async -> NbBuyResult {
        do {
            return wrapBuy(try await post("api/market/fastBuy", body: ["product_id": "\(productId)"]), batch: false, buyNum: 1)
        } catch {
            return NbBuyResult(ok: false, message: error.localizedDescription)
        }
    }

    func batchBuy(productId: Int64, buyNum: Int, maxMoney: String) async -> NbBuyResult {
        let n = max(1, min(30, buyNum))
        do {
            return wrapBuy(try await post("api/market/batchBuy", body: [
                "buy_num": "\(n)", "max_money": maxMoney, "product_id": "\(productId)", "pay_type": "140"
            ]), batch: true, buyNum: n)
        } catch {
            return NbBuyResult(ok: false, message: error.localizedDescription)
        }
    }

    func queryFloor(productId: Int64) async -> (status: String, floor: Double?, message: String, source: String) {
        let pid = productId
        let pl = await getAllowFail("api/v2/market/productList", params: [
            "per_page": "20", "product_id": "\(pid)", "page": "1", "sort": "ASC", "market_type": "0", "order": "price"
        ])
        if pl.code == 1 {
            var prices: [Double] = []
            var lockedN = 0
            for it in extractList(pl.data) {
                guard let pf = JSONX.doubleVal(it["amount"]) ?? JSONX.doubleVal(it["price"]) ?? JSONX.doubleVal(it["minamout"]), pf > 0 else { continue }
                prices.append(pf)
                if "\(it["status"] ?? "")" == "3" { lockedN += 1 }
            }
            if !prices.isEmpty {
                let src = lockedN > 0 && lockedN == prices.count ? "挂单·全锁定" : (lockedN > 0 ? "挂单·含锁定" : "挂单")
                return ("ok", prices.min(), pl.msg, src)
            }
        }
        let fp = await getAllowFail("api/market_collect/floorPrice", params: ["id": "\(pid)"])
        if fp.code == 1 {
            if let n = fp.data as? NSNumber { return ("ok", n.doubleValue, fp.msg, "floorPrice") }
            if let s = fp.data as? String, let f = Double(s), f > 0 { return ("ok", f, fp.msg, "floorPrice") }
            if let o = fp.data as? [String: Any] {
                for k in ["floor_price", "floorPrice", "minamout", "amount", "price"] {
                    if let f = JSONX.doubleVal(o[k]), f > 0 { return ("ok", f, fp.msg, "floorPrice") }
                }
            }
        }
        let en = await getAllowFail("api/v2/market/entrust_list", params: ["product_id": "\(pid)", "page": "1", "per_page": "20"])
        if en.code == 1 {
            let prices = extractList(en.data).compactMap { JSONX.doubleVal($0["amount"]) ?? JSONX.doubleVal($0["price"]) }.filter { $0 > 0 }
            if let min = prices.min() { return ("ok", min, en.msg, "委托") }
        }
        return ("empty", nil, "暂无挂单/委托", "")
    }

    func marketSearch(keyword: String) async -> [NbMarketHit] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }
        var map: [Int64: NbMarketHit] = [:]
        for pt in [19, 25] {
            let (code, data, msg) = await getAllowFail("api/v2/market/search", params: [
                "collection_id": "", "per_page": "20", "product_type": "\(pt)", "time_type": "1",
                "keywords": kw, "page": "1", "sort": "DESC", "hot": "0", "market_type": "0",
                "hasmarket": "-1", "order": "fluctuation"
            ])
            if code != 1 {
                if map.isEmpty && !msg.isEmpty { continue }
                continue
            }
            for row in extractList(data) {
                let prod = row["product"] as? [String: Any] ?? [:]
                let id = JSONX.int64Val(row["product_id"]) ?? JSONX.int64Val(row["productId"]) ?? JSONX.int64Val(row["id"]) ?? JSONX.int64Val(prod["id"]) ?? 0
                guard id > 0, map[id] == nil else { continue }
                let name = (prod["subject"] as? String) ?? (prod["name"] as? String) ?? (row["subject"] as? String) ?? (row["name"] as? String) ?? "PID \(id)"
                let floor = "\(row["amount"] ?? row["minamout"] ?? row["floor_price"] ?? prod["amount"] ?? "")"
                map[id] = NbMarketHit(id: id, name: name, floor: floor)
            }
            if !kw.isEmpty && map.values.contains(where: { $0.name.localizedCaseInsensitiveContains(kw) }) { break }
        }
        return Array(map.values)
    }

    func warmUpCalendar() async {
        _ = await getAllowFail("api/product/getCalendarList", params: ["page": "1", "per_page": "1"])
    }
}
