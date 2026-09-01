import Foundation

struct NbPresaleItem: Identifiable {
    var id: Int64
    var pid: Int64
    var name: String
    var price: Double
    var startTime: String = ""
}

struct NbBuyResult {
    var ok: Bool
    var message: String
    var buyNum: Int = 1
}

final class NewbeeClient: @unchecked Sendable {
    private let base = "https://api.newbee.net.cn"
    private let token: String
    private let session: URLSession

    init(token: String, proxyUrl: String = "") {
        self.token = token
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        if !proxyUrl.isEmpty, let ep = ProxyPool.parseEndpoint(proxyUrl) {
            cfg.connectionProxyDictionary = [
                "HTTPEnable": 1, "HTTPProxy": ep.host, "HTTPPort": ep.port,
                "HTTPSEnable": 1, "HTTPSProxy": ep.host, "HTTPSPort": ep.port
            ]
        }
        session = URLSession(configuration: cfg)
    }

    private func signHeaders() -> [String: String] {
        let ts = "\(Int(Date().timeIntervalSince1970))"
        let raw = "\(token)\(ts)"
        let sig = md5Hex(raw)
        return [
            "x-token": token,
            "x-timestamp": ts,
            "x-sign": sig,
            "Content-Type": "application/json; charset=UTF-8",
            "User-Agent": "Mozilla/5.0",
            "accept": "application/json"
        ]
    }

    private func get(_ path: String, query: [String: Any] = [:]) async -> [String: Any] {
        var comps = URLComponents(string: "\(base)/\(path)")!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        var req = URLRequest(url: comps.url!)
        signHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, _) = try await session.data(for: req)
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch {
            return ["code": -1, "message": error.localizedDescription]
        }
    }

    private func post(_ path: String, body: [String: Any]) async -> [String: Any] {
        var req = URLRequest(url: URL(string: "\(base)/\(path)")!)
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        signHeaders().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, _) = try await session.data(for: req)
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch {
            return ["code": -1, "message": error.localizedDescription]
        }
    }

    func calendarList(page: Int = 1) async -> [NbPresaleItem] {
        let data = await get("api/product/getCalendarList", query: ["page": page, "per_page": 30])
        let arr = (data["data"] as? [[String: Any]])
            ?? ((data["data"] as? [String: Any])?["list"] as? [[String: Any]])
            ?? []
        return arr.compactMap { it in
            let prod = it["product"] as? [String: Any] ?? [:]
            let pid = JSONX.int64Val(it["productId"]) ?? JSONX.int64Val(prod["id"]) ?? JSONX.int64Val(it["id"]) ?? 0
            guard pid > 0 else { return nil }
            return NbPresaleItem(
                id: JSONX.int64Val(it["id"]) ?? pid,
                pid: pid,
                name: (prod["subject"] as? String) ?? (it["name"] as? String) ?? "PID \(pid)",
                price: JSONX.doubleVal(prod["amount"]) ?? JSONX.doubleVal(it["amount"]) ?? 0,
                startTime: (prod["starttime"] as? String) ?? (it["starttime"] as? String) ?? ""
            )
        }
    }

    func buy(pid: Int64, qty: Int = 1) async -> NbBuyResult {
        let r = await post("api/product/buy", body: ["pid": "\(pid)", "qty": "\(max(1, qty))"])
        let ok = (r["code"] as? Int) == 0 || (r["code"] as? NSNumber)?.intValue == 0 || r["status"] as? String == "ok"
        return NbBuyResult(ok: ok, message: (r["message"] as? String) ?? (r["msg"] as? String) ?? "", buyNum: qty)
    }

    func fastBuy(productId: Int64, price: Double) async -> NbBuyResult {
        let r = await post("api/market/fastBuy", body: ["productId": productId, "price": price])
        let ok = (r["code"] as? Int) == 0 || (r["code"] as? NSNumber)?.intValue == 0
        return NbBuyResult(ok: ok, message: (r["message"] as? String) ?? "", buyNum: 1)
    }

    func queryFloor(productId: Int64) async -> Double? {
        let r = await get("api/market/floor", query: ["productId": productId])
        if let d = JSONX.doubleVal((r["data"] as? [String: Any])?["floor"]) { return d }
        return JSONX.doubleVal(r["floor"])
    }

    func marketSearch(keyword: String) async -> [(id: Int64, name: String, floor: String)] {
        let r = await get("api/market/search", query: ["keyword": keyword])
        let arr = (r["data"] as? [[String: Any]]) ?? []
        return arr.compactMap { row in
            guard let id = JSONX.int64Val(row["id"]) else { return nil }
            return (id, row["name"] as? String ?? "", "\(row["floor"] ?? "")")
        }
    }
}
