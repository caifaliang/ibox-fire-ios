import Foundation

struct SegmentInfo: Identifiable, Equatable {
    var id: Int
    var name: String
}

struct SegmentSnipeConfig {
    var token: String
    var segmentId: Int
    var segmentName: String = ""
    var intervalMs: UInt64 = 3_000
    var dropPercent: Double = 10
    var maxBuyPrice: Double? = nil
    var quantity: Int = 1
    var maxSuccess: Int = 1
    var cooldownMs: TimeInterval = 300
    var autoPay: Bool = false
    var payPassword: String = ""
}

final class SegmentSnipeEngine: @unchecked Sendable {
    private let cfg: SegmentSnipeConfig
    private let onLog: (String) -> Void
    private var stop = false

    private struct FloorItem {
        var gid: Int64
        var name: String
        var floor: Double
        var dropPct: Double = 0
        var baseline: Double = 0
    }

    init(cfg: SegmentSnipeConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        guard let uid = JwtUtil.uid(cfg.token) else { onLog("JWT 无 userId"); return 0 }
        let interval = min(max(cfg.intervalMs, 1_000), 60_000)
        let dropNeed = max(0.1, cfg.dropPercent)
        let qty = max(1, cfg.quantity)
        let maxOk = max(1, cfg.maxSuccess)
        let client = IboxClient(token: cfg.token, deviceIdMode: .random)
        let payer: HfpayPayer? = (cfg.autoPay && !cfg.payPassword.isEmpty) ? HfpayPayer(iboxToken: cfg.token) : nil
        let segLabel = cfg.segmentName.isEmpty ? "板块\(cfg.segmentId)" : cfg.segmentName
        onLog("全盘捡漏启动 · \(segLabel)(id=\(cfg.segmentId))")
        onLog("间隔 \(interval)ms · 跌幅≥\(fmt(dropNeed))% · 数量\(qty) · 成功上限\(maxOk)")
        if let p = cfg.maxBuyPrice, p > 0 { onLog("最高买入价 ≤¥\(fmt(p))") }
        if payer != nil { onLog("自动支付已开启（汇付钱包）") }
        else { onLog("未开自动支付 · 下单后推送可点支付链接") }

        var baseline: [Int64: Double] = [:]
        var names: [Int64: String] = [:]
        var cooldownUntil: [Int64: TimeInterval] = [:]
        var success = 0
        var round = 0
        var coolUntil: TimeInterval = 0

        while !stop && success < maxOk {
            let now = Date().timeIntervalSince1970
            if now < coolUntil {
                let wait = min(coolUntil - now, Double(interval) / 1000)
                try? await Task.sleep(nanoseconds: UInt64(max(wait, 0.05) * 1_000_000_000))
                continue
            }
            round += 1
            let snap = await fetchSegmentFloors(client, segmentId: cfg.segmentId)
            if snap.rateLimited {
                coolUntil = Date().timeIntervalSince1970 + 5
                onLog("限流/频繁 · 冷5s后继续 (#\(round))")
                continue
            }
            if let err = snap.error {
                onLog("拉地板失败 #\(round) · \(err)")
                try? await Task.sleep(nanoseconds: interval * 1_000_000)
                continue
            }
            if snap.items.isEmpty {
                onLog("板块为空或无地板 #\(round)")
                try? await Task.sleep(nanoseconds: interval * 1_000_000)
                continue
            }
            if baseline.isEmpty {
                for it in snap.items where it.floor > 0 {
                    baseline[it.gid] = it.floor
                    names[it.gid] = it.name
                }
                onLog("基线就绪 \(baseline.count) 个藏品 · 开始盯盘")
                try? await Task.sleep(nanoseconds: interval * 1_000_000)
                continue
            }
            for it in snap.items where it.floor > 0 {
                if baseline[it.gid] == nil {
                    baseline[it.gid] = it.floor
                    names[it.gid] = it.name
                    onLog("新藏品入基线 \(it.name) gid=\(it.gid) ¥\(fmt(it.floor))")
                } else if !it.name.isEmpty {
                    names[it.gid] = it.name
                }
            }
            var hits: [FloorItem] = []
            for it in snap.items {
                guard it.floor > 0, let base = baseline[it.gid], base > 0 else { continue }
                let drop = (base - it.floor) / base * 100
                if drop + 1e-9 < dropNeed { continue }
                if let maxP = cfg.maxBuyPrice, maxP > 0, it.floor > maxP { continue }
                if now < (cooldownUntil[it.gid] ?? 0) { continue }
                hits.append(FloorItem(gid: it.gid, name: it.name, floor: it.floor, dropPct: drop, baseline: base))
            }
            if hits.isEmpty {
                var deepest = 0.0, deepName = "", deepNow = 0.0, deepBase = 0.0
                for it in snap.items {
                    guard it.floor > 0, let base = baseline[it.gid], base > 0 else { continue }
                    let d = (base - it.floor) / base * 100
                    if d > deepest {
                        deepest = d; deepName = it.name; deepNow = it.floor; deepBase = base
                    }
                }
                if deepest > 0 {
                    onLog("巡检 #\(round) · \(snap.items.count)个 · 最深\(fmt(deepest))% \(deepName.isEmpty ? "-" : deepName) ¥\(fmt(deepBase))→¥\(fmt(deepNow)) · 未达\(fmt(dropNeed))%")
                } else {
                    onLog("巡检 #\(round) · \(snap.items.count)个 · 暂无下跌 · 阈值\(fmt(dropNeed))%")
                }
                try? await Task.sleep(nanoseconds: interval * 1_000_000)
                continue
            }
            hits.sort { $0.dropPct > $1.dropPct }
            let top = hits[0]
            onLog("触发 \(top.name.isEmpty ? "gid=\(top.gid)" : top.name) 基线¥\(fmt(top.baseline)) → ¥\(fmt(top.floor)) 跌\(fmt(top.dropPct))%")
            let bought = await tryBuyOne(client, payer: payer, uid: uid, hit: top, qty: qty)
            cooldownUntil[top.gid] = Date().timeIntervalSince1970 + max(cfg.cooldownMs, 60)
            if bought > 0 {
                success += bought
                onLog("锁定成功 \(success)/\(maxOk) · 自动停止")
                break
            }
            try? await Task.sleep(nanoseconds: interval * 1_000_000)
        }
        if stop { onLog("收到停止信号") }
        onLog("全盘捡漏结束 · 成功 \(success)")
        return success
    }

    private struct SnapResult {
        var items: [FloorItem]
        var rateLimited: Bool = false
        var error: String? = nil
    }

    private func fetchSegmentFloors(_ client: IboxClient, segmentId: Int) async -> SnapResult {
        var out: [FloorItem] = []
        var page = 1
        for _ in 0..<40 {
            let path = "/public-service/markets?pageNo=\(page)&pageSize=50&segmentId=\(segmentId)&sortField=2&sortType=0&timeRange=0"
            let r = await client.get(path)
            let code = JSONX.code(r)
            let msg = JSONX.message(r)
            if code == 429 || code == 10002 || msg.contains("频繁") || msg.contains("限流") {
                return SnapResult(items: out, rateLimited: true)
            }
            if code == 401 || code == 403 {
                return SnapResult(items: [], error: "鉴权失败 c=\(code)")
            }
            if code != 0 && code != -1 && out.isEmpty && page == 1 && r["data"] == nil {
                return SnapResult(items: [], error: "c=\(code) \(String(msg.prefix(40)))")
            }
            let list = JSONX.dataDict(r)["list"] as? [[String: Any]] ?? []
            if list.isEmpty { break }
            for it in list {
                let gid = JSONX.int64Val(it["id"]) ?? 0
                if gid <= 0 { continue }
                out.append(FloorItem(gid: gid, name: JSONX.stringVal(it["name"]), floor: JSONX.doubleVal(it["floorPrice"]) ?? 0))
            }
            if JSONX.dataDict(r)["hasMore"] as? Bool != true { break }
            page += 1
        }
        return SnapResult(items: out)
    }

    private func tryBuyOne(_ client: IboxClient, payer: HfpayPayer?, uid: Int64, hit: FloorItem, qty: Int) async -> Int {
        let path = "/public-market-service/digital-collection-groups/\(hit.gid)/consignment-orders?pageNo=1&pageSize=20&sortField=1&sortType=1&uid=\(uid)"
        let book = await client.get(path)
        let code = JSONX.code(book)
        let msg = JSONX.message(book)
        if code == 429 || code == 10002 || msg.contains("频繁") {
            onLog("确认地板限流 · \(String(msg.prefix(40)))")
            return 0
        }
        let list = JSONX.dataDict(book)["list"] as? [[String: Any]] ?? []
        if list.isEmpty {
            onLog("确认地板 · 无挂单，跳过")
            return 0
        }
        let triggerCap = hit.floor * 1.02
        var bought = 0
        for it in list {
            if stop || bought >= qty { break }
            if it["isBelongUser"] as? Bool == true { continue }
            if (JSONX.int64Val(it["orderStatus"]) ?? -1) != 2 { continue }
            let price = JSONX.doubleVal(it["price"]) ?? 0
            if price <= 0 { continue }
            if price > triggerCap { continue }
            if let maxP = cfg.maxBuyPrice, maxP > 0, price > maxP { continue }
            var did = JSONX.int64Val(it["digitalCollectionId"]) ?? 0
            if did <= 0 { did = JSONX.int64Val(it["id"]) ?? 0 }
            if did <= 0, let dc = it["digitalCollection"] as? [String: Any] {
                did = JSONX.int64Val(dc["id"]) ?? 0
            }
            if did <= 0 { continue }
            onLog("下单中 \(hit.name) ¥\(fmt(price)) did=\(did)")
            let ord = await client.postJson("/order-create-service/purchase-consignment-orders", body: [
                "digitalCollectionId": did, "paymentPlatformCode": 30
            ])
            let oc = JSONX.code(ord)
            let om = JSONX.message(ord)
            switch oc {
            case 0:
                let oid = JSONX.stringVal(JSONX.dataDict(ord)["orderId"])
                onLog("下单成功 \(hit.name) ¥\(fmt(price)) \(oid)")
                await doPayment(client, payer: payer, oid: oid)
                bought += 1
            case 2_600_009:
                onLog("已被抢 did=\(did)")
            case 10_002:
                onLog("已锁定/频繁 did=\(did) · \(String(om.prefix(30)))")
            case 5_100_004:
                onLog("未付订单阻塞，停止本轮购买")
                break
            case 429:
                onLog("下单限流 · \(String(om.prefix(40)))")
                break
            default:
                onLog("下单失败 c=\(oc) \(String(om.prefix(50)))")
            }
            if bought < qty { try? await Task.sleep(nanoseconds: 350_000_000) }
        }
        if bought == 0 { onLog("本轮未成交（地板已变或被抢）") }
        return bought
    }

    private func doPayment(_ client: IboxClient, payer: HfpayPayer?, oid: String) async {
        if oid.isEmpty { return }
        if payer == nil {
            let pay = await client.get("/payment-service/cashiers/gain?orderUUId=\(oid)&paymentInitiatorType=0")
            let link = (JSONX.dataDict(pay)["link"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if !link.isEmpty { onLog("支付直达 \(link)") }
            else { onLog("请手动支付 \(oid)（未取到收银台链接）") }
            return
        }
        onLog("支付中...")
        let result = await payer!.pay(ibox: client, orderId: oid, payPassword: cfg.payPassword)
        if result.ok { onLog("自动支付成功! \(result.detail)"); return }
        if result.passwordError { onLog("密码错误! \(result.detail)"); return }
        let pay = await client.get("/payment-service/cashiers/gain?orderUUId=\(oid)&paymentInitiatorType=0")
        let link = (JSONX.dataDict(pay)["link"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if !link.isEmpty { onLog("支付失败:\(result.detail) 支付直达 \(link)") }
        else { onLog("支付失败:\(result.detail)") }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    static func loadSegments(_ client: IboxClient) async -> [SegmentInfo] {
        let r = await client.get("/public-service/markets/segments?timeRange=0&pageNo=1&pageSize=50")
        let list = JSONX.dataDict(r)["list"] as? [[String: Any]] ?? []
        return list.compactMap { it in
            let id = Int(JSONX.int64Val(it["id"]) ?? -999)
            let name = JSONX.stringVal(it["name"])
            if id == -999 || name.isEmpty { return nil }
            return SegmentInfo(id: id, name: name)
        }
    }
}
