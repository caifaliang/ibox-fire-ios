import Foundation

struct QueryConfig {
    var token: String
    var groupId: Int64
    var collectionName: String = ""
    var kind: String // purchase | consignment
    var depth: Int
}

struct QueryTier: Identifiable {
    var id: String { String(format: "%.4f", price) }
    var price: Double
    var count: Int
}

struct QueryResult {
    var scanned: Int
    var apiTotal: Int
    var tiers: [QueryTier]
    var active: Int = 0
    var locked: Int = 0
    var pages: Int = 0
}

final class QueryEngine: @unchecked Sendable {
    private let cfg: QueryConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: QueryConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run(onProgress: @escaping (QueryResult) -> Void = { _ in }) async throws -> QueryResult {
        guard let uid = JwtUtil.uid(cfg.token) else { throw NSError(domain: "query", code: 1, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"]) }
        let depth = max(20, min(20_000, cfg.depth))
        let client = IboxClient(token: cfg.token, proxyLine: nil, connectMs: 8000, readMs: 15000, deviceIdMode: .stableMD5)
        let kindLabel = cfg.kind == "purchase" ? "求购" : "挂单"
        onLog("开始查\(kindLabel) · GID \(cfg.groupId) · 深度 \(depth) · 限速翻页")

        var prices: [Double] = []
        var apiTotal = 0, active = 0, locked = 0, pages = 0
        var sortValues = ""
        var pageNo = 1
        let maxPages = (depth + 19) / 20
        var pageGapMs: UInt64 = 450
        var afterLimitBoost = 0

        func emitProgress() {
            let tiers = Self.buildTiers(prices)
            onProgress(QueryResult(
                scanned: prices.count,
                apiTotal: apiTotal,
                tiers: tiers,
                active: active,
                locked: locked,
                pages: pages
            ))
        }

        while !stop && prices.count < depth && pages < maxPages {
            if pages > 0 {
                let gap: UInt64
                if afterLimitBoost > 0 {
                    afterLimitBoost -= 1
                    gap = 900
                } else {
                    gap = pageGapMs
                }
                try await Task.sleep(nanoseconds: (gap + UInt64.random(in: 0...200)) * 1_000_000)
            }
            if stop { break }

            let path: String
            if cfg.kind == "purchase" {
                path = "/public-market-service/digital-collection-groups/\(cfg.groupId)/purchase-orders?pageNo=\(pageNo)&pageSize=20&sortField=1&sortType=2&uid=\(uid)"
            } else {
                var p = "/public-market-service/digital-collection-groups/\(cfg.groupId)/consignment-orders?pageNo=1&pageSize=20&sortField=1&sortType=1&uid=\(uid)"
                if !sortValues.isEmpty { p += "&sortValues=\(sortValues)" }
                path = p
            }

            guard let fetched = await fetchWithBackoff(client, path) else { break }
            if fetched.hadLimit {
                afterLimitBoost = 8
                pageGapMs = 900
            }
            let payload = JSONX.dataDict(fetched.data)
            if pages == 0 { apiTotal = payload["total"] as? Int ?? (payload["total"] as? NSNumber)?.intValue ?? 0 }
            // JSONSerialization 常给出 [Any]，勿强转 [[String:Any]] 静默空列表
            let list: [[String: Any]] = {
                if let a = payload["list"] as? [[String: Any]] { return a }
                if let a = payload["list"] as? [Any] { return a.compactMap { $0 as? [String: Any] } }
                return []
            }()
            if list.isEmpty { break }
            pages += 1
            for it in list {
                if prices.count >= depth { break }
                guard let price = JSONX.doubleVal(it["price"]), price > 0 else { continue }
                prices.append(price)
                if cfg.kind != "purchase" {
                    let st = it["orderStatus"] as? Int ?? (it["orderStatus"] as? NSNumber)?.intValue ?? 2
                    if st == 3 { locked += 1 } else if st == 2 { active += 1 }
                }
            }
            emitProgress()
            if pages % 5 == 0 || prices.count >= depth {
                onLog("已扫 \(prices.count) / \(depth)")
            }
            // 接口已声明总量：扫满即停，避免坏游标把首页乘翻
            if apiTotal > 0 && prices.count >= apiTotal { break }
            if cfg.kind == "purchase" {
                if list.count < 20 { break }
                let hasMore = payload["hasMore"] as? Bool ?? (list.count >= 20)
                if !hasMore { break }
                pageNo += 1
            } else {
                // 对齐 APK：挂单必须用 sortValues 游标；pageNo++ 会反复首页 → 假 ×25
                let nextSv = Self.formatSortValues(payload)
                let hasMoreFlag = payload["hasMore"] as? Bool
                    ?? (payload["hasMore"] as? NSNumber)?.boolValue
                    ?? false
                let hasMore = hasMoreFlag && !nextSv.isEmpty
                if !hasMore { break }
                sortValues = nextSv
            }
        }

        let tiers = Self.buildTiers(prices)
        onLog("完成 扫描\(prices.count) 档位\(tiers.count)")
        let result = QueryResult(scanned: prices.count, apiTotal: apiTotal, tiers: tiers, active: active, locked: locked, pages: pages)
        onProgress(result)
        return result
    }

    private static func buildTiers(_ prices: [Double]) -> [QueryTier] {
        var map: [Double: Int] = [:]
        for p in prices { map[p, default: 0] += 1 }
        return map.keys.sorted().map { QueryTier(price: $0, count: map[$0]!) }
    }

    /// 对齐 Android QueryEngine.formatSortValues：`{ values: [a,b,c] }` → `a,b,c`
    private static func formatSortValues(_ payload: [String: Any]) -> String {
        if let sv = payload["sortValues"] as? [String: Any] {
            let vals: [Any]
            if let a = sv["values"] as? [Any] { vals = a }
            else if let a = sv["values"] as? [String] { vals = a }
            else { return "" }
            guard vals.count >= 3 else { return "" }
            return vals.prefix(3).map { "\($0)" }.joined(separator: ",")
        }
        if let s = payload["sortValues"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t
        }
        if let arr = payload["sortValues"] as? [Any], arr.count >= 3 {
            return arr.prefix(3).map { "\($0)" }.joined(separator: ",")
        }
        return ""
    }

    private func fetchWithBackoff(_ client: IboxClient, _ path: String) async -> (data: [String: Any], hadLimit: Bool)? {
        var backoff: UInt64 = 2500
        for _ in 0..<6 {
            if stop { return nil }
            let data = await client.get(path)
            let code = JSONX.code(data)
            let msg = JSONX.message(data)
            if code == 0 { return (data, false) }
            if code == 429 || msg.contains("过于频繁") {
                onLog("限流退避 \(backoff)ms")
                try? await Task.sleep(nanoseconds: backoff * 1_000_000)
                backoff = min(backoff * 2, 30_000)
                continue
            }
            if JwtUtil.isAuthFail(code: code, message: msg) {
                onLog("Token失效 c=\(code)")
                return nil
            }
            onLog("查询失败 c=\(code) \(msg.prefix(40))")
            return nil
        }
        return nil
    }
}
