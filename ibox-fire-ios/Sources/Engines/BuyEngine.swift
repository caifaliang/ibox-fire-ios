import Foundation

struct BuyConfig {
    var token: String
    var groupId: Int64
    var collectionName: String = ""
    var targetPrice: Double
    var quantity: Int
    var buyMode: String = "cross"
    var batchIntervalS: Double = 6.0
    var proxy: String = ""
    var durationS: Double = 3600
    var autoPay: Bool = false
    var payPassword: String = ""
}

/// 本地捡漏 — 对齐 Android BuyEngine（私人节奏 + 正确下单 API）。
final class BuyEngine: @unchecked Sendable {
    private let cfg: BuyConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: BuyConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        guard let uid = JwtUtil.uid(cfg.token) else {
            onLog("JWT 无 userId"); return 0
        }
        let proxy = cfg.proxy.isEmpty ? nil : cfg.proxy
        let payer: HfpayPayer? = (cfg.autoPay && !cfg.payPassword.isEmpty) ? HfpayPayer(iboxToken: cfg.token, proxyLine: proxy) : nil
        var mode = cfg.buyMode.lowercased()
        if !["normal", "cross", "batch"].contains(mode) { mode = "cross" }
        let batchIntervalMs = UInt64(max(1.0, cfg.batchIntervalS) * 1000)
        let qty = max(1, cfg.quantity)
        let batchMax = 9
        let batchGapMs: UInt64 = 6_000
        let batch429CooldownMs: UInt64 = 50_000
        let normal429CooldownMs: UInt64 = 15_000
        let sleepNoMatch: UInt64 = 300
        let sleepCycle: UInt64 = 400
        let sleepBetweenBuys: UInt64 = 300

        onLog("捡漏启动[\(mode)] \(cfg.collectionName.isEmpty ? "-" : cfg.collectionName) gid=\(cfg.groupId) ≤¥\(cfg.targetPrice) x\(qty)")
        onLog(proxy == nil ? "⚡本地直连模式（私人节奏）" : "⚡私人代理模式")
        if payer != nil { onLog("自动支付已开启（汇付钱包）") }

        let probePath = "/public-market-service/digital-collection-groups/\(cfg.groupId)/consignment-orders?pageNo=1&pageSize=1&sortField=1&sortType=1&uid=\(uid)"
        let modes: [(DeviceIdMode, String)] = [(.random, "网站捡漏同款(随机UUID)"), (.stableMD5, "稳定MD5"), (.hash, "活动列表Hash")]
        var client: IboxClient?
        for (dm, label) in modes {
            if stop { return 0 }
            let c = IboxClient(token: cfg.token, proxyLine: proxy, deviceIdMode: dm)
            let r = await c.get(probePath)
            let code = JSONX.code(r)
            onLog("鉴权探测[\(label)] c=\(code) \(JSONX.message(r).prefix(50))")
            if code == 0 { client = c; onLog("鉴权通过 → \(label)"); break }
        }
        guard let client else {
            onLog("本机直连市场接口全部失败；请换网络或加代理")
            return 0
        }

        var normalBought = 0, batchBought = 0, unpaid = 0, cycle = 0
        var nextBatchAt = Date().timeIntervalSince1970 * 1000
        var batchCooldownAt: Double = 0
        var batchTimeouts = 0
        var consec403 = 0, consecBiz401 = 0
        let deadline = Date().timeIntervalSince1970 + cfg.durationS

        func total() -> Int { normalBought + batchBought }
        func jitter(_ ms: UInt64) -> UInt64 { ms == 0 ? 0 : UInt64(Double(ms) * (0.85 + Double.random(in: 0...0.3))) }
        func isFreq(_ code: Int64, _ msg: String) -> Bool {
            code == 429 || msg.contains("过于频繁") || msg.contains("请稍后再试") || msg.contains("限流")
        }

        func handleFatal(code: Int64, msg: String) async -> Bool {
            if code == -2 || code == -1 { return false }
            if code == 401 {
                if msg.contains("HTTP 401") { onLog("HTTP 401，Token 可能失效"); return true }
                consecBiz401 += 1
                onLog("业务401 \(msg.prefix(50)) (#\(consecBiz401)/2)")
                if consecBiz401 >= 2 { onLog("连续业务401，停止（换网络后再试）"); return true }
                return false
            }
            if code == 403 {
                consec403 += 1
                if consec403 >= 5 { onLog("连续5次403,确认IP被封"); return true }
                let wait = min(30 * consec403, 120)
                batchCooldownAt = Date().timeIntervalSince1970 * 1000 + Double(wait) * 1000
                onLog("403冷却\(wait)s(#\(consec403)/5) \(msg.prefix(60))")
                return false
            }
            if consec403 > 0 && code != -2 && code != -1 && code != 401 { consec403 = 0 }
            if consecBiz401 > 0 && code != 401 { consecBiz401 = 0 }
            return false
        }

        func doPayment(oid: String, isBatch: Bool, count: Int) async -> Bool {
            guard !oid.isEmpty else { return false }
            guard let payer else {
                onLog("下单成功 请手动支付 \(oid)")
                if isBatch { batchBought += count } else { normalBought += 1 }
                return false
            }
            onLog("支付中...")
            let pay = await payer.pay(ibox: client, orderId: oid, payPassword: cfg.payPassword)
            if pay.ok {
                unpaid = 0
                if isBatch { batchBought += count } else { normalBought += 1 }
                onLog("自动支付成功! \(pay.detail) 进度 \(total())/\(qty)")
                return false
            }
            if pay.passwordError { onLog("密码错误! \(pay.detail)"); return true }
            onLog("支付失败:\(pay.detail)")
            unpaid += 1
            if unpaid >= 2 { onLog("连续\(unpaid)单未付,停止"); return true }
            if isBatch { batchBought += count } else { normalBought += 1 }
            return false
        }

        func extractOrderId(_ data: [String: Any]) -> String {
            let d = JSONX.dataDict(data)
            for k in ["orderId", "orderUUId", "orderUuid"] {
                if let s = d[k] as? String, !s.isEmpty { return s }
            }
            return ""
        }

        func runBatchStep() async -> Bool {
            let nowMs = Date().timeIntervalSince1970 * 1000
            if nowMs < nextBatchAt || nowMs < batchCooldownAt { return false }
            let maxCount = min(batchMax, qty - total())
            if maxCount <= 0 { return false }
            onLog("批量购买 #\(cycle)...")
            let body: [String: Any] = [
                "digitalCollectionGroupId": cfg.groupId,
                "maxCount": maxCount,
                "maxSinglePrice": cfg.targetPrice,
                "paymentPlatformCode": 30
            ]
            let r = await client.postJson("/order-create-service/batch-purchase-consignment-orders?uid=\(uid)", body: body)
            let code = JSONX.code(r)
            let msg = JSONX.message(r)
            if code == 0 {
                batchTimeouts = 0
                let oid = extractOrderId(r)
                var count = maxCount
                if !oid.isEmpty {
                    let detail = await client.get("/order-service/orders/\(oid)")
                    if JSONX.code(detail) == 0 {
                        let od = JSONX.dataDict(detail)
                        if let n = od["quantity"] as? Int, n > 0 { count = n }
                    }
                }
                if await doPayment(oid: oid, isBatch: true, count: count) { return true }
                if total() >= qty { return true }
                nextBatchAt = Date().timeIntervalSince1970 * 1000 + Double(batchGapMs)
                if mode == "batch" {
                    try? await Task.sleep(nanoseconds: batchIntervalMs * 1_000_000)
                    return true
                }
                return true
            }
            if isFreq(code, msg) {
                if mode == "batch" {
                    onLog("批购限流，休息60s")
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    return true
                }
                nextBatchAt = Date().timeIntervalSince1970 * 1000 + Double(batch429CooldownMs)
                onLog("批购限流 冷却\(batch429CooldownMs / 1000)s")
                return mode == "cross"
            }
            onLog("批购 c=\(code) \(msg.prefix(40))")
            if await handleFatal(code: code, msg: msg) { return true }
            if mode == "batch" {
                try? await Task.sleep(nanoseconds: batchIntervalMs * 1_000_000)
                return true
            }
            nextBatchAt = Date().timeIntervalSince1970 * 1000 + Double(batchGapMs)
            return false
        }

        func runNormalStep() async -> Bool {
            let path = "/public-market-service/digital-collection-groups/\(cfg.groupId)/consignment-orders?pageNo=1&pageSize=20&sortField=1&sortType=1&uid=\(uid)"
            let page = await client.get(path)
            let code = JSONX.code(page)
            let msg = JSONX.message(page)
            if await handleFatal(code: code, msg: msg) { return true }
            if isFreq(code, msg) {
                onLog("列表 c=\(code) \(msg.prefix(40)) 冷却\(normal429CooldownMs / 1000)s")
                try? await Task.sleep(nanoseconds: normal429CooldownMs * 1_000_000)
                return false
            }
            if code != 0 {
                onLog("列表 c=\(code) \(msg.prefix(40))")
                return false
            }
            var targets: [(Int64, Double)] = []
            for it in JSONX.dataList(page) {
                if it["isBelongUser"] as? Bool == true { continue }
                if let st = it["orderStatus"] as? Int, st != 2 { continue }
                guard let price = JSONX.doubleVal(it["price"]), price > 0, price <= cfg.targetPrice else { continue }
                let did = JSONX.int64Val(it["digitalCollectionId"])
                    ?? JSONX.int64Val(it["id"])
                    ?? JSONX.int64Val((it["digitalCollection"] as? [String: Any])?["id"])
                guard let dcId = did, dcId > 0 else { continue }
                targets.append((dcId, price))
            }
            if targets.isEmpty {
                try? await Task.sleep(nanoseconds: jitter(sleepNoMatch))
                return false
            }
            for (ni, pair) in targets.enumerated() {
                if stop || normalBought >= qty || total() >= qty { break }
                let (did, price) = pair
                let buy = await client.postJson(
                    "/order-create-service/purchase-consignment-orders",
                    body: ["digitalCollectionId": did, "paymentPlatformCode": 30]
                )
                let bc = JSONX.code(buy)
                let bmsg = JSONX.message(buy)
                if await handleFatal(code: bc, msg: bmsg) { return true }
                if bc == 0 {
                    let oid = extractOrderId(buy)
                    onLog("普通下单 #\(cycle)/\(ni + 1)/¥\(price) \(oid)")
                    if await doPayment(oid: oid, isBatch: false, count: 1) { return true }
                } else if bc == 429 {
                    onLog("普通下单 429限流 冷却\(normal429CooldownMs / 1000)s")
                    try? await Task.sleep(nanoseconds: normal429CooldownMs)
                    break
                } else {
                    onLog("购买失败 c=\(bc) \(bmsg.prefix(40))")
                }
                if ni < targets.count - 1 { try? await Task.sleep(nanoseconds: jitter(sleepBetweenBuys)) }
            }
            return false
        }

        while !stop && total() < qty && Date().timeIntervalSince1970 < deadline {
            cycle += 1
            let nowMs = Date().timeIntervalSince1970 * 1000
            if mode == "batch" || mode == "cross" {
                let doBatch = mode == "batch" ? batchTimeouts < 2 : (nowMs >= nextBatchAt && batchTimeouts < 2)
                if doBatch {
                    if await runBatchStep() { break }
                    if mode == "batch" { continue }
                }
            }
            if mode != "batch" {
                if await runNormalStep() { break }
            }
            if total() < qty && !stop {
                try? await Task.sleep(nanoseconds: jitter(sleepCycle))
            }
        }
        onLog("捡漏结束 成交 \(total())/\(qty)")
        return total()
    }
}
