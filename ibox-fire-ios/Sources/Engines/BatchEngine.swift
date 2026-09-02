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
        var holdFailLogged = false
        while hp <= 50 {
            let data = await client.get("/personal-center-service/users/digital-collection-groups/\(cfg.groupId)?pageSize=100&pageNo=\(hp)&lockStatus=0&uid=\(uid)")
            let code = JSONX.code(data)
            let msg = JSONX.message(data)
            if code != 0 {
                if !holdFailLogged {
                    onLog("获取持仓失败 c=\(code) \(msg.prefix(80))")
                    holdFailLogged = true
                }
                if hp == 1 {
                    let data2 = await client.get("/personal-center-service/users/digital-collection-groups/\(cfg.groupId)?pageSize=100&pageNo=1&lockStatus=0")
                    if JSONX.code(data2) == 0 {
                        holdings.append(contentsOf: JSONX.dataList(data2))
                        onLog("持仓(无uid路径) \(holdings.count) 件")
                        break
                    }
                }
                break
            }
            let list = JSONX.dataList(data)
            if list.isEmpty { break }
            holdings.append(contentsOf: list)
            if !(JSONX.dataDict(data)["hasMore"] as? Bool ?? false) { break }
            hp += 1
        }
        onLog("持仓共 \(holdings.count) 件")

        var listedIds = Set<String>()
        var lp = 1
        while lp <= 30 {
            let c = await client.get("/order-service/purchase-consignment-orders?pageNo=\(lp)&pageSize=50&orderStatus=2&orderType=2")
            if JSONX.code(c) != 0 { break }
            let list = JSONX.dataList(c)
            if list.isEmpty { break }
            for row in list {
                let pp = row["productPreview"] as? [String: Any] ?? [:]
                let tid = JSONX.stringVal(pp["tokenId"])
                if !tid.isEmpty { listedIds.insert(tid) }
            }
            if !(JSONX.dataDict(c)["hasMore"] as? Bool ?? false) { break }
            lp += 1
        }

        var pool = holdings.filter {
            let tid = JSONX.stringVal($0["tokenId"]).isEmpty ? JSONX.stringVal($0["token_id"]) : JSONX.stringVal($0["tokenId"])
            return !listedIds.contains(tid)
        }
        if cfg.safeMode { pool.shuffle() }
        onLog("本藏品待挂\(pool.count)件 全站寄售中\(listedIds.count)件 本批目标\(target)件")
        if pool.isEmpty {
            onLog(holdings.isEmpty ? "无可上架持仓（持仓接口返回0，请检查GID/Token）" : "无可上架持仓（可能已全部挂单）")
            return 0
        }

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
            let code = JSONX.code(r)
            let msg = JSONX.message(r)
            if code == 0 {
                await ConsignGate.shared.mark(uid: uid)
                onLog("OK \(String((item["name"] as? String ?? "").prefix(30)))")
                success += 1
            } else if JwtUtil.isAuthFail(code: code, message: msg) && code != 403 {
                await ConsignGate.shared.release(uid: uid)
                onLog("Token失效(挂单 c=\(code) \(msg.prefix(40)))，请到「我的」重新登录")
                return success
            } else if msg.contains("密码") {
                await ConsignGate.shared.release(uid: uid)
                onLog("密码错误! 停止"); return success
            } else if code == 4100003 {
                await ConsignGate.shared.release(uid: uid)
                onLog("未实名认证(4100003),停止"); return success
            } else if [2100001, 4100010, 4100007].contains(Int(code)) {
                await ConsignGate.shared.mark(uid: uid)
                onLog("冷却 \(msg.prefix(40))"); skip += 1
            } else if [429, 10002, -1].contains(Int(code)) {
                await ConsignGate.shared.mark(uid: uid)
                onLog("限流 \(msg.prefix(40)) (已计入硬间隔)"); fail += 1
            } else {
                await ConsignGate.shared.mark(uid: uid)
                onLog("失败 c=\(code) \(msg.prefix(40))"); fail += 1
            }
        }
        onLog("完成: \(success)/\(target) (失败\(fail) 跳过\(skip))")
        return success
    }

    private func doUnlist(_ client: IboxClient, target: Int) async -> Int {
        onLog("⚡本地模式 下架")
        let collData = await client.get("/public-service/digital-collection-groups/\(cfg.groupId)")
        let dataObj = JSONX.dataDict(collData)
        let coll = (dataObj["digitalCollectionGroup"] as? [String: Any]) ?? dataObj
        let collCover = (coll["coverPicUrl"] as? String) ?? ""
        let collName = ((coll["name"] as? String) ?? "").isEmpty ? cfg.collectionName : ((coll["name"] as? String) ?? "")

        onLog("匹配寄售中...")
        var toUnlist: [(Int64, String)] = []
        var page = 1, scanned = 0
        while page <= 40 && toUnlist.count < target {
            let c = await client.get("/order-service/purchase-consignment-orders?pageNo=\(page)&pageSize=50&orderStatus=2&orderType=2")
            if JSONX.code(c) != 0 { break }
            let list = JSONX.dataList(c)
            if list.isEmpty { break }
            for row in list {
                scanned += 1
                let pp = row["productPreview"] as? [String: Any] ?? [:]
                guard matchConsignRow(row, pp, collCover: collCover, collName: collName) else { continue }
                if let oid = JSONX.int64Val(row["id"]) ?? JSONX.int64Val(row["orderId"]) ?? JSONX.int64Val(row["consignOrderId"]) {
                    toUnlist.append((oid, String(collName.prefix(20))))
                    if toUnlist.count >= target { break }
                }
            }
            if !(JSONX.dataDict(c)["hasMore"] as? Bool ?? false) { break }
            page += 1
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        if toUnlist.isEmpty {
            onLog("匹配0件（已扫\(scanned)条，GID=\(cfg.groupId)）")
            return 0
        }
        onLog("匹配\(toUnlist.count)件 开始下架...")
        var success = 0
        for (oid, _) in toUnlist {
            if stop { break }
            var ok = false
            for attempt in 0..<3 {
                let r = await client.postJson("/order-service/consign-orders/\(oid)/cancel", body: [:])
                let code = JSONX.code(r)
                if code == 0 {
                    success += 1
                    onLog("OK #\(oid)")
                    ok = true
                    break
                }
                if code == -1 && attempt < 2 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                onLog("FAIL #\(oid) c=\(code) \(JSONX.message(r).prefix(30))")
                break
            }
            if !ok && cfg.safeMode { /* already logged */ }
            let delay: UInt64 = cfg.safeMode ? UInt64(Double.random(in: 5...8) * 1_000_000_000) : 500_000_000
            try? await Task.sleep(nanoseconds: delay)
        }
        onLog("下架完成 \(success)/\(toUnlist.count)")
        return success
    }

    private func extractGroupId(_ order: [String: Any], _ pp: [String: Any]) -> Int64? {
        for v in [
            order["digitalCollectionGroupId"], order["groupId"], order["albumId"],
            pp["digitalCollectionGroupId"], pp["groupId"], pp["albumId"], pp["digitalCollectionGroupID"]
        ] {
            if let n = JSONX.int64Val(v), n > 0 { return n }
        }
        return nil
    }

    private func matchConsignRow(_ order: [String: Any], _ pp: [String: Any], collCover: String, collName: String) -> Bool {
        if extractGroupId(order, pp) == cfg.groupId { return true }
        let rowCover = (pp["coverPicUrl"] as? String) ?? (order["coverPicUrl"] as? String) ?? ""
        if !collCover.isEmpty && !rowCover.isEmpty {
            if rowCover == collCover { return true }
            if coverKey(rowCover) == coverKey(collCover) && !coverKey(collCover).isEmpty { return true }
        }
        let rowName = ((pp["name"] as? String) ?? (order["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let want = collName.trimmingCharacters(in: .whitespaces)
        if !want.isEmpty && !rowName.isEmpty {
            if rowName == want { return true }
            let baseWant = want.components(separatedBy: "#").first?.trimmingCharacters(in: .whitespaces) ?? want
            let baseRow = rowName.components(separatedBy: "#").first?.trimmingCharacters(in: .whitespaces) ?? rowName
            if !baseWant.isEmpty && (baseRow == baseWant || baseRow.hasPrefix(baseWant) || baseWant.hasPrefix(baseRow)) { return true }
        }
        return false
    }

    private func coverKey(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespaces).components(separatedBy: "?").first?.components(separatedBy: "#").first ?? url
        if u.lowercased().hasPrefix("http://") { u = "https://" + u.dropFirst(7) }
        let file = u.components(separatedBy: "/").last?.lowercased() ?? ""
        return file.components(separatedBy: "!").first?
            .replacingOccurrences(of: #"_\d+x\d+(?=\.)"#, with: "", options: .regularExpression)
            .components(separatedBy: ".").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
