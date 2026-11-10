import Foundation

struct IbPresaleConfig {
    var token: String
    var deviceId: String
    var goodsId: Int64
    var goodsType: Int = 2
    var batchId: Int64 = 0
    var productName: String = ""
    var quantity: Int = 1
    var fireAtEpochSec: Int64
    var earlyMs: Int64 = 800
    /// <=0 不限时
    var durationS: Double = 0
    var proxies: [String] = []
    var autoPay: Bool = false
    var payPassword: String = ""
    var payWay: String = "huifu"
}

struct IbSnipeConfig {
    var token: String
    var deviceId: String
    var goodsId: Int64
    var goodsType: Int = 2
    var goodsName: String = ""
    var maxPrice: Double
    var quantity: Int = 1
    /// auto | fast | batch | listing
    var buyMode: String = "auto"
    var intervalMs: UInt64 = 1000
    var proxies: [String] = []
    var autoPay: Bool = false
    var payPassword: String = ""
    var payWay: String = "huifu"
    var durationS: Double = 3600
}

/// ibPro 抢购：本机 + 可选易代理多路 CreateOrder
final class IbPresaleEngine: @unchecked Sendable {
    private let cfg: IbPresaleConfig
    private let onLog: (String) -> Void
    private var stop = false
    private let lock = NSLock()
    private var bought = 0
    private var attempts = 0

    init(cfg: IbPresaleConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        let target = max(1, cfg.quantity)
        let name = cfg.productName.isEmpty ? "ID \(cfg.goodsId)" : cfg.productName
        var lanes: [String?] = [nil]
        for p in cfg.proxies {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { lanes.append(t) }
        }
        // distinct
        var seen = Set<String>()
        lanes = lanes.filter { px in
            guard let px else { return true }
            if seen.contains(px) { return false }
            seen.insert(px); return true
        }

        let late = Date().timeIntervalSince1970 - Double(cfg.fireAtEpochSec)
        if late > 30 { onLog("开火时间已过 \(Int(late))s，已放弃"); return 0 }

        if cfg.proxies.isEmpty {
            onLog("本机直连抢购 \(name) x\(target) · 提前\(cfg.earlyMs)ms")
        } else {
            onLog("本机+易代理抢购 \(name) x\(target) · 路数=\(lanes.count) · 提前\(cfg.earlyMs)ms")
        }
        if cfg.autoPay && !cfg.payPassword.isEmpty { onLog("已开启自动支付") }

        let fireStartMs = Double(cfg.fireAtEpochSec) * 1000 - Double(max(0, cfg.earlyMs))
        let deadlineMs: Double = cfg.durationS > 0
            ? Double(cfg.fireAtEpochSec) * 1000 + cfg.durationS * 1000
            : .greatestFiniteMagnitude

        var left = fireStartMs - Date().timeIntervalSince1970 * 1000
        if left > 0 {
            onLog("等待开抢…")
            while !stop {
                left = fireStartMs - Date().timeIntervalSince1970 * 1000
                if left <= 0 { break }
                try? await Task.sleep(nanoseconds: UInt64(min(200, max(40, left)) * 1_000_000))
            }
        }
        if stop { return bought }

        onLog("预热 GET 发售列表…")
        var resolvedBatch = cfg.batchId
        var resolvedType = cfg.goodsType
        do {
            let list = try await IbproClient(token: cfg.token, deviceId: cfg.deviceId).saleList()
            onLog("预热 OK · \(list.count) 条")
            if let hit = list.first(where: { $0.id == cfg.goodsId }) {
                if hit.batchId > 0 { resolvedBatch = hit.batchId }
                if hit.goodsType > 0 { resolvedType = hit.goodsType }
            }
        } catch {
            onLog("预热失败: \(error.localizedDescription.prefix(80))")
        }
        if resolvedBatch <= 0 {
            onLog("中止：goods_id=\(cfg.goodsId) 无 batch_id，CreateOrder 会回「缺少批次参数」")
            return 0
        }
        onLog("参数 goods_id=\(cfg.goodsId) goods_type=\(resolvedType) batch_id=\(resolvedBatch)")

        onLog("开始循环 CreateOrder")
        await withTaskGroup(of: Void.self) { group in
            for (idx, px) in lanes.enumerated() {
                group.addTask { [self] in
                    let label = px == nil ? "本机" : "代理#\(idx)"
                    let client = IbproClient(token: cfg.token, deviceId: cfg.deviceId, proxyUrl: px ?? "", readMs: 8)
                    while !self.stop {
                        self.lock.lock()
                        let cur = self.bought
                        self.lock.unlock()
                        if cur >= target { break }
                        if Date().timeIntervalSince1970 * 1000 >= deadlineMs { break }
                        self.lock.lock(); self.attempts += 1; let n = self.attempts; self.lock.unlock()
                        let t0 = Date().timeIntervalSince1970
                        let r = await client.createOrder(
                            goodsId: cfg.goodsId, goodsType: resolvedType,
                            batchId: resolvedBatch, num: 1, payWay: cfg.payWay
                        )
                        let ms = Int((Date().timeIntervalSince1970 - t0) * 1000)
                        if IbproClient.isAuthFail(r) {
                            self.onLog("\(label) 鉴权失效: \(r.msg.prefix(60))")
                            self.stop = true
                            break
                        }
                        if r.ok {
                            self.lock.lock()
                            self.bought += 1
                            let got = self.bought
                            self.lock.unlock()
                            self.onLog("\(label) CreateOrder#\(n) 成功 \(ms)ms (\(got)/\(target)) \(r.msg.prefix(40))")
                            if cfg.autoPay && !cfg.payPassword.isEmpty {
                                let orderId = r.data["order_id"] ?? r.data["id"]
                                let sn = JSONX.stringVal(r.data["order_sn"]).ifEmpty(JSONX.stringVal(r.data["order_number"]))
                                let pr = await client.doPay(orderId: orderId, orderSn: sn, payPassword: cfg.payPassword, payWay: cfg.payWay)
                                self.onLog(pr.ok ? "\(label) doPay OK" : "\(label) doPay 失败: \(pr.msg.prefix(50))")
                            }
                            if got >= target { self.stop = true; break }
                        } else {
                            let msg = r.msg.isEmpty ? "code=\(r.code)" : r.msg
                            // 每条都打：售罄/防重也完整输出
                            self.onLog("\(label) #\(n) \(msg.prefix(80)) \(ms)ms")
                            if msg.contains("缺少批次") {
                                self.onLog("\(label) 缺 batch_id，停止本路")
                                break
                            }
                            let delayMs: UInt64
                            if msg.contains("重复提交") { delayMs = 120 }
                            else if msg.contains("售罄") || msg.contains("出售完") || msg.contains("已售完") || msg.contains("库存不足") {
                                delayMs = 60
                            } else { delayMs = 40 }
                            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                        }
                    }
                }
            }
        }
        onLog("结束: 成功 \(bought)/\(target) · 尝试 \(attempts)")
        return bought
    }
}

/// ibPro 二级市场捡漏
final class IbSnipeEngine: @unchecked Sendable {
    private let cfg: IbSnipeConfig
    private let onLog: (String) -> Void
    private var stop = false
    private let lock = NSLock()
    private var bought = 0

    init(cfg: IbSnipeConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        let target = max(1, cfg.quantity)
        let name = cfg.goodsName.isEmpty ? "ID \(cfg.goodsId)" : cfg.goodsName
        let gap = max(UInt64(400), cfg.intervalMs)
        let deadline = Date().timeIntervalSince1970 + max(60, cfg.durationS)
        let modeIn = ["auto", "fast", "batch", "listing"].contains(cfg.buyMode.lowercased())
            ? cfg.buyMode.lowercased() : "auto"

        if cfg.proxies.isEmpty {
            onLog("本机直连捡漏 · \(name) ≤¥\(cfg.maxPrice) x\(target) · \(modeIn)")
        } else {
            onLog("本机盯盘+多路下单 · \(name) ≤¥\(cfg.maxPrice) x\(target) · \(modeIn) · 代理\(cfg.proxies.count)")
        }
        if cfg.autoPay && !cfg.payPassword.isEmpty { onLog("已开启自动支付") }

        let watch = IbproClient(token: cfg.token, deviceId: cfg.deviceId)
        let det = await watch.marketGoodsDetail(goodsId: cfg.goodsId, goodsType: cfg.goodsType)
        if IbproClient.isAuthFail(det) { onLog("登录失效: \(det.msg.prefix(60))"); return 0 }
        if !det.ok { onLog("详情失败: \(det.msg.prefix(80))"); return 0 }
        let key = JSONX.stringVal(det.data["key"])
        let batchPay = (det.data["batch_pay"] as? Bool == true) || (det.data["product_batch_buy"] as? Bool == true)
        if key.isEmpty && modeIn != "listing" {
            onLog("无商品 key，无法快捷/批量（可试挂单模式）"); return 0
        }
        onLog("key就绪\(batchPay ? " · 支持批量" : "")")
        var loopMode = modeIn
        if modeIn == "auto" { loopMode = batchPay ? "batch" : "fast" }

        var lanes: [String?] = [nil]
        for p in cfg.proxies {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { lanes.append(t) }
        }

        var rounds = 0
        var consecNet = 0
        while !stop {
            lock.lock(); let cur = bought; lock.unlock()
            if cur >= target { break }
            if Date().timeIntervalSince1970 >= deadline { onLog("已达最长时长，结束"); break }
            rounds += 1
            let hang = await watch.hangList(goodsId: cfg.goodsId, goodsType: cfg.goodsType, page: 1)
            if hang.code == -1 && hang.httpStatus == 0 {
                consecNet += 1
                if rounds == 1 || consecNet % 4 == 0 { onLog("#\(rounds) 盯盘网络失败（\(consecNet)）") }
                if consecNet >= 8 { onLog("连续网络失败，停止"); break }
                try? await Task.sleep(nanoseconds: gap * 1_000_000)
                continue
            }
            consecNet = 0
            if IbproClient.isAuthFail(hang) { onLog("登录失效: \(hang.msg.prefix(60))"); break }
            let (floor, cheapest) = parseFloor(hang.data)
            guard let floor else {
                if rounds % 5 == 1 { onLog("#\(rounds) 暂无挂单") }
                try? await Task.sleep(nanoseconds: gap * 1_000_000)
                continue
            }
            if floor > cfg.maxPrice {
                if rounds % 4 == 1 { onLog("#\(rounds) 地板 ¥\(floor) > 目标 ¥\(cfg.maxPrice)") }
                try? await Task.sleep(nanoseconds: gap * 1_000_000)
                continue
            }
            onLog("#\(rounds) 命中地板 ¥\(floor) ≤ ¥\(cfg.maxPrice) · 下单")
            lock.lock(); let need = max(1, target - bought); lock.unlock()
            let marketId = JSONX.int64Val(cheapest?["id"]) ?? 0
            let preferBatch = loopMode == "batch"
            let preferListing = loopMode == "listing" && marketId > 0

            await withTaskGroup(of: Void.self) { group in
                for (idx, px) in lanes.enumerated() {
                    group.addTask { [self] in
                        self.lock.lock(); let done = self.bought >= target || self.stop; self.lock.unlock()
                        if done { return }
                        let client = IbproClient(token: cfg.token, deviceId: cfg.deviceId, proxyUrl: px ?? "", readMs: 10)
                        let label = px == nil ? "本机" : "代理#\(idx)"
                        var r: IbApiResult
                        var usedBatch = false
                        if preferListing {
                            r = await client.createMarketOrder(marketGoodsId: marketId, payWay: cfg.payWay)
                        } else if preferBatch {
                            usedBatch = true
                            r = await client.batchBuy(goodsId: cfg.goodsId, key: key, maxPrice: cfg.maxPrice, num: need, payWay: cfg.payWay)
                            let msg = r.msg
                            if !r.ok && (msg.contains("未开启") || msg.contains("未开放") || msg.contains("不支持") || msg.contains("批量")) {
                                usedBatch = false
                                r = await client.fastOrderNew(goodsId: cfg.goodsId, key: key, payWay: cfg.payWay)
                            }
                        } else {
                            r = await client.fastOrderNew(goodsId: cfg.goodsId, key: key, payWay: cfg.payWay)
                        }
                        self.lock.lock()
                        let alreadyDone = self.stop || self.bought >= target
                        self.lock.unlock()
                        if alreadyDone { return }
                        if IbproClient.isAuthFail(r) {
                            self.onLog("\(label) 鉴权失效: \(r.msg.prefix(50))")
                            self.stop = true
                            return
                        }
                        if r.ok {
                            self.lock.lock()
                            let add = usedBatch ? max(1, min(need, Int(JSONX.int64Val(r.data["num"]) ?? Int64(need)))) : 1
                            self.bought += add
                            let got = min(self.bought, target)
                            if self.bought >= target { self.stop = true }
                            self.lock.unlock()
                            self.onLog("\(label) 下单成功 +\(add)（\(got)/\(target)） \(r.msg.prefix(40))")
                            if cfg.autoPay && !cfg.payPassword.isEmpty {
                                let orderId = r.data["order_id"] ?? r.data["id"]
                                let sn = JSONX.stringVal(r.data["order_sn"]).ifEmpty(JSONX.stringVal(r.data["order_number"]))
                                let orderType = usedBatch ? 10 : 2
                                let pr = await client.doPay(orderId: orderId, orderSn: sn, payPassword: cfg.payPassword, payWay: cfg.payWay, orderType: orderType)
                                self.onLog(pr.ok ? "\(label) doPay OK" : "\(label) doPay 失败: \(pr.msg.prefix(50))")
                            }
                        } else if idx == 0 {
                            self.onLog("\(label) 下单失败: \(r.msg.prefix(50))")
                        }
                    }
                }
            }
            lock.lock(); let done = bought >= target; lock.unlock()
            if done { break }
            try? await Task.sleep(nanoseconds: gap * 1_000_000)
        }
        onLog("结束: 成功 \(bought)/\(target)")
        return min(bought, target)
    }

    private func parseFloor(_ data: [String: Any]) -> (Double?, [String: Any]?) {
        let list = (data["list"] as? [Any]) ?? (data["data"] as? [Any]) ?? []
        var floor: Double?
        var cheapest: [String: Any]?
        for raw in list {
            guard let it = raw as? [String: Any] else { continue }
            guard let p = JSONX.doubleVal(it["price"]) ?? JSONX.doubleVal(it["min_price"]), p > 0 else { continue }
            if floor == nil || p < floor! {
                floor = p
                cheapest = it
            }
        }
        return (floor, cheapest)
    }
}

/// ibPro 极速批量：详情拿 key 后直打 batchBuy（对齐 Android IbBatchEngine；捡漏默认走此引擎）
final class IbBatchEngine: @unchecked Sendable {
    private let cfg: IbSnipeConfig
    private let onLog: (String) -> Void
    private var stop = false
    private let lock = NSLock()
    private var bought = 0

    init(cfg: IbSnipeConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        let target = max(1, cfg.quantity)
        let name = cfg.goodsName.isEmpty ? "ID \(cfg.goodsId)" : cfg.goodsName
        let gap = min(2_000, max(120, cfg.intervalMs))
        let deadline = Date().timeIntervalSince1970 + max(60, cfg.durationS)

        if cfg.proxies.isEmpty {
            onLog("极速批量 · \(name) ≤¥\(cfg.maxPrice) x\(target) · 间隔\(gap)ms")
        } else {
            onLog("极速批量+多路 · \(name) ≤¥\(cfg.maxPrice) x\(target) · 代理\(cfg.proxies.count) · \(gap)ms")
        }
        if cfg.autoPay && !cfg.payPassword.isEmpty { onLog("已开启自动支付") }

        let watch = IbproClient(token: cfg.token, deviceId: cfg.deviceId)
        let det = await watch.marketGoodsDetail(goodsId: cfg.goodsId, goodsType: cfg.goodsType)
        if IbproClient.isAuthFail(det) { onLog("登录失效: \(det.msg.prefix(60))"); return 0 }
        if !det.ok { onLog("详情失败: \(det.msg.prefix(80))"); return 0 }
        let key = JSONX.stringVal(det.data["key"])
        if key.isEmpty { onLog("无商品 key，无法批量"); return 0 }
        let batchPay = (det.data["batch_pay"] as? Bool == true) || (det.data["product_batch_buy"] as? Bool == true)
        onLog("key就绪\(batchPay ? " · 支持批量" : " · 未标batch_pay仍尝试")")

        var lanes: [String?] = [nil]
        for p in cfg.proxies {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { lanes.append(t) }
        }
        var rounds = 0
        var consecFail = 0

        while !stop {
            lock.lock(); let cur = bought; lock.unlock()
            if cur >= target { break }
            if Date().timeIntervalSince1970 >= deadline { onLog("已达最长时长，结束"); break }
            rounds += 1
            lock.lock(); let need = max(1, target - bought); lock.unlock()
            onLog("#\(rounds) 直打 batchBuy x\(need) ≤¥\(cfg.maxPrice)")

            await withTaskGroup(of: Void.self) { group in
                for (idx, px) in lanes.enumerated() {
                    group.addTask { [self] in
                        self.lock.lock(); let done = self.stop || self.bought >= target; self.lock.unlock()
                        if done { return }
                        let client = IbproClient(token: cfg.token, deviceId: cfg.deviceId, proxyUrl: px ?? "", readMs: 8)
                        let label = px == nil ? "本机" : "代理#\(idx)"
                        let r = await client.batchBuy(goodsId: cfg.goodsId, key: key, maxPrice: cfg.maxPrice, num: need, payWay: cfg.payWay)
                        self.lock.lock()
                        defer { self.lock.unlock() }
                        if self.stop || self.bought >= target { return }
                        if IbproClient.isAuthFail(r) {
                            self.onLog("\(label) 鉴权失效: \(r.msg.prefix(80))")
                            self.stop = true
                            return
                        }
                        if r.ok {
                            consecFail = 0
                            let add = max(1, min(need, Int(JSONX.int64Val(r.data["num"]) ?? Int64(need))))
                            self.bought += add
                            let got = min(self.bought, target)
                            self.onLog("\(label) 批量成功 +\(add)（\(got)/\(target)） \(r.msg.prefix(80))")
                            if cfg.autoPay && !cfg.payPassword.isEmpty {
                                let orderId = r.data["order_id"] ?? r.data["id"]
                                let sn = JSONX.stringVal(r.data["order_sn"]).ifEmpty(JSONX.stringVal(r.data["order_number"]))
                                Task {
                                    let pr = await client.doPay(orderId: orderId, orderSn: sn, payPassword: cfg.payPassword, payWay: cfg.payWay, orderType: 10)
                                    self.onLog(pr.ok ? "\(label) doPay OK" : "\(label) doPay 失败: \(pr.msg.prefix(80))")
                                }
                            }
                            if self.bought >= target { self.stop = true }
                        } else if idx == 0 {
                            consecFail += 1
                            self.onLog("\(label) 失败: \(r.msg.prefix(80))")
                        }
                    }
                }
            }
            lock.lock(); let done = bought >= target; lock.unlock()
            if done { break }
            let wait = consecFail >= 12 ? gap * 4 : (consecFail >= 6 ? gap * 2 : gap)
            try? await Task.sleep(nanoseconds: wait * 1_000_000)
        }
        onLog("结束: 成功 \(bought)/\(target)")
        return min(bought, target)
    }
}

struct IbSellConfig {
    var token: String
    var deviceId: String
    var goodsId: Int64
    var goodsType: Int = 2
    var goodsName: String = ""
    var minPrice: Double
    var quantity: Int = 1
    var payPassword: String
    var payWay: String = "huifu"
    var intervalMs: UInt64 = 400
    var durationS: Double = 3600
}

/// ibPro 卖求购：begBuyList → getSellCollectionInfo → sell
final class IbSellEngine: @unchecked Sendable {
    private let cfg: IbSellConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: IbSellConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        guard !cfg.payPassword.isEmpty else { onLog("请填写支付密码"); return 0 }
        let qty = max(1, cfg.quantity)
        let name = cfg.goodsName.isEmpty ? "ID \(cfg.goodsId)" : cfg.goodsName
        let gap = max(UInt64(250), cfg.intervalMs)
        let client = IbproClient(token: cfg.token, deviceId: cfg.deviceId, readMs: 12)
        onLog("卖求购启动 \(name) id=\(cfg.goodsId) ≥¥\(cfg.minPrice) x\(qty)")
        var sold = 0
        var round = 0
        var usedBuyIds = Set<Int64>()
        let deadline = Date().timeIntervalSince1970 + max(60, cfg.durationS)
        var lastBest = -1.0

        while !stop && sold < qty && Date().timeIntervalSince1970 < deadline {
            round += 1
            let listResp = await client.begBuyList(collectionId: cfg.goodsId, page: 1, sort: "desc")
            if IbproClient.isAuthFail(listResp) { onLog("登录失效: \(listResp.msg.prefix(60))"); break }
            if listResp.code == -1 && listResp.httpStatus == 0 {
                onLog("求购列表网络失败"); try? await Task.sleep(nanoseconds: 1_000_000_000); continue
            }
            if !listResp.ok {
                if round % 4 == 1 { onLog("求购列表: \(listResp.msg.prefix(50))") }
                try? await Task.sleep(nanoseconds: gap * 1_000_000); continue
            }
            let items = Self.extractBegItems(listResp.data)
            if items.isEmpty {
                if round % 8 == 1 { onLog("求购:无订单/等待中") }
                try? await Task.sleep(nanoseconds: gap * 1_000_000); continue
            }
            let candidates = items.filter { $0.price >= cfg.minPrice && !usedBuyIds.contains($0.buyId) }
                .sorted { $0.price > $1.price }
            if candidates.isEmpty {
                let best = items.map(\.price).max() ?? 0
                if best != lastBest {
                    onLog("求购最高¥\(best) 未达目标¥\(cfg.minPrice)")
                    lastBest = best
                }
                try? await Task.sleep(nanoseconds: gap * 1_000_000); continue
            }
            for po in candidates {
                if stop || sold >= qty { break }
                onLog("#\(round) 尝试卖 ¥\(po.price) buy=\(po.buyId) order=\(po.orderId)")
                let lock = await client.getSellCollectionInfo(
                    collectionId: cfg.goodsId, buyId: po.buyId, orderId: po.orderId,
                    number: 1, payWay: po.payWay.isEmpty ? cfg.payWay : po.payWay, goodsType: cfg.goodsType
                )
                if IbproClient.isAuthFail(lock) { onLog("登录失效: \(lock.msg.prefix(50))"); return sold }
                if !lock.ok {
                    usedBuyIds.insert(po.buyId)
                    onLog("锁仓失败: \(lock.msg.prefix(50))")
                    try? await Task.sleep(nanoseconds: 200_000_000); continue
                }
                let pairs = Self.autoPair(lock.data)
                if pairs.isEmpty {
                    usedBuyIds.insert(po.buyId)
                    onLog("无可配对持仓")
                    try? await Task.sleep(nanoseconds: 300_000_000); continue
                }
                let sell = await client.sellToBeg(
                    pairs: pairs,
                    payWay: po.payWay.isEmpty ? cfg.payWay : po.payWay,
                    payPassword: cfg.payPassword
                )
                if IbproClient.isAuthFail(sell) { onLog("登录失效: \(sell.msg.prefix(50))"); return sold }
                if sell.ok {
                    sold += pairs.count
                    usedBuyIds.insert(po.buyId)
                    onLog("卖出成功! ¥\(po.price) (\(sold)/\(qty)) \(sell.msg.prefix(30))")
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if sold >= qty { break }
                } else {
                    if sell.msg.contains("密码") || (sell.data["password_error"] as? Bool == true) {
                        onLog("支付密码错误，停止"); return sold
                    }
                    usedBuyIds.insert(po.buyId)
                    onLog("卖出失败: \(sell.msg.prefix(50))")
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
            if sold < qty { try? await Task.sleep(nanoseconds: gap * 1_000_000) }
        }
        onLog("卖求购结束 成交 \(sold)/\(qty)")
        return sold
    }

    private struct BegItem {
        var buyId: Int64
        var orderId: Int64
        var price: Double
        var payWay: String
    }

    private static func extractBegItems(_ data: [String: Any]) -> [BegItem] {
        let list = (data["data"] as? [Any])
            ?? ((data["data"] as? [String: Any])?["data"] as? [Any])
            ?? (data["list"] as? [Any])
            ?? []
        var out: [BegItem] = []
        for raw in list {
            guard let it = raw as? [String: Any] else { continue }
            let buyId = JSONX.int64Val(it["id"]) ?? 0
            guard buyId > 0, let price = JSONX.doubleVal(it["price"]), price > 0 else { continue }
            out.append(BegItem(
                buyId: buyId,
                orderId: JSONX.int64Val(it["order_id"]) ?? 0,
                price: price,
                payWay: {
                    let p = JSONX.stringVal(it["pay_way"])
                    return p.isEmpty ? "huifu" : p
                }()
            ))
        }
        return out
    }

    private static func autoPair(_ data: [String: Any]) -> [(buyId: Int64, userCollectionId: Int64)] {
        let selected = data["selected"] as? [Any] ?? []
        let holdings = data["user_collection_list"] as? [Any] ?? []
        var available: [Int64] = []
        for raw in holdings {
            guard let h = raw as? [String: Any], let id = JSONX.int64Val(h["id"]), id > 0 else { continue }
            available.append(id)
        }
        guard !available.isEmpty else { return [] }
        var pairs: [(buyId: Int64, userCollectionId: Int64)] = []
        var hi = 0
        for raw in selected {
            if hi >= available.count { break }
            guard let slot = raw as? [String: Any] else { continue }
            let idVal = JSONX.int64Val(slot["id"]) ?? 0
            let buyId = idVal > 0 ? idVal : (JSONX.int64Val(slot["buy_id"]) ?? 0)
            let already = JSONX.int64Val(slot["user_collection_id"]) ?? 0
            let uc: Int64
            if already > 0 {
                uc = already
            } else {
                uc = available[hi]
                hi += 1
            }
            if buyId > 0 && uc > 0 { pairs.append((buyId, uc)) }
        }
        return pairs
    }
}

struct IbQueryConfig {
    var token: String
    var deviceId: String
    var goodsId: Int64
    var goodsType: Int = 2
    var goodsName: String = ""
    var depth: Int = 100
}

struct IbQueryTier {
    var price: Double
    var count: Int
}

/// ibPro 查挂单：翻页汇总价位分布
final class IbQueryEngine: @unchecked Sendable {
    private let cfg: IbQueryConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: IbQueryConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    @discardableResult
    func run() async -> (scanned: Int, tiers: [IbQueryTier]) {
        let depth = min(5_000, max(20, cfg.depth))
        let name = cfg.goodsName.isEmpty ? "ID \(cfg.goodsId)" : cfg.goodsName
        let client = IbproClient(token: cfg.token, deviceId: cfg.deviceId, readMs: 12)
        onLog("开始查挂单 · \(name) · ID \(cfg.goodsId) · 深度 \(depth)")

        var prices: [Double] = []
        var apiTotal = 0
        var active = 0
        var locked = 0
        var pages = 0
        var page = 1
        let maxPages = (depth + 19) / 20

        while !stop && prices.count < depth && pages < maxPages {
            if pages > 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
            if stop { break }
            let r = await client.hangList(goodsId: cfg.goodsId, goodsType: cfg.goodsType, page: page)
            if IbproClient.isAuthFail(r) { onLog("登录失效: \(r.msg.prefix(60))"); break }
            if !r.ok { onLog("挂单失败: \(r.msg.prefix(60))"); break }
            let list = Self.hangArray(r.data)
            if pages == 0 {
                apiTotal = Int(JSONX.int64Val(r.data["total"]) ?? 0)
                if apiTotal <= 0, let nested = r.data["data"] as? [String: Any] {
                    apiTotal = Int(JSONX.int64Val(nested["total"]) ?? 0)
                }
                if apiTotal <= 0 { apiTotal = list.count }
            }
            if list.isEmpty { break }
            pages += 1
            for it in list {
                if prices.count >= depth { break }
                guard let price = JSONX.doubleVal(it["price"]), price > 0 else { continue }
                prices.append(price)
                let st = Int(JSONX.int64Val(it["status"]) ?? 0)
                if st == 3 { locked += 1 } else { active += 1 }
            }
            onLog("进度 · 第\(pages)页 · 已扫 \(min(prices.count, depth)) / \(depth)")
            if list.count < 10 { break }
            page += 1
        }
        if stop { onLog("已停止查询") }
        let scanned = min(prices.count, depth)
        let sample = Array(prices.prefix(scanned))
        let tiers = Self.buildTiers(sample)

        onLog("──────── 查挂单结果 ────────")
        onLog("藏品  \(name)")
        onLog("ID    \(cfg.goodsId)")
        onLog("扫描  \(scanned) 单" + (apiTotal > 0 ? " / 接口合计 \(apiTotal)" : "") + " · \(pages) 页 · \(tiers.count) 个价位")
        if active > 0 || locked > 0 { onLog("状态  可购≈\(active) · 其他=\(locked)") }
        if let floor = sample.min(), let ceil = sample.max() {
            let mid = sample.sorted()[sample.count / 2]
            onLog("行情  地板 ¥\(Self.fmtPrice(floor)) · 最高 ¥\(Self.fmtPrice(ceil)) · 中位 ¥\(Self.fmtPrice(mid))")
        }
        onLog("──── 价位分布（低→高）────")
        if tiers.isEmpty {
            onLog("（无挂单数据）")
        } else {
            var cum = 0
            for (idx, t) in tiers.enumerated() {
                cum += t.count
                let pct = scanned > 0 ? Double(t.count) * 100 / Double(scanned) : 0
                let cumPct = scanned > 0 ? Double(cum) * 100 / Double(scanned) : 0
                onLog("#\(idx + 1) ¥\(Self.fmtPrice(t.price))  x\(t.count)  \(String(format: "%.1f", pct))%  累计\(String(format: "%.1f", cumPct))%")
            }
            onLog("合计 \(tiers.reduce(0) { $0 + $1.count }) 单 · \(tiers.count) 档")
        }
        return (scanned, tiers)
    }

    private static func hangArray(_ data: [String: Any]) -> [[String: Any]] {
        if let list = data["list"] as? [[String: Any]], !list.isEmpty { return list }
        if let list = data["data"] as? [[String: Any]], !list.isEmpty { return list }
        if let nested = data["data"] as? [String: Any] {
            if let list = nested["list"] as? [[String: Any]] { return list }
            if let list = nested["data"] as? [[String: Any]] { return list }
        }
        // Any 数组兜底
        let raw = (data["list"] as? [Any]) ?? (data["data"] as? [Any]) ?? []
        return raw.compactMap { $0 as? [String: Any] }
    }

    private static func buildTiers(_ prices: [Double]) -> [IbQueryTier] {
        guard !prices.isEmpty else { return [] }
        var map: [Double: Int] = [:]
        for p in prices.sorted() { map[p, default: 0] += 1 }
        return map.keys.sorted().map { IbQueryTier(price: $0, count: map[$0] ?? 0) }
    }

    private static func fmtPrice(_ p: Double) -> String {
        p == Double(Int64(p)) ? "\(Int64(p))" : String(format: "%.2f", p)
    }
}

private extension String {
    func ifEmpty(_ other: @autoclosure () -> String) -> String {
        isEmpty ? other() : self
    }
}
