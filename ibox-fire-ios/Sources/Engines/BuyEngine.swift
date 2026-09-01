import Foundation

struct BuyConfig {
    var token: String
    var groupId: Int64
    var collectionName: String = ""
    var targetPrice: Double
    var quantity: Int
    var buyMode: String = "cross" // normal | cross | batch
    var batchIntervalS: Double = 6.0
    var proxy: String = ""
    var durationS: Double = 3600
    var autoPay: Bool = false
    var payPassword: String = ""
}

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
        let sleepNoMatch: UInt64 = 300
        let sleepCycle: UInt64 = 400

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
            if code == 0 {
                client = c
                onLog("鉴权通过 → \(label)")
                break
            }
        }
        guard let client else {
            onLog("本机直连市场接口全部失败；请换网络或加代理")
            return 0
        }

        var normalBought = 0, batchBought = 0, unpaid = 0, cycle = 0
        var nextBatchAt = Date().timeIntervalSince1970 * 1000
        var batchCooldownAt: Double = 0
        let deadline = Date().timeIntervalSince1970 + cfg.durationS

        func total() -> Int { normalBought + batchBought }

        while !stop && total() < qty && Date().timeIntervalSince1970 < deadline {
            cycle += 1
            let nowMs = Date().timeIntervalSince1970 * 1000
            if mode != "normal", nowMs >= nextBatchAt, nowMs >= batchCooldownAt {
                let maxCount = min(batchMax, qty - total())
                if maxCount > 0 {
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
                        let oid = ((JSONX.dataDict(r)["orderUUId"] as? String) ?? (JSONX.dataDict(r)["orderId"] as? String) ?? "")
                        let count = (JSONX.dataDict(r)["count"] as? Int) ?? 1
                        if let payer {
                            let pay = await payer.pay(ibox: client, orderId: oid, payPassword: cfg.payPassword)
                            if pay.ok {
                                batchBought += count
                                onLog("自动支付成功! 进度 \(total())/\(qty)")
                            } else if pay.passwordError {
                                onLog("密码错误! \(pay.detail)"); return total()
                            } else {
                                unpaid += 1
                                onLog("支付失败:\(pay.detail)")
                                if unpaid >= 2 { onLog("连续未付,停止"); return total() }
                                batchBought += count
                            }
                        } else {
                            onLog("下单成功 请手动支付 \(oid)")
                            batchBought += count
                        }
                    } else if code == 429 || msg.contains("过于频繁") {
                        batchCooldownAt = nowMs + 50_000
                        onLog("批购限流 冷却50s")
                    } else {
                        onLog("批购 c=\(code) \(msg.prefix(40))")
                    }
                    nextBatchAt = Date().timeIntervalSince1970 * 1000 + Double(batchIntervalMs)
                    if mode == "batch" {
                        try? await Task.sleep(nanoseconds: batchIntervalMs * 1_000_000)
                        continue
                    }
                }
            }

            if mode == "batch" {
                try? await Task.sleep(nanoseconds: sleepCycle * 1_000_000)
                continue
            }

            let listPath = "/public-market-service/digital-collection-groups/\(cfg.groupId)/consignment-orders?pageNo=1&pageSize=20&sortField=1&sortType=1&uid=\(uid)"
            let page = await client.get(listPath)
            let code = JSONX.code(page)
            if code != 0 {
                onLog("列表 c=\(code) \(JSONX.message(page).prefix(40))")
                try? await Task.sleep(nanoseconds: sleepCycle * 1_000_000)
                continue
            }
            let list = JSONX.dataList(page)
            var matched: [String: Any]?
            for it in list {
                guard let price = JSONX.doubleVal(it["price"]), price > 0, price <= cfg.targetPrice else { continue }
                matched = it
                break
            }
            guard let hit = matched else {
                try? await Task.sleep(nanoseconds: sleepNoMatch * 1_000_000)
                continue
            }
            let orderId = JSONX.int64Val(hit["id"]) ?? 0
            let price = JSONX.doubleVal(hit["price"]) ?? 0
            onLog("锁定 ¥\(price) oid=\(orderId)")
            let buyBody: [String: Any] = ["paymentPlatformCode": 30]
            let buy = await client.postJson("/order-create-service/consignment-orders/\(orderId)/purchase?uid=\(uid)", body: buyBody)
            let bc = JSONX.code(buy)
            let bmsg = JSONX.message(buy)
            if bc == 0 {
                let oid = (JSONX.dataDict(buy)["orderUUId"] as? String) ?? ""
                if let payer {
                    let pay = await payer.pay(ibox: client, orderId: oid, payPassword: cfg.payPassword)
                    if pay.ok { normalBought += 1; onLog("支付成功 \(total())/\(qty)") }
                    else if pay.passwordError { onLog("密码错误"); return total() }
                    else { unpaid += 1; onLog("支付失败"); if unpaid >= 2 { return total() }; normalBought += 1 }
                } else {
                    onLog("下单成功 请手动支付 \(oid)")
                    normalBought += 1
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            } else {
                onLog("购买失败 c=\(bc) \(bmsg.prefix(40))")
                try? await Task.sleep(nanoseconds: sleepCycle * 1_000_000)
            }
        }
        onLog("捡漏结束 成交 \(total())/\(qty)")
        return total()
    }
}
