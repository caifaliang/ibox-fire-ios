import Foundation

struct BatchConfig {
    var token: String
    var groupId: Int64
    var collectionName: String = ""
    var action: String // list | unlist
    var price: Double = 0
    var consignPassword: String = ""
    var quantity: Int = 0
    var safeMode: Bool = true
    var proxy: String = ""
}

final class BatchEngine: @unchecked Sendable {
    private let cfg: BatchConfig
    private let onLog: (String) -> Void
    private var stop = false

    init(cfg: BatchConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async throws -> Int {
        if JwtUtil.isExpired(cfg.token) {
            onLog("Token已过期(JWT)，请到「我的」重新登录")
            throw NSError(domain: "batch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Token已过期"])
        }
        guard let uid = JwtUtil.uid(cfg.token) else { throw NSError(domain: "batch", code: 2, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"]) }
        let client = IboxClient(token: cfg.token, proxyLine: nil, connectMs: 10000, readMs: 15000, deviceIdMode: .stableMD5)
        let target = cfg.quantity <= 0 ? 99999 : cfg.quantity
        if cfg.action == "unlist" { return await doUnlist(client, target: target) }
        return await doList(client, uid: uid, target: target)
    }

    private func doList(_ client: IboxClient, uid: Int64, target: Int) async -> Int {
        if cfg.consignPassword.isEmpty { onLog("上架请填写寄售密码"); return 0 }
        if cfg.price <= 0 { onLog("请填写上架价格"); return 0 }
        onLog("⚡本地模式")
        onLog(cfg.safeMode ? "安全模式(固定\(ConsignGate.batchListGapS)s+随机顺序)" : "快速模式(固定\(ConsignGate.batchListGapS)s)")

        var holdings: [[String: Any]] = []
        var hp = 1
        while hp <= 50 {
            let data = await client.get("/personal-center-service/users/digital-collection-groups/\(cfg.groupId)?pageSize=100&pageNo=\(hp)&lockStatus=0&uid=\(uid)")
            if JSONX.code(data) != 0 {
                if hp == 1 {
                    let data2 = await client.get("/personal-center-service/users/digital-collection-groups/\(cfg.groupId)?pageSize=100&pageNo=1&lockStatus=0")
                    if JSONX.code(data2) == 0 { holdings.append(contentsOf: JSONX.dataList(data2)) }
                }
                break
            }
            let list = JSONX.dataList(data)
            if list.isEmpty { break }
            holdings.append(contentsOf: list)
            if !(JSONX.dataDict(data)["hasMore"] as? Bool ?? false) { break }
            hp += 1
        }

        var listedIds = Set<String>()
        var lp = 1
        while lp <= 30 {
            let c = await client.get("/order-service/purchase-consignment-orders?pageNo=\(lp)&pageSize=50&orderStatus=2&orderType=2")
            if JSONX.code(c) != 0 { break }
            let list = JSONX.dataList(c)
            if list.isEmpty { break }
            for row in list {
                if let tid = (row["productPreview"] as? [String: Any])?["tokenId"] as? String, !tid.isEmpty {
                    listedIds.insert(tid)
                }
            }
            if !(JSONX.dataDict(c)["hasMore"] as? Bool ?? false) { break }
            lp += 1
        }

        var pool = holdings.filter {
            let tid = ($0["tokenId"] as? String) ?? ""
            return !tid.isEmpty && !listedIds.contains(tid)
        }
        if cfg.safeMode { pool.shuffle() }
        onLog("本藏品待挂\(pool.count)件 全站寄售中\(listedIds.count)件 本批目标\(target)件")
        if pool.isEmpty { onLog("无可上架持仓"); return 0 }

        var success = 0, fail = 0, skip = 0
        for item in pool {
            if stop { onLog("收到停止信号"); break }
            if success >= target { break }
            let okWait = await ConsignGate.shared.wait(uid: uid, gapS: ConsignGate.batchListGapS, isStopped: { [weak self] in self?.stop ?? true }, addLog: onLog, floorS: ConsignGate.batchListGapS)
            if !okWait { break }
            let nm = String((item["name"] as? String ?? "").prefix(24))
            onLog("挂单 \(success + 1)/\(target) \(nm)...")
            let did = JSONX.int64Val(item["id"]) ?? 0
            let body: [String: Any] = [
                "digitalCollectionId": did,
                "price": cfg.price,
                "paymentPlatformCodes": [30],
                "consignPassword": cfg.consignPassword
            ]
            let r = await client.postJson("/order-create-service/consignment-orders", body: body)
            await ConsignGate.shared.mark(uid: uid)
            let code = JSONX.code(r)
            let msg = JSONX.message(r)
            if code == 0 {
                onLog("OK \(String((item["name"] as? String ?? "").prefix(30)))")
                success += 1
            } else if msg.contains("密码") {
                onLog("密码错误! 停止"); return success
            } else if [2100001, 4100010, 4100007].contains(Int(code)) {
                onLog("冷却 \(msg.prefix(40))"); skip += 1
            } else {
                onLog("失败 c=\(code) \(msg.prefix(40))"); fail += 1
            }
        }
        onLog("完成: \(success)/\(target) (失败\(fail) 跳过\(skip))")
        return success
    }

    private func doUnlist(_ client: IboxClient, target: Int) async -> Int {
        onLog("⚡本地模式 下架")
        onLog("匹配寄售中...")
        var toUnlist: [(Int64, String)] = []
        var page = 1
        while page <= 40 && toUnlist.count < target {
            let c = await client.get("/order-service/purchase-consignment-orders?pageNo=\(page)&pageSize=50&orderStatus=2&orderType=2")
            if JSONX.code(c) != 0 { break }
            let list = JSONX.dataList(c)
            if list.isEmpty { break }
            for row in list {
                let pp = row["productPreview"] as? [String: Any] ?? [:]
                let gid = JSONX.int64Val(pp["digitalCollectionGroupId"])
                    ?? JSONX.int64Val(pp["groupId"])
                    ?? JSONX.int64Val(row["digitalCollectionGroupId"])
                    ?? 0
                let name = (pp["name"] as? String) ?? ""
                let match = gid == cfg.groupId || (!cfg.collectionName.isEmpty && name.contains(cfg.collectionName))
                if match, let oid = JSONX.int64Val(row["id"]) ?? JSONX.int64Val(row["orderId"]) {
                    toUnlist.append((oid, String(name.prefix(20))))
                    if toUnlist.count >= target { break }
                }
            }
            if !(JSONX.dataDict(c)["hasMore"] as? Bool ?? false) { break }
            page += 1
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        if toUnlist.isEmpty { onLog("匹配0件"); return 0 }
        onLog("匹配\(toUnlist.count)件 开始下架...")
        var success = 0
        for (oid, _) in toUnlist {
            if stop { break }
            let r = await client.postJson("/order-service/consign-orders/\(oid)/cancel", body: [:])
            if JSONX.code(r) == 0 {
                success += 1
                onLog("OK #\(oid)")
            } else {
                onLog("FAIL #\(oid) c=\(JSONX.code(r))")
            }
            let delay: UInt64 = cfg.safeMode ? UInt64(Double.random(in: 5...8) * 1_000_000_000) : 500_000_000
            try? await Task.sleep(nanoseconds: delay)
        }
        onLog("下架完成 \(success)/\(toUnlist.count)")
        return success
    }
}
