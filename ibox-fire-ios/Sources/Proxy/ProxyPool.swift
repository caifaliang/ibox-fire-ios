import Foundation

enum ProxyPool {
    static let extractN = 50
    static let fireCap = 50
    static let minAlive = 12
    static let defaultExtractURL =
        "http://api3.ydaili.cn/tools/MeasureApi.ashx?action=EAPI" +
        "&secret=65FD05455A5E3E7E1EFDAEDCA23C835F04472EAEA0853CE6" +
        "&number=30&orderId=SH20260814213448412&format=txt&type=1&split=3"

    struct AliveResult {
        let proxies: [String]
        let detail: String
        let needMore: Bool
    }

    static func effectiveExtractUrl(_ custom: String) -> String {
        let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? defaultExtractURL : t
    }

    static func bumpExtractCount(_ apiUrl: String, want: Int = extractN) -> String {
        let lower = apiUrl.lowercased()
        for key in ["number=", "num="] {
            if let r = lower.range(of: key) {
                let start = apiUrl.index(apiUrl.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: r.upperBound))
                var end = start
                while end < apiUrl.endIndex, apiUrl[end].isNumber { end = apiUrl.index(after: end) }
                return String(apiUrl[..<start]) + "\(want)" + String(apiUrl[end...])
            }
        }
        let sep = apiUrl.contains("?") ? "&" : "?"
        return "\(apiUrl)\(sep)number=\(want)"
    }

    static func normalizeProxyUrl(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        if !(s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("socks")) {
            s = "http://\(s)"
        }
        if s.hasPrefix("socks") { return s }
        let body = s.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
        if body.contains("@") {
            return s.hasPrefix("https://") ? "https://\(body)" : "http://\(body)"
        }
        let parts = body.split(separator: ":").map(String.init)
        if parts.count >= 4 {
            let host = parts[0], port = parts[1], user = parts[2]
            let pass = parts[3...].joined(separator: ":")
            return "http://\(user):\(pass)@\(host):\(port)"
        }
        return s.hasPrefix("https://") ? "https://\(body)" : "http://\(body)"
    }

    struct ProxyEndpoint {
        let host: String
        let port: Int
        let user: String?
        let pass: String?
    }

    static func parseEndpoint(_ url: String) -> ProxyEndpoint? {
        let norm = normalizeProxyUrl(url)
        var rest = norm.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
        var user: String?
        var pass: String?
        if let at = rest.lastIndex(of: "@") {
            let ui = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
            if let c = ui.firstIndex(of: ":") {
                user = String(ui[..<c])
                pass = String(ui[ui.index(after: c)...])
            }
        }
        let hp = rest.split(separator: ":")
        guard hp.count >= 2, let port = Int(hp[1]), (1...65535).contains(port) else { return nil }
        return ProxyEndpoint(host: String(hp[0]), port: port, user: user, pass: pass)
    }

    static func fetchYdaili(_ apiUrl: String) async throws -> [String] {
        let urlStr = bumpExtractCount(apiUrl.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let url = URL(string: urlStr) else { throw NSError(domain: "Proxy", code: 1) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.hasPrefix("<") || (text.contains("\"code\"") && text.contains("{")) {
            throw NSError(domain: "Proxy", code: 2, userInfo: [NSLocalizedDescriptionKey: "易代理返回异常: \(text.prefix(80))"])
        }
        var seen = Set<String>()
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }
            let looks = l.contains(":") && !l.contains(" ") && (
                l.hasPrefix("http") || l.hasPrefix("socks") ||
                l.allSatisfy { $0.isLetter || $0.isNumber || ":.-@_".contains($0) }
            )
            guard looks else { continue }
            let px = normalizeProxyUrl(l.hasPrefix("http") || l.hasPrefix("socks") ? l : "http://\(l)")
            if seen.insert(px).inserted {
                out.append(px)
                if out.count >= extractN { break }
            }
        }
        if out.isEmpty { throw NSError(domain: "Proxy", code: 3, userInfo: [NSLocalizedDescriptionKey: "易代理未返回可用代理"]) }
        return out
    }

    private static let probeURLs = [
        "https://www.baidu.com/",
        "https://sail-api.ibox.art/public-service/markets?pageNo=1&pageSize=1&segmentId=-1&sortField=2&sortType=0&timeRange=0"
    ]

    private static func validateOne(_ proxyUrl: String) async -> Bool {
        guard let ep = parseEndpoint(proxyUrl) else { return false }
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": ep.host,
            "HTTPPort": ep.port,
            "HTTPSEnable": 1,
            "HTTPSProxy": ep.host,
            "HTTPSPort": ep.port
        ] as [AnyHashable: Any]
        if let u = ep.user, let p = ep.pass {
            // URLSession proxy auth is limited; still try without auth header for open proxies
            _ = u; _ = p
        }
        config.timeoutIntervalForRequest = 3.5
        let session = URLSession(configuration: config)
        for u in probeURLs {
            guard let url = URL(string: u) else { continue }
            do {
                let (_, resp) = try await session.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode < 500 { return true }
            } catch { continue }
        }
        return false
    }

    static func filterAlive(_ raw: [String], cap: Int) async -> (proxies: [String], detail: String) {
        var alive: [String] = []
        let lock = NSLock()
        await withTaskGroup(of: String?.self) { group in
            for px in raw.prefix(80) {
                group.addTask {
                    await validateOne(px) ? px : nil
                }
            }
            for await r in group {
                guard let px = r else { continue }
                lock.lock()
                if alive.count < cap { alive.append(px) }
                lock.unlock()
                if alive.count >= cap { group.cancelAll() }
            }
        }
        return (alive, "抽\(raw.count)活\(alive.count)")
    }

    static func extractAlivePool(_ apiUrl: String) async throws -> AliveResult {
        var seen = Set<String>()
        var all: [String] = []
        var parts: [String] = []
        for round in 1...5 {
            do {
                let raw = try await fetchYdaili(apiUrl)
                let (alive, detail) = await filterAlive(raw, cap: fireCap)
                parts.append("R\(round):\(detail)")
                for p in alive where seen.insert(p).inserted { all.append(p) }
                if all.count >= minAlive { break }
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                parts.append("R\(round):失败(\(error.localizedDescription.prefix(40)))")
                if all.isEmpty && round == 5 { throw error }
            }
        }
        let out = Array(all.prefix(fireCap))
        return AliveResult(
            proxies: out,
            detail: "\(parts.joined(separator: " + ")) → 合并活\(out.count)（提\(extractN)/够\(minAlive)停/开火≤\(fireCap)）",
            needMore: out.count < minAlive
        )
    }

    static func extractFewAlive(_ apiUrl: String, want: Int = 3) async throws -> AliveResult {
        let raw = try await fetchYdaili(apiUrl)
        let (alive, detail) = await filterAlive(raw, cap: max(1, want))
        return AliveResult(proxies: alive, detail: "\(detail) → 取\(alive.count)", needMore: alive.isEmpty)
    }
}
