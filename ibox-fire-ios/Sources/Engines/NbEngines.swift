import Foundation

struct NbPresaleConfig {
    var token: String
    var pid: Int64
    var name: String = ""
    var quantity: Int = 1
    var fireAtEpochSec: Int64
    var proxies: [String]
    var concurrency: Int = 0 // 0 = all proxies
    var durationS: Double = 1200
    var peakS: Double = 60
}

final class NbPresaleEngine: @unchecked Sendable {
    private let cfg: NbPresaleConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: NbPresaleConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async {
        if cfg.proxies.isEmpty { onLog("无代理"); return }
        let n = cfg.concurrency > 0 ? min(cfg.concurrency, cfg.proxies.count) : cfg.proxies.count
        onLog("NB抢购 pid=\(cfg.pid) \(cfg.name) x\(cfg.quantity) workers=\(n)")
        let fireAt = Double(cfg.fireAtEpochSec)
        while !stop && Date().timeIntervalSince1970 < fireAt {
            let rem = fireAt - Date().timeIntervalSince1970
            if rem > 1 { try? await Task.sleep(nanoseconds: 200_000_000) }
            else { break }
        }
        onLog("NB开火!")
        let peakEnd = fireAt + cfg.peakS
        let deadline = fireAt + cfg.durationS
        var success = 0
        let lock = NSLock()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<n {
                let px = cfg.proxies[i]
                group.addTask {
                    let client = NewbeeClient(token: self.cfg.token, proxyUrl: px)
                    var fail = 0
                    while !self.stop && Date().timeIntervalSince1970 < deadline {
                        lock.lock(); let sc = success; lock.unlock()
                        if sc >= self.cfg.quantity { break }
                        let inPeak = Date().timeIntervalSince1970 < peakEnd
                        let r = await client.buy(pid: self.cfg.pid, qty: 1)
                        if r.ok {
                            lock.lock(); success += 1; let s = success; lock.unlock()
                            self.onLog("NB OK \(s)/\(self.cfg.quantity)")
                            if s >= self.cfg.quantity { self.stop = true; return }
                        } else {
                            fail += 1
                            if fail >= 3 && !inPeak {
                                self.onLog("代理连败标记死亡 \(px.prefix(24))…")
                                return
                            }
                            if !inPeak { try? await Task.sleep(nanoseconds: 300_000_000) }
                        }
                    }
                }
            }
        }
        onLog("NB抢购结束 成功\(success)")
    }
}

struct NbSnipeConfig {
    var token: String
    var productId: Int64
    var name: String = ""
    var maxPrice: Double
    var quantity: Int = 1
    var mode: String = "fast" // fast | batch | cross
    var intervalS: Double = 1.0
    var proxy: String = ""
    var durationS: Double = 3600
}

final class NbSnipeEngine: @unchecked Sendable {
    private let cfg: NbSnipeConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: NbSnipeConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async {
        let client = NewbeeClient(token: cfg.token, proxyUrl: cfg.proxy)
        onLog("NB捡漏 \(cfg.name) pid=\(cfg.productId) ≤¥\(cfg.maxPrice) mode=\(cfg.mode)")
        var bought = 0
        let deadline = Date().timeIntervalSince1970 + cfg.durationS
        while !stop && bought < cfg.quantity && Date().timeIntervalSince1970 < deadline {
            if let floor = await client.queryFloor(productId: cfg.productId) {
                if floor <= cfg.maxPrice {
                    onLog("地板 ¥\(floor) → 下单")
                    let r = await client.fastBuy(productId: cfg.productId, price: floor)
                    if r.ok {
                        bought += 1
                        onLog("NB捡漏成功 \(bought)/\(cfg.quantity)")
                    } else {
                        onLog("失败 \(r.message.prefix(40))")
                    }
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, cfg.intervalS) * 1_000_000_000))
        }
        onLog("NB捡漏结束 \(bought)/\(cfg.quantity)")
    }
}

struct SweepConfig {
    var token: String
    var groupId: Int64
    var sellerUserId: Int64 = 0
    var maxPrice: Double
    var quantity: Int = 1
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

    func run() async {
        guard let uid = JwtUtil.uid(cfg.token) else { onLog("无uid"); return }
        let client = IboxClient(token: cfg.token, deviceIdMode: .stableMD5)
        onLog("点对点扫货 gid=\(cfg.groupId) ≤¥\(cfg.maxPrice)")
        var bought = 0
        while !stop && bought < cfg.quantity {
            let path = "/public-market-service/digital-collection-groups/\(cfg.groupId)/consignment-orders?pageNo=1&pageSize=20&sortField=1&sortType=1&uid=\(uid)"
            let page = await client.get(path)
            for it in JSONX.dataList(page) {
                if stop || bought >= cfg.quantity { break }
                let price = JSONX.doubleVal(it["price"]) ?? 999999
                guard price <= cfg.maxPrice, let oid = JSONX.int64Val(it["id"]) else { continue }
                let r = await client.postJson("/order-create-service/consignment-orders/\(oid)/purchase?uid=\(uid)", body: ["paymentPlatformCode": 30])
                if JSONX.code(r) == 0 {
                    bought += 1
                    onLog("扫到 ¥\(price) \(bought)/\(cfg.quantity)")
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        onLog("扫货结束 \(bought)")
    }
}
