import Foundation

struct NbPresaleConfig {
    var token: String
    var pid: Int64
    var name: String = ""
    var quantity: Int = 1
    var fireAtEpochSec: Int64
    var proxies: [String]
    var workers: Int = 10
    var earlyS: Double = 3.0
    var peakAfterS: Double = 60.0
    var durationS: Double = 1200.0
    var postPeakIntervalMs: UInt64 = 300
    var deadFailStreak: Int = 3
    var proxyExtractUrl: String = ""
    var autoPay: Bool = false
    var payPassword: String = ""
    var siteBase: String = "https://ai.iboxai.top/api"
}

struct NbSnipeConfig {
    var token: String
    var productId: Int64
    var name: String = ""
    var maxPrice: Double
    var quantity: Int = 1
    var mode: String = "cross"
    var proxy: String = ""
    var autoPay: Bool = false
    var payPassword: String = ""
    var siteBase: String = "https://ai.iboxai.top/api"
    var durationS: Double = 3600
}

private func nbPayPwdError(_ msg: String) -> Bool {
    msg.contains("C00136") || msg.contains("支付密码错误") || msg.contains("密码错误") ||
        msg.contains("密码不正确") || msg.contains("密码剩余")
}

private func nbExtractOrderId(_ data: [String: Any]) -> String {
    for k in ["order_id", "orderId", "id", "pay_order_id", "payOrderId", "order_sn"] {
        if let s = data[k] as? String, !s.isEmpty, s != "null" { return s }
        if let n = JSONX.int64Val(data[k]), n > 0 { return "\(n)" }
    }
    for nest in ["order", "pay_order", "data"] {
        if let inner = data[nest] as? [String: Any] {
            let oid = nbExtractOrderId(inner)
            if !oid.isEmpty { return oid }
        }
    }
    return ""
}

private func nbRunAutopay(api: ApiRepository, cfg: NbPresaleConfig, orderId: String, buyMsg: String, buyData: [String: Any]) async -> (Bool, String) {
    do {
        let r = try await api.newbeeAutopay(nbToken: cfg.token, payPassword: cfg.payPassword, orderId: orderId, buyMessage: buyMsg, buyData: buyData)
        return (r.paid, r.message)
    } catch {
        return (false, error.localizedDescription)
    }
}

/// 对齐 Android NbPresaleEngine：高峰多线程 → 单线程拖尾 → 代理补抽。
final class NbPresaleEngine: @unchecked Sendable {
    private let cfg: NbPresaleConfig
    private let onLog: (String) -> Void
    private var stop = false
    private let api = ApiRepository()

    init(cfg: NbPresaleConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
        self.api.siteBase = cfg.siteBase
    }

    func requestStop() { stop = true }

    func run() async {
        let now0 = Date().timeIntervalSince1970
        if now0 - Double(cfg.fireAtEpochSec) > 10 { onLog("开火时间已过，已放弃"); return }
        guard !cfg.proxies.isEmpty else { onLog("无代理"); return }

        let qty = max(1, cfg.quantity)
        let workers = max(1, min(20, min(cfg.workers, cfg.proxies.count)))
        onLog("NB抢购 \(cfg.name.isEmpty ? "pid=\(cfg.pid)" : cfg.name) x\(qty)")
        onLog("节奏: 高峰\(Int(cfg.peakAfterS))s×\(workers)线程 → 单线程\(cfg.postPeakIntervalMs)ms → 补抽 → 最长\(Int(cfg.durationS / 60))min")

        var proxies = cfg.proxies
        let fireStart = Double(cfg.fireAtEpochSec) - cfg.earlyS
        let warmStart = fireStart - 5.0
        if Date().timeIntervalSince1970 < warmStart {
            onLog(String(format: "等待预热窗口 %.1fs", warmStart - Date().timeIntervalSince1970))
            await waitUntil(warmStart)
        }
        onLog("轻预热 \(proxies.count)×1/IP…")
        await withTaskGroup(of: Void.self) { g in
            for px in proxies {
                g.addTask {
                    let c = NewbeeClient(token: self.cfg.token, proxyUrl: px, readMs: 1.8)
                    await c.warmUpCalendar()
                }
            }
        }
        if Date().timeIntervalSince1970 < fireStart {
            onLog(String(format: "等待开火 T-%.1fs", fireStart - Date().timeIntervalSince1970))
            await waitUntil(fireStart)
        }

        let peakEnd = Double(cfg.fireAtEpochSec) + cfg.peakAfterS
        let deadline = Double(cfg.fireAtEpochSec) + cfg.durationS
        onLog("开火! 高峰至+\(Int(cfg.peakAfterS))s")

        let lock = NSLock()
        var success = 0
        var sent: Int64 = 0

        await runPeak(proxies: proxies, workers: workers, qty: qty, peakEnd: peakEnd, deadline: deadline, success: &success, sent: &sent, lock: lock)

        if !stop && success < qty && Date().timeIntervalSince1970 < deadline {
            onLog("高峰结束 → 单线程拖尾")
            var batchNo = 1
            while !stop && success < qty && Date().timeIntervalSince1970 < deadline {
                let drained = await runSingleBatch(proxies: proxies, qty: qty, deadline: deadline, success: &success, sent: &sent, lock: lock, batchNo: batchNo)
                if stop || success >= qty || Date().timeIntervalSince1970 >= deadline { break }
                if !drained { break }
                onLog("批#\(batchNo) 代理耗尽，补抽…")
                do {
                    let pool = try await ProxyPool.extractAlivePool(ProxyPool.effectiveExtractUrl(cfg.proxyExtractUrl))
                    if pool.proxies.isEmpty {
                        onLog("补抽存活0条，结束 | \(pool.detail)")
                        break
                    }
                    proxies = pool.proxies
                    batchNo += 1
                    onLog("补抽就绪 批#\(batchNo) \(proxies.count) 条 → 继续单线程")
                } catch {
                    onLog("补抽失败: \(error.localizedDescription.prefix(80))")
                    break
                }
            }
        }
        lock.lock(); let sc = success; lock.unlock()
        onLog("结束: 成功 \(sc)/\(qty) 总发\(sent)")
    }

    private func runPeak(proxies: [String], workers: Int, qty: Int, peakEnd: Double, deadline: Double, success: inout Int, sent: inout Int64, lock: NSLock) async {
        let nPx = proxies.count
        var cooldown = [Int64](repeating: 0, count: nPx)
        let rrLock = NSLock()
        var rr: Int64 = 0
        await withTaskGroup(of: Void.self) { group in
            for wid in 0..<workers {
                group.addTask {
                    var local: Int64 = Int64(wid)
                    while !self.stop {
                        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                        let nowSec = Double(nowMs) / 1000.0
                        if nowSec >= peakEnd || nowSec >= deadline { break }
                        lock.lock(); let sc = success; lock.unlock()
                        if sc >= qty { break }
                        var idx: Int?
                        for _ in 0..<nPx {
                            let i: Int = rrLock.withLock {
                                let v = (rr + local) % Int64(nPx)
                                rr += 1
                                local += 1
                                return Int(v)
                            }
                            if cooldown[i] <= nowMs { idx = i; break }
                        }
                        guard let pxI = idx else { try? await Task.sleep(nanoseconds: 20_000_000); continue }
                        let died = await self.fireOnce(proxy: proxies[pxI], pxI: pxI, qty: qty, inPeak: true, intervalMs: 0, cooldown: &cooldown, success: &success, sent: &sent, lock: lock)
                        if died { /* peak 不标记死亡 */ }
                    }
                }
            }
        }
    }

    private func runSingleBatch(proxies: [String], qty: Int, deadline: Double, success: inout Int, sent: inout Int64, lock: NSLock, batchNo: Int) async -> Bool {
        let nPx = proxies.count
        guard nPx > 0 else { return true }
        var dead = [Bool](repeating: false, count: nPx)
        var cooldown = [Int64](repeating: 0, count: nPx)
        var failStreak = [Int](repeating: 0, count: nPx)
        var aliveLeft = nPx
        var rr = 0
        onLog("单线程拖尾 批#\(batchNo)(\(nPx)IP)")
        while !stop {
            lock.lock(); let sc = success; lock.unlock()
            if sc >= qty { return false }
            if Date().timeIntervalSince1970 >= deadline { return false }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            var idx: Int?
            for _ in 0..<nPx {
                let i = rr % nPx; rr += 1
                if !dead[i] && cooldown[i] <= nowMs { idx = i; break }
            }
            if idx == nil {
                if dead.allSatisfy({ $0 }) { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            let pxI = idx!
            let markDead = await fireOnce(proxy: proxies[pxI], pxI: pxI, qty: qty, inPeak: false, intervalMs: cfg.postPeakIntervalMs, cooldown: &cooldown, success: &success, sent: &sent, lock: lock, failStreak: &failStreak)
            if markDead && !dead[pxI] {
                dead[pxI] = true
                aliveLeft -= 1
                onLog("代理死 #\(pxI) 剩余活\(aliveLeft)/\(nPx)")
            }
        }
        lock.lock(); let sc = success; lock.unlock()
        return (dead.allSatisfy { $0 } || aliveLeft <= 0) && sc < qty && !stop
    }

    private func fireOnce(
        proxy: String, pxI: Int, qty: Int, inPeak: Bool, intervalMs: UInt64,
        cooldown: inout [Int64], success: inout Int, sent: inout Int64, lock: NSLock,
        failStreak: inout [Int]? = nil
    ) async -> Bool {
        let t0 = Date()
        var markDead = false
        do {
            let client = NewbeeClient(token: cfg.token, proxyUrl: proxy, readMs: inPeak ? 1.8 : 8)
            let buy = await client.buy(pid: cfg.pid, qty: 1)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            lock.lock(); sent += 1; lock.unlock()
            let code = buy.ok ? 1 : -1
            if !inPeak, var fs = failStreak {
                if buy.ok { fs[pxI] = 0 } else { fs[pxI] += 1; failStreak = fs }
            }
            if buy.ok {
                lock.lock(); success += 1; let sc = success; lock.unlock()
                let oid = nbExtractOrderId(buy.data)
                onLog("OK #\(sc)/\(qty) \(ms)ms oid=\(oid.isEmpty ? "-" : oid)")
                if cfg.autoPay && !cfg.payPassword.isEmpty {
                    onLog("支付中…")
                    let pay = await nbRunAutopay(api: api, cfg: cfg, orderId: oid, buyMsg: buy.message, buyData: buy.data)
                    onLog(pay.0 ? "自动支付成功 \(pay.1.prefix(40))" : "支付失败: \(pay.1.prefix(60))")
                    if nbPayPwdError(pay.1) { stop = true }
                }
                if sc >= qty { stop = true }
            } else if sent <= 3 || sent % 25 == 0 {
                onLog("#\(sent) \(ms)ms code=\(code) \(buy.message.prefix(60))")
            }
            if !inPeak, let fs = failStreak, fs[pxI] >= cfg.deadFailStreak {
                markDead = true
            }
            if !inPeak && intervalMs > 0 { try? await Task.sleep(nanoseconds: intervalMs * 1_000_000) }
        } catch {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            lock.lock(); sent += 1; lock.unlock()
            if !inPeak {
                if var fs = failStreak {
                    fs[pxI] += 1
                    if fs[pxI] >= cfg.deadFailStreak { markDead = true; fs[pxI] = 0 }
                    failStreak = fs
                }
                cooldown[pxI] = Int64(Date().timeIntervalSince1970 * 1000) + 500
            }
            if sent <= 3 { onLog("#\(sent) \(ms)ms ERR \(error.localizedDescription.prefix(80))") }
            if !inPeak && intervalMs > 0 { try? await Task.sleep(nanoseconds: intervalMs * 1_000_000) }
        }
        return markDead
    }

    private func waitUntil(_ epochSec: Double) async {
        while !stop {
            let left = epochSec - Date().timeIntervalSince1970
            if left <= 0 { return }
            try? await Task.sleep(nanoseconds: UInt64(max(10, min(200, (left - 0.03) * 1000))) * 1_000_000)
        }
    }
}

/// 对齐 Android NbSnipeEngine：盯盘 → fast/batch/cross + 自动支付。
final class NbSnipeEngine: @unchecked Sendable {
    private let cfg: NbSnipeConfig
    private let onLog: (String) -> Void
    private var stop = false
    private let api = ApiRepository()

    init(cfg: NbSnipeConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
        self.api.siteBase = cfg.siteBase
    }

    func requestStop() { stop = true }

    func run() async {
        let qty = max(1, cfg.quantity)
        let mode = ["fast", "batch", "cross"].contains(cfg.mode.lowercased()) ? cfg.mode.lowercased() : "fast"
        let intervalMs: UInt64 = mode == "batch" ? 2000 : 1000
        let modeLabel = mode == "fast" ? "快捷下单" : (mode == "batch" ? "批量购买" : "批量+快捷交叉")
        let client = NewbeeClient(token: cfg.token, proxyUrl: cfg.proxy)
        let maxMoney = String(format: "%.1f", cfg.maxPrice)
        let deadline = Date().timeIntervalSince1970 + cfg.durationS

        onLog("捡漏启动[\(modeLabel)] \(cfg.name.isEmpty ? "\(cfg.productId)" : cfg.name) ≤¥\(cfg.maxPrice) x\(qty)")
        onLog(cfg.proxy.isEmpty ? "本地直连" : "私人代理模式")
        if cfg.autoPay && !cfg.payPassword.isEmpty { onLog("已开启自动支付（汇付）") }

        var success = 0
        var tick = 0
        var emptyTicks = 0

        while !stop && success < qty {
            if Date().timeIntervalSince1970 >= deadline { onLog("已达最长时长，结束"); break }
            let floor = await client.queryFloor(productId: cfg.productId)
            if floor.status == "empty" {
                emptyTicks += 1
                if emptyTicks == 1 || emptyTicks % 20 == 0 { onLog(String(floor.message.prefix(120))) }
                if !(await waitMs(intervalMs)) { break }
                continue
            }
            if floor.status == "error" {
                onLog(String((floor.message.isEmpty ? "盯盘失败" : floor.message).prefix(120)))
                if !(await waitMs(intervalMs)) { break }
                continue
            }
            emptyTicks = 0
            guard let floorF = floor.floor else {
                onLog("地板无效")
                if !(await waitMs(intervalMs)) { break }
                continue
            }
            if floorF > cfg.maxPrice {
                onLog("盯盘 地板¥\(floorF) > 目标¥\(cfg.maxPrice)，本轮不下单")
                if !(await waitMs(intervalMs)) { break }
                continue
            }
            onLog("地板¥\(floorF) ≤ 目标¥\(cfg.maxPrice)，开火")

            let useBatch = mode == "cross" ? tick % 3 == 0 : mode == "batch"
            tick += 1
            let action = useBatch ? "批量" : "快捷"
            let buyNumReq = useBatch ? max(1, qty - success) : 1
            let buy = useBatch
                ? await client.batchBuy(productId: cfg.productId, buyNum: buyNumReq, maxMoney: maxMoney)
                : await client.fastBuy(productId: cfg.productId)

            let unpaidHint = buy.message.contains("未付款") || buy.message.contains("未支付") || buy.message.contains("待支付")

            if cfg.autoPay && !cfg.payPassword.isEmpty {
                var payData = buy.data
                if buy.batch {
                    payData["batch"] = true
                    if payData["buy_num"] == nil { payData["buy_num"] = buyNumReq }
                }
                let pay = await (try? api.newbeeAutopay(
                    nbToken: cfg.token, payPassword: cfg.payPassword, orderId: "",
                    buyMessage: buy.message, buyData: payData, proxy: cfg.proxy
                ).map { ($0.paid, $0.message) }) ?? (false, "支付请求失败")
                if nbPayPwdError(pay.1) {
                    onLog("支付密码错误，捡漏已停止: \(pay.1.prefix(80))")
                    break
                }
                if pay.0 {
                    var gained = action == "快捷" ? 1 : max(1, buyNumReq)
                    for k in ["num", "count", "buy_num", "success_num"] {
                        if let n = JSONX.int64Val(buy.data[k]), n > 0 { gained = Int(n); break }
                    }
                    if buy.ok || unpaidHint {
                        success += gained
                        onLog("\(action) 成功 ¥\(floorF) (+\(gained)) +已支付")
                        if success >= qty { break }
                        if !(await waitMs(intervalMs)) { break }
                        continue
                    }
                } else if buy.ok || unpaidHint {
                    onLog("\(action) 已下单但支付失败: \(pay.1.prefix(80))")
                    if !(await waitMs(max(intervalMs, 3000))) { break }
                    continue
                }
            }

            if buy.ok {
                var gained = action == "快捷" ? 1 : max(1, buyNumReq)
                for k in ["num", "count", "buy_num", "success_num"] {
                    if let n = JSONX.int64Val(buy.data[k]), n > 0 { gained = Int(n); break }
                }
                success += gained
                onLog("\(action) 成功 ¥\(floorF) (+\(gained))")
            } else {
                onLog(String((buy.message.isEmpty ? "error" : buy.message).prefix(120)))
                if unpaidHint {
                    if !(await waitMs(max(intervalMs, 2000))) { break }
                    continue
                }
            }
            if !(await waitMs(intervalMs)) { break }
        }
        onLog("结束: 成功 \(success)/\(qty)")
    }

    private func waitMs(_ ms: UInt64) async -> Bool {
        if ms == 0 { return !stop }
        let end = Date().timeIntervalSince1970 + Double(ms) / 1000
        while !stop {
            let remain = end - Date().timeIntervalSince1970
            if remain <= 0 { return true }
            try? await Task.sleep(nanoseconds: UInt64(min(remain, 0.2) * 1_000_000_000))
        }
        return false
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

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
