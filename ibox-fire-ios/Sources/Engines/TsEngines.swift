import Foundation

struct TsSnipeConfig {
    var token: String
    var goodsId: Int64
    var name: String
    var goodsType: Int
    var maxPrice: Double
    var quantity: Int
    /// auto | fast | batch — auto：有 batch_pay 先批量，失败回落快捷
    var mode: String
    var preferBatch: Bool
    var batchNum: Int
    var autoPay: Bool
    var payPassword: String
    var durationS: TimeInterval = 3600
    var proxy: String = ""
}

/// 炬星捡漏：盯盘地板 → batch/fast → doPay（汇付+支付密码）。
final class TsSnipeEngine: @unchecked Sendable {
    private let cfg: TsSnipeConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: TsSnipeConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async {
        let qty = max(1, cfg.quantity)
        let mode = ["auto", "fast", "batch"].contains(cfg.mode.lowercased()) ? cfg.mode.lowercased() : "auto"
        let client = TopstarClient(token: cfg.token, proxyUrl: cfg.proxy)
        let deadline = Date().timeIntervalSince1970 + cfg.durationS
        let title = cfg.name.isEmpty ? "GID \(cfg.goodsId)" : cfg.name

        onLog("捡漏启动[\(mode)] \(title) ≤¥\(cfg.maxPrice) x\(qty)")
        onLog(cfg.proxy.isEmpty ? "本地直连 api.topstar.art" : "私人代理模式")
        if cfg.autoPay && !cfg.payPassword.isEmpty { onLog("已开启自动支付（汇付）") }

        // 拉详情拿 key / batch_pay
        var key = ""
        var batchPay = cfg.preferBatch
        var batchNum = max(1, cfg.batchNum)
        do {
            let det = try await client.productDetail(id: cfg.goodsId)
            key = JSONX.stringVal(det["key"])
            if let bp = det["batch_pay"] as? Bool { batchPay = bp }
            else if let n = JSONX.int64Val(det["batch_pay"]) { batchPay = n == 1 }
            if let n = JSONX.int64Val(det["batch_pay_num"]), n > 0 { batchNum = Int(n) }
            if let floor = JSONX.doubleVal(det["min_price"]) ?? JSONX.doubleVal(det["price"]) {
                onLog("详情 地板≈¥\(floor) batch=\(batchPay ? "开" : "关")")
            }
        } catch {
            onLog("详情失败: \(error.localizedDescription.prefix(80))")
        }
        guard !key.isEmpty else {
            onLog("无商品 key，无法下单"); return
        }

        var success = 0
        var emptyTicks = 0
        let intervalMs: UInt64 = mode == "batch" ? 2000 : 1000

        while !stop && success < qty {
            if Date().timeIntervalSince1970 >= deadline { onLog("已达最长时长，结束"); break }
            let floor = await client.queryFloor(goodsId: cfg.goodsId, goodsType: cfg.goodsType)
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

            let wantBatch: Bool
            switch mode {
            case "batch": wantBatch = true
            case "fast": wantBatch = false
            default: wantBatch = batchPay
            }

            var buy: TsBuyResult
            var usedBatch = false
            if wantBatch {
                let n = min(batchNum, max(1, qty - success))
                buy = await client.batchBuy(goodsId: cfg.goodsId, key: key, maxPrice: cfg.maxPrice, num: n)
                usedBatch = true
                if !buy.ok, buy.message.contains("未开启") || buy.message.contains("未开放") || buy.message.contains("不支持") {
                    onLog("批量不可用(\(buy.message.prefix(40)))，改快捷")
                    buy = await client.fastBuy(goodsId: cfg.goodsId, key: key)
                    usedBatch = false
                }
            } else {
                buy = await client.fastBuy(goodsId: cfg.goodsId, key: key)
            }

            let action = usedBatch ? "批量" : "快捷"
            let unpaidHint = buy.message.contains("未付款") || buy.message.contains("未支付") || buy.message.contains("待支付")
                || (!buy.orderId.isEmpty || !buy.orderSn.isEmpty)

            if cfg.autoPay && !cfg.payPassword.isEmpty && (!buy.orderId.isEmpty || !buy.orderSn.isEmpty || buy.ok || unpaidHint) {
                let orderType = usedBatch ? 12 : 2
                let pay = await client.doPay(
                    orderId: buy.orderId,
                    orderSn: buy.orderSn,
                    orderType: orderType,
                    payPassword: cfg.payPassword
                )
                if pay.message.contains("密码") && (pay.message.contains("错误") || pay.message.contains("不正确")) {
                    onLog("支付密码错误，捡漏已停止: \(pay.message.prefix(80))")
                    break
                }
                if pay.ok {
                    let gained = usedBatch ? max(1, min(batchNum, qty - success)) : 1
                    success += gained
                    onLog("\(action) 成功 ¥\(floorF) (+\(gained)) +已支付")
                    if success >= qty { break }
                    if !(await waitMs(intervalMs)) { break }
                    continue
                } else if buy.ok || unpaidHint {
                    onLog("\(action) 已下单但支付失败: \(pay.message.prefix(80))")
                    if !(await waitMs(max(intervalMs, 3000))) { break }
                    continue
                }
            }

            if buy.ok {
                let gained = usedBatch ? max(1, min(batchNum, qty - success)) : 1
                success += gained
                onLog("\(action) 下单成功 ¥\(floorF) (+\(gained))")
            } else {
                onLog(String((buy.message.isEmpty ? "error" : buy.message).prefix(120)))
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
