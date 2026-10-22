import Foundation

enum ProxyPool {
    static let extractN = 50
    static let fireCap = 50
    static let minAlive = 12
    /** 抢合抽代理默认条数（Android SYNTH_EXTRACT_N）；存活为 0 也可纯本机 */
    static let synthExtractN = 10
    /** APP 默认易代理订单（与 Android DEFAULT_EXTRACT_URL 一致） */
    static let defaultExtractURL =
        "http://api3.ydaili.cn/tools/MeasureApi.ashx?action=EAPI" +
        "&secret=2F21B68F8C7AE20EBDF57ADC90CD07F857D73FA8F2FD2C79" +
        "&number=10&orderId=SH20260819103610448&format=txt&type=1&split=3"

    private static let legacyOrder = "SH20260814213448412"
    private static let legacySecret = "65FD05455A5E3E7E1EFDAEDCA23C835F04472EAEA0853CE6"

    struct AliveResult {
        let proxies: [String]
        let detail: String
        let needMore: Bool
    }

    static func effectiveExtractUrl(_ custom: String) -> String {
        let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return defaultExtractURL }
        // 旧默认订单已耗尽，启动时自动迁移（对齐 Android）
        if t.contains(legacyOrder) || t.contains(legacySecret) { return defaultExtractURL }
        return t
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

    /** 从易代理错误文案解析剩余可提取数量，如「剩余数量为：2」 */
    static func parseRemainingQuota(_ text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"剩余数量为[：:]\s*(\d+)"#, options: []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text),
              let n = Int(text[r]), n > 0 else { return nil }
        return n
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

    private static func parseProxyLines(_ text: String, cap: Int) -> [String] {
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
                if out.count >= cap { break }
            }
        }
        return out
    }

    private static func isYdailiErrorBody(_ text: String) -> Bool {
        if text.hasPrefix("<") { return true }
        guard text.hasPrefix("{") else { return false }
        return text.contains("\"status\"") || text.contains("\"code\"") || text.contains("\"info\"")
    }

    /** 对齐 Android：按 want 抽取；余额不足时按「剩余数量」降级再抽一次 */
    static func fetchYdaili(_ apiUrl: String, want: Int = extractN) async throws -> [String] {
        var cap = max(1, want)
        let trimmed = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        for attempt in 0..<2 {
            let urlStr = bumpExtractCount(trimmed, want: cap)
            guard let url = URL(string: urlStr) else {
                throw NSError(domain: "Proxy", code: 1, userInfo: [NSLocalizedDescriptionKey: "易代理 URL 无效"])
            }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.httpMethod = "GET"
            let (data, _) = try await URLSession.shared.data(for: req)
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if isYdailiErrorBody(text) {
                if attempt == 0, let left = parseRemainingQuota(text), left < cap {
                    cap = left
                    continue
                }
                throw NSError(
                    domain: "Proxy",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "易代理返回异常: \(text.prefix(80))"]
                )
            }
            let list = parseProxyLines(text, cap: cap)
            if list.isEmpty {
                throw NSError(domain: "Proxy", code: 3, userInfo: [NSLocalizedDescriptionKey: "易代理未返回可用代理"])
            }
            return list
        }
        throw NSError(domain: "Proxy", code: 3, userInfo: [NSLocalizedDescriptionKey: "易代理未返回可用代理"])
    }

    private static let probeURLs = [
        "https://www.baidu.com/",
        "https://sail-api.ibox.art/public-service/markets?pageNo=1&pageSize=1&segmentId=-1&sortField=2&sortType=0&timeRange=0"
    ]

    private static func validateOne(_ proxyUrl: String) async -> Bool {
        guard ProxyPool.parseEndpoint(proxyUrl) != nil else { return false }
        let http = ProxyURLSession(proxyLine: proxyUrl, timeout: 3.5)
        for u in probeURLs {
            guard let url = URL(string: u) else { continue }
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                let (_, resp) = try await http.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode < 500 { return true }
            } catch { continue }
        }
        return false
    }

    static func filterAlive(_ raw: [String], cap: Int) async -> (proxies: [String], detail: String) {
        var alive: [String] = []
        let lock = NSLock()
        let chunk = raw.prefix(80)
        let workers = min(8, max(1, chunk.count))
        var idx = 0
        await withTaskGroup(of: String?.self) { group in
            for _ in 0..<workers {
                group.addTask {
                    while true {
                        let i: Int = {
                            lock.lock()
                            defer { lock.unlock() }
                            guard idx < chunk.count else { return -1 }
                            defer { idx += 1 }
                            return idx
                        }()
                        if i < 0 { break }
                        let px = Array(chunk)[i]
                        if await validateOne(px) { return px }
                    }
                    return nil
                }
            }
            for await r in group {
                guard let px = r else { continue }
                lock.lock()
                if alive.count < cap { alive.append(px) }
                let full = alive.count >= cap
                lock.unlock()
                if full { group.cancelAll() }
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

    /** 抢合专用：默认抽 10；余额不足则按剩余数量再抽；存活为 0 也可继续纯本机 */
    static func extractAliveForSynth(_ apiUrl: String, want: Int = synthExtractN) async -> AliveResult {
        let n = max(1, min(fireCap, want))
        do {
            let raw = try await fetchYdaili(apiUrl, want: n)
            let (alive, detail) = await filterAlive(raw, cap: max(1, raw.count))
            return AliveResult(
                proxies: alive,
                detail: "\(detail) → 抢合取\(alive.count)/提\(raw.count)(要\(n))",
                needMore: alive.isEmpty
            )
        } catch {
            return AliveResult(
                proxies: [],
                detail: "抽失败(\(error.localizedDescription.prefix(80)))",
                needMore: true
            )
        }
    }
}
