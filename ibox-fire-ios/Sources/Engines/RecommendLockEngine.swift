import Foundation

struct RecommendLockConfig {
    var token: String
    var quantity: Int
    var maxSinglePrice: Double = 0
    var pollMs: UInt64 = 300
    var durationS: Double = 3600 * 8
}

/// 推荐锁定：300ms 扫发现趋势上新并批量下单（对齐公告锁间隔）。
final class RecommendLockEngine: @unchecked Sendable {
    private let cfg: RecommendLockConfig
    private let onLog: (String) -> Void
    private var stop = false
    private var seen = Set<Int64>()
    private var locked = Set<Int64>()
    private var ready = false
    private let minFloor = 11.0

    init(cfg: RecommendLockConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        guard let uid = JwtUtil.uid(cfg.token) else {
            onLog("JWT 无 userId")
            return 0
        }
        let qty = max(1, cfg.quantity)
        let client = IboxClient(token: cfg.token, deviceIdMode: .stableMD5)
        let poll = min(max(cfg.pollMs, 200), 5_000)
        onLog("⚡推荐锁定 · 批量x\(qty) · activity-areas \(poll)ms · 本机直连")
        var success = 0
        var pollCount = 0
        let deadline = Date().timeIntervalSince1970 + cfg.durationS
        try? await Task.sleep(nanoseconds: poll * 1_000_000)
        onLog("开始轮询 activity-areas 间隔 \(poll)ms")
        while !stop && Date().timeIntervalSince1970 < deadline {
            do {
                onLog("请求 activity-areas…")
                let slots = await DiscoverPushEngine.fetchAreas(client)
                pollCount += 1
                let topTip: String = {
                    guard let t = slots.first else { return "-" }
                    let hint = t.1.isEmpty ? "GID" : String(t.1.prefix(20))
                    return "\(hint)(\(t.0))"
                }()
                onLog("轮询#\(pollCount) OK 已见\(seen.count) 已锁\(locked.count) 最新\(topTip)")
                if slots.isEmpty {
                    try? await Task.sleep(nanoseconds: poll * 1_000_000)
                    continue
                }
                let gids = Set(slots.map(\.0))
                if !ready {
                    seen = gids
                    ready = true
                    onLog("首轮补同步趋势 \(seen.count) 个（跳过旧槽），继续监听…")
                } else {
                    for (gid, hint) in slots {
                        if stop { break }
                        if seen.contains(gid) || locked.contains(gid) { continue }
                        seen.insert(gid)
                        let name = hint.isEmpty ? "GID\(gid)" : hint
                        let floor = await DiscoverPushEngine.getFloor(client, gid: gid)
                        let cap: Double = {
                            if cfg.maxSinglePrice > 0 { return cfg.maxSinglePrice }
                            if floor >= minFloor { return floor }
                            return 0
                        }()
                        if cap < minFloor {
                            onLog("跳过 \(name) · 地板/上限不足¥\(Int(minFloor))（floor=\(floor)）")
                            continue
                        }
                        onLog("上新锁定 · \(name)(\(gid)) · 批购≤¥\(Int(cap)) x\(qty)")
                        if await placeBatch(client, uid: uid, gid: gid, qty: qty, priceCap: cap) {
                            locked.insert(gid)
                            success += 1
                        }
                    }
                }
            } catch {
                onLog("推荐锁异常 · \(String(error.localizedDescription.prefix(60)))")
            }
            try? await Task.sleep(nanoseconds: poll * 1_000_000)
        }
        onLog("推荐锁定结束 · 成功 \(success)")
        return success
    }

    private func placeBatch(_ client: IboxClient, uid: Int64, gid: Int64, qty: Int, priceCap: Double) async -> Bool {
        let body: [String: Any] = [
            "digitalCollectionGroupId": gid,
            "maxCount": qty,
            "maxSinglePrice": priceCap,
            "paymentPlatformCode": 30,
            "level": -1
        ]
        let order = await client.postJson("/order-create-service/batch-purchase-consignment-orders?uid=\(uid)", body: body)
        if JSONX.code(order) != 0 {
            onLog("  批购失败 c=\(JSONX.code(order)) \(String(JSONX.message(order).prefix(40)))")
            return false
        }
        let d = JSONX.dataDict(order)
        var oid = JSONX.stringVal(d["orderId"])
        if oid.isEmpty { oid = JSONX.stringVal(d["id"]) }
        if oid.isEmpty { oid = JSONX.stringVal(d["orderUuid"]) }
        oid = oid.trimmingCharacters(in: .whitespaces)
        onLog("  批购成功 · 订单 \(oid.isEmpty ? "?" : oid)")
        if !oid.isEmpty {
            let pay = await client.get("/payment-service/cashiers/gain?orderUUId=\(oid)&paymentInitiatorType=0")
            let link = (JSONX.dataDict(pay)["link"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if !link.isEmpty { onLog("  支付直达 \(link)") }
            else { onLog("  待支付订单 \(oid)") }
        }
        return true
    }
}
