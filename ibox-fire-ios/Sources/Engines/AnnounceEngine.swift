import Foundation

struct AnnounceConfig {
    var token: String
    var orderMode: String = "batch" // single | batch
    var maxSinglePrice: Double = 0
    var maxCount: Int = 1
    var durationS: Double = 3600
    var pollMs: UInt64 = 1000
    var s1SearchBase: String = "https://ai.iboxai.top/api"
}

/// 本地公告锁 — 对齐 Android AnnounceEngine（bulletin 轮询 + 本机直连锁单）。
final class AnnounceEngine: @unchecked Sendable {
    private let cfg: AnnounceConfig
    private let onLog: (String) -> Void
    private let api = ApiRepository()
    private var stop = false

    private let sailHost = "https://sail-api.ibox.art"
    private let bulletinOrigin = "https://announcement.ibox.art"
    private let listPath = "/public-service/announcements?pageNo=1&pageSize=10"
    private var seenNotice = Set<String>()
    private var lockedGids = Set<Int64>()
    private let minFloor = 11.0

    init(cfg: AnnounceConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async -> Int {
        guard bjOpenNow() else {
            onLog("仅北京时间 09:00–23:59 可用")
            return 0
        }
        guard let uid = JwtUtil.uid(cfg.token) else {
            onLog("JWT 无 userId")
            return 0
        }
        let client = IboxClient(token: cfg.token, proxyLine: nil, deviceIdMode: .stableMD5)
        let mode = cfg.orderMode.lowercased() == "single" ? "single" : "batch"
        let basePoll = max(400, min(5000, cfg.pollMs))

        onLog("⚡本地模式 mode=\(mode)（bulletin \(basePoll)ms · 本机直连）")
        if mode == "batch" {
            onLog("批量锁单 ≤¥\(cfg.maxSinglePrice) x\(max(1, cfg.maxCount))")
        }

        var bootstrapped = await seedSeenNotices()
        let deadline = Date().timeIntervalSince1970 + cfg.durationS
        var locked = 0
        var backoffMs: UInt64 = 0
        var okStreak = 0
        var pollCount = 0

        try? await Task.sleep(nanoseconds: basePoll * 1_000_000)
        onLog("开始轮询 bulletin 间隔 \(basePoll)ms")

        while !stop && Date().timeIntervalSince1970 < deadline {
            if !bjOpenNow() { onLog("已过开放时段，停止"); break }
            let waitMs = backoffMs > 0 ? max(backoffMs, basePoll) : basePoll
            if backoffMs > 0 { onLog("等待 \(waitMs)ms 后轮询…") }
            try? await Task.sleep(nanoseconds: waitMs * 1_000_000)

            do {
                onLog("请求 bulletin 列表…")
                let raw = try await bulletinGet(listPath)
                let code = JSONX.code(raw)
                let msg = JSONX.message(raw)
                if code == 403 || code == 429 || msg.contains("403") || msg.contains("429") {
                    okStreak = 0
                    backoffMs = backoffMs == 0 ? 1000 : min(backoffMs * 18 / 10, 30_000)
                    onLog("限流 code=\(code) 退避\(backoffMs)ms")
                } else if code != 0 {
                    okStreak = 0
                    onLog("bulletin 异常 code=\(code) \(msg.prefix(80))")
                } else {
                    okStreak += 1
                    if okStreak >= 3, backoffMs > 0 {
                        backoffMs = backoffMs / 2
                        if backoffMs < 500 { backoffMs = 0 }
                    }
                    let list = parseListNotices(raw)
                    pollCount += 1
                    let top = list.first
                    let topTip = top.map { "#\($0.0.prefix(12)) \($0.1.prefix(24))" } ?? "-"
                    onLog("轮询#\(pollCount) OK 已见\(seenNotice.count) 已锁\(locked) 最新\(topTip)")

                    if !bootstrapped {
                        list.forEach { seenNotice.insert($0.0) }
                        bootstrapped = true
                        onLog("首轮补同步 bulletin \(seenNotice.count) 条（跳过旧公告），继续监听…")
                        continue
                    }

                    var batchNew: [(String, String)] = []
                    for (nid, title) in list where !seenNotice.contains(nid) {
                        batchNew.append((nid, title))
                    }
                    for (nid, titleHint) in batchNew {
                        if stop { break }
                        guard seenNotice.insert(nid).inserted else { continue }
                        let got = await handleNewNotice(client: client, uid: uid, mode: mode, nid: nid, titleHint: titleHint)
                        locked += got
                    }
                }
            } catch {
                let tip = error.localizedDescription
                backoffMs = (tip.contains("429") || tip.contains("403")) ? (backoffMs == 0 ? 1000 : min(backoffMs * 18 / 10, 30_000)) : 1000
                onLog("轮询异常: \(tip.prefix(120)) · 退避 \(backoffMs)ms")
            }
        }
        onLog("公告锁定结束 成功锁 \(locked)")
        return locked
    }

    private func handleNewNotice(client: IboxClient, uid: Int64, mode: String, nid: String, titleHint: String) async -> Int {
        let t0 = Date()
        onLog("发现新公告 #\(nid.prefix(12)) \(titleHint.prefix(24)) · 拉详情…")
        var title = titleHint
        var content = ""
        if let detail = await fetchBulletinDetail(nid) {
            title = detail.0.isEmpty ? title : detail.0
            content = detail.1
        } else {
            onLog("新公告 #\(nid.prefix(12)) 拉详情失败，跳过")
            return 0
        }
        let targets = AnnounceParser.extractLockTargets(title: title, contentHtml: content)
        if targets.all.isEmpty {
            onLog("新公告 #\(nid.prefix(12)) → (无)")
            return 0
        }
        onLog("新公告 #\(nid.prefix(12)) → \(formatTargetTip(targets).prefix(80))")
        var locked = 0
        for name in targets.all {
            if stop { break }
            guard let gid = await resolveGid(name: name, client: client) else {
                onLog("未映射 \(name)")
                continue
            }
            guard lockedGids.insert(gid).inserted else { continue }
            let ok = await placeLock(client: client, uid: uid, gid: gid, mode: mode)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if ok.ok {
                locked += 1
                if ok.mode == "batch" {
                    onLog("批量锁定OK \(name) gid=\(gid) ≤¥\(cfg.maxSinglePrice) x\(cfg.maxCount) \(ms)ms")
                } else {
                    onLog("锁定OK \(name) gid=\(gid) ¥\(ok.price) \(ms)ms")
                }
            } else {
                lockedGids.remove(gid)
                onLog("跳过/失败 \(name) gid=\(gid) \(ok.reason)")
            }
        }
        return locked
    }

    private struct LockOutcome {
        var ok: Bool
        var mode: String
        var reason: String = ""
        var price: Double = 0
    }

    private func placeLock(client: IboxClient, uid: Int64, gid: Int64, mode: String) async -> LockOutcome {
        if mode == "single" {
            let path = "/public-market-service/digital-collection-groups/\(gid)/consignment-orders?pageNo=1&pageSize=20&sortField=1&sortType=1"
            let book = await client.get(path)
            if JSONX.code(book) != 0 { return LockOutcome(ok: false, mode: "single", reason: "book c=\(JSONX.code(book))") }
            let list = JSONX.dataList(book)
            if list.isEmpty { return LockOutcome(ok: false, mode: "single", reason: "empty_book") }
            for it in list {
                if !unlocked(it) { continue }
                let price = JSONX.doubleVal(it["price"]) ?? 0
                if price > 0, price < minFloor { continue }
                guard let did = JSONX.int64Val(it["digitalCollectionId"])
                    ?? JSONX.int64Val((it["digitalCollection"] as? [String: Any])?["id"]) else { continue }
                let r = await client.postJson("/order-create-service/purchase-consignment-orders", body: [
                    "digitalCollectionId": did, "paymentPlatformCode": 30
                ])
                let ok = JSONX.code(r) == 0
                return LockOutcome(ok: ok, mode: "single", reason: ok ? "" : JSONX.message(r), price: price)
            }
            return LockOutcome(ok: false, mode: "single", reason: "no_unlocked_on_page1")
        }
        let cap = cfg.maxSinglePrice
        let qty = max(1, cfg.maxCount)
        if cap <= 0 { return LockOutcome(ok: false, mode: "batch", reason: "need_max_single_price") }
        if cap < minFloor { return LockOutcome(ok: false, mode: "batch", reason: "below_min_floor") }
        let body: [String: Any] = [
            "digitalCollectionGroupId": gid,
            "maxCount": qty,
            "maxSinglePrice": cap,
            "paymentPlatformCode": 30,
            "level": -1
        ]
        let order = await client.postJson("/order-create-service/batch-purchase-consignment-orders?uid=\(uid)", body: body)
        let ok = JSONX.code(order) == 0
        return LockOutcome(ok: ok, mode: "batch", reason: ok ? "" : "c=\(JSONX.code(order)) \(JSONX.message(order).prefix(40))")
    }

    private func unlocked(_ it: [String: Any]) -> Bool {
        if it["isBelongUser"] as? Bool == true { return false }
        if let st = JSONX.int64Val(it["orderStatus"]), st != 2 { return false }
        if let ls = JSONX.int64Val((it["digitalCollection"] as? [String: Any])?["lockStatus"]), ls != 0 { return false }
        return true
    }

    private func resolveGid(name: String, client: IboxClient) async -> Int64? {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let path = "/public-service/search?keyword=\(raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw)&pageNo=1&pageSize=10&groupType=0"
        let data = await client.get(path)
        if JSONX.code(data) != 0 { return try? await api.searchCollections(raw).first?.id }
        let payload = JSONX.dataDict(data)
        let list = (payload["list"] as? [[String: Any]]) ?? (payload["records"] as? [[String: Any]]) ?? []
        for it in list {
            let n = ((it["name"] as? String) ?? (it["groupName"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            if n == raw || n.contains(raw) {
                if let g = JSONX.int64Val(it["id"]) ?? JSONX.int64Val(it["groupId"]) ?? JSONX.int64Val(it["digitalCollectionGroupId"]), g > 0 {
                    return g
                }
            }
        }
        return try? await api.searchCollections(raw).first?.id
    }

    private func seedSeenNotices() async -> Bool {
        for attempt in 1...3 {
            do {
                let seed = parseListNotices(try await bulletinGet(listPath))
                seed.forEach { seenNotice.insert($0.0) }
                onLog("已同步 bulletin \(seenNotice.count) 条，监听新公告…")
                return true
            } catch {
                if attempt < 3 {
                    onLog("同步 bulletin 失败(\(attempt)/3): \(error.localizedDescription.prefix(80))，重试…")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                } else {
                    onLog("同步 bulletin 失败: \(error.localizedDescription.prefix(80))（首轮成功列表将跳过旧公告）")
                }
            }
        }
        return false
    }

    private func parseListNotices(_ data: [String: Any]) -> [(String, String)] {
        guard JSONX.code(data) == 0 else { return [] }
        let list = JSONX.dataDict(data)["list"] as? [[String: Any]] ?? (data["data"] as? [[String: Any]]) ?? []
        return list.compactMap { a -> (String, String)? in
            let id = (a["uuid"] as? String) ?? "\(a["id"] ?? "")"
            guard !id.isEmpty, id != "null" else { return nil }
            return (id, a["title"] as? String ?? "")
        }
    }

    private func bulletinGet(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: sailHost + path) else { throw NSError(domain: "bulletin", code: 1) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("\(bulletinOrigin)/", forHTTPHeaderField: "Referer")
        req.setValue(bulletinOrigin, forHTTPHeaderField: "Origin")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: cfg)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 429 { return ["code": status, "message": "HTTP \(status)"] }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return ["code": -1, "message": "empty"] }
        guard var obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return ["code": status, "message": String(text.prefix(60))]
        }
        if obj["encryptKey"] != nil {
            let plain = try IboxCrypto.decryptResponse(text)
            obj = (try JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any]) ?? obj
        }
        return obj
    }

    private func fetchBulletinDetail(_ nid: String) async -> (String, String)? {
        guard let data = try? await bulletinGet("/public-service/announcements/uuid/\(nid)"),
              JSONX.code(data) == 0 else { return nil }
        let body = JSONX.dataDict(data)
        return (body["title"] as? String ?? "", body["content"] as? String ?? "")
    }

    private func formatTargetTip(_ t: AnnounceParser.LockTargets) -> String {
        var parts: [String] = []
        if !t.p1.isEmpty { parts.append("P1:\(t.p1.joined(separator: ","))") }
        if !t.p2.isEmpty { parts.append("P2:\(t.p2.joined(separator: ","))") }
        if !t.p3.isEmpty { parts.append("P3:\(t.p3.joined(separator: ","))") }
        return parts.isEmpty ? t.all.joined(separator: ",") : parts.joined(separator: " ")
    }

    private func bjOpenNow() -> Bool {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let h = cal.component(.hour, from: Date())
        return (9...23).contains(h)
    }
}
