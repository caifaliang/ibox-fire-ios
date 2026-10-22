import Foundation

/**
 * 对齐 Android AnnounceGidResolver / announce_lock.resolve_name_to_gid。
 * 精确映射以 S1 藏品索引为主；S1 直连（不走用户代理）。
 */
final class AnnounceGidResolver: @unchecked Sendable {
    private let s1SearchBase: String
    private let iboxGet: (String) async -> [String: Any]
    private var cache: [String: Int64] = [:]
    private let lock = NSLock()

    init(s1SearchBase: String, iboxGet: @escaping (String) async -> [String: Any]) {
        self.s1SearchBase = s1SearchBase
        self.iboxGet = iboxGet
    }

    func resolve(_ name: String) async -> Int64? {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let hit = cached(raw) { return hit }
        let nn = AnnounceNameNorm.norm(raw)
        if !nn.isEmpty, let hit = cached(nn) { return hit }
        if let g = await resolveViaS1(raw) { return remember(raw, g) }
        if let g = await resolveViaSail(raw) { return remember(raw, g) }
        return nil
    }

    @discardableResult
    func remember(_ name: String, _ gid: Int64) -> Int64 {
        lock.lock()
        cache[name] = gid
        let nn = AnnounceNameNorm.norm(name)
        if !nn.isEmpty { cache[nn] = gid }
        lock.unlock()
        return gid
    }

    private func cached(_ key: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    private func resolveViaSail(_ name: String) async -> Int64? {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let path = "/public-service/search?keyword=\(enc)&pageNo=1&pageSize=10&groupType=0"
        let data = await iboxGet(path)
        guard JSONX.code(data) == 0 else { return nil }
        let payload = JSONX.dataDict(data)
        let items = (payload["list"] as? [[String: Any]])
            ?? (payload["records"] as? [[String: Any]])
            ?? (data["data"] as? [[String: Any]])
            ?? []
        let want = AnnounceNameNorm.norm(name)
        var exact: [(cs: Int, gid: Int64, len: Int)] = []
        for it in items {
            let n = ((it["name"] as? String) ?? (it["groupName"] as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard let g = JSONX.int64Val(it["id"])
                ?? JSONX.int64Val(it["groupId"])
                ?? JSONX.int64Val(it["digitalCollectionGroupId"]), g > 0 else { continue }
            if n == name || AnnounceNameNorm.norm(n) == want {
                let cs = Int(JSONX.int64Val(it["consignmentStatus"])
                    ?? JSONX.int64Val(it["consignment_status"]) ?? 0)
                exact.append((cs, g, n.count))
            }
        }
        if !exact.isEmpty {
            exact.sort { a, b in
                if a.cs != b.cs { return a.cs > b.cs }
                return a.len < b.len
            }
            return exact[0].gid
        }
        var cands: [Int64] = []
        for it in items {
            let n = ((it["name"] as? String) ?? (it["groupName"] as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard let g = JSONX.int64Val(it["id"]) ?? JSONX.int64Val(it["groupId"]), g > 0 else { continue }
            let nn = AnnounceNameNorm.norm(n)
            if n.contains(name) || (!want.isEmpty && nn.contains(want) && nn == want) {
                cands.append(g)
            }
        }
        return cands.count == 1 ? cands[0] : nil
    }

    private func resolveViaS1(_ name: String) async -> Int64? {
        let base = s1SearchBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { return nil }
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "\(base)/collections/search?q=\(enc)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("ibox-announce-lock/1", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: cfg)
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let items: [[String: Any]]
            if text.hasPrefix("[") {
                items = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]]) ?? []
            } else {
                let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
                items = (o["items"] as? [[String: Any]])
                    ?? (o["data"] as? [[String: Any]])
                    ?? (o["results"] as? [[String: Any]])
                    ?? []
            }
            let want = AnnounceNameNorm.norm(name)
            var exact: [(cs: Int, gid: Int64, len: Int)] = []
            for it in items {
                let n = (it["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { continue }
                if n != name && AnnounceNameNorm.norm(n) != want { continue }
                guard let gid = JSONX.int64Val(it["id"]), gid > 0 else { continue }
                let cs = Int(JSONX.int64Val(it["consignment_status"])
                    ?? JSONX.int64Val(it["consignmentStatus"]) ?? 0)
                exact.append((cs, gid, n.count))
            }
            guard !exact.isEmpty else { return nil }
            exact.sort { a, b in
                if a.cs != b.cs { return a.cs > b.cs }
                return a.len < b.len
            }
            return exact[0].gid
        } catch {
            return nil
        }
    }
}
