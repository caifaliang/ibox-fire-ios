import Foundation

/// 对齐 Android `WeaponSpeReplayCache`：开战前预取官方 `weapon_specialize` JSON，
/// 专精/武器面板需要 `src_weapons0`/`dst_weapons0` 形状，空 stub 会错乱。
enum WeaponSpeReplayCache {
    private static let lock = NSLock()
    private static var _weaponspe1 = ""
    private static var _weaponspe2 = ""
    private static var _lastOfficialJson = ""

    static var weaponspe1: String {
        lock.lock(); defer { lock.unlock() }
        return _weaponspe1
    }

    static var weaponspe2: String {
        lock.lock(); defer { lock.unlock() }
        return _weaponspe2
    }

    static var lastOfficialJson: String {
        lock.lock(); defer { lock.unlock() }
        return _lastOfficialJson
    }

    static func hasOfficialSpecialize() -> Bool {
        let j = lastOfficialJson
        return j.contains("src_weapons0") && j.contains("\"result\":\"0\"")
    }

    static func captureFromAct(_ act: String) {
        func field(_ name: String) -> String {
            guard let re = try? NSRegularExpression(pattern: "&\(NSRegularExpression.escapedPattern(for: name)):([^&]*)"),
                  let m = re.firstMatch(in: act, range: NSRange(act.startIndex..., in: act)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: act) else { return "" }
            return act[r].trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        }
        lock.lock()
        _weaponspe1 = field("weaponspe1")
        _weaponspe2 = field("weaponspe2")
        lock.unlock()
    }

    /// 后台预取；失败则 CGI 走 minimal stub。返回诊断串供日志。
    @discardableResult
    static func prefetchOfficial(replayId: String, cookieHeader: String) async -> String {
        if hasOfficialSpecialize() {
            return "cached \(lastOfficialJson.count)B"
        }
        var q = "cmd=weapon_specialize&op=11&replayType=0"
        let w1 = weaponspe1
        let w2 = weaponspe2
        if !w1.isEmpty, let e = w1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            q += "&weaponspe1=\(e)"
        }
        if !w2.isEmpty, let e = w2.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            q += "&weaponspe2=\(e)"
        }
        if !replayId.isEmpty, let e = replayId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            q += "&replayId=\(e)"
        }
        let cookieLen = cookieHeader.count
        guard cookieLen > 8 else { return "fail no-cookie" }
        if let body = await fetchAndCache(query: q, cookieHeader: cookieHeader) {
            return "ok \(body.count)B"
        }
        return "fail fetch cookie=\(cookieLen) w1=\(w1.count)"
    }

    @discardableResult
    static func fetchAndCache(query: String, cookieHeader: String) async -> String? {
        guard let url = URL(string: "https://fight.pet.qq.com/cgi-bin/petpk?\(query)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue("https://fight.pet.qq.com/", forHTTPHeaderField: "Referer")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code),
                  let body = String(data: data, encoding: .utf8), !body.isEmpty else { return nil }
            if body.contains("登陆校验失败") || body.contains("登录校验失败") { return nil }
            let enriched = enrich(body)
            lock.lock()
            _lastOfficialJson = enriched
            lock.unlock()
            return enriched
        } catch {
            return nil
        }
    }

    /// CGI 拦截时返回：优先官方缓存，否则 minimal 官方形状。
    static func stubResponse(query: String) -> String {
        if hasOfficialSpecialize() {
            return lastOfficialJson
        }
        func qp(_ name: String) -> String {
            guard let re = try? NSRegularExpression(pattern: "(?:^|&)\(NSRegularExpression.escapedPattern(for: name))=([^&]*)"),
                  let m = re.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: query) else { return "" }
            return query[r].removingPercentEncoding ?? String(query[r])
        }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let w1 = {
            let q = qp("weaponspe1")
            return q.isEmpty ? weaponspe1 : q
        }()
        let w2 = {
            let q = qp("weaponspe2")
            return q.isEmpty ? weaponspe2 : q
        }()
        return """
        {"result":"0","msg":"","weapons_num":"1","src_weapons0":[],"dst_weapons0":[],"weaponspe1":"\(esc(w1))","weaponspe2":"\(esc(w2))","weaponspe":"\(esc(w1))"}
        """
    }

    private static func enrich(_ official: String) -> String {
        func fill(_ json: String, key: String, fallback: String) -> String {
            guard !fallback.isEmpty else { return json }
            let esc = fallback
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            if let re = try? NSRegularExpression(pattern: "\"\(key)\"\\s*:\\s*\"\"(?=[,}])"),
               re.firstMatch(in: json, range: NSRange(json.startIndex..., in: json)) != nil {
                return re.stringByReplacingMatches(
                    in: json,
                    range: NSRange(json.startIndex..., in: json),
                    withTemplate: "\"\(key)\":\"\(esc)\""
                )
            }
            if !json.contains("\"\(key)\"") {
                if let insertAt = json.lastIndex(of: "}") {
                    return String(json[..<insertAt]) + ",\"\(key)\":\"\(esc)\"" + String(json[insertAt...])
                }
            }
            return json
        }
        var out = official
        out = fill(out, key: "weaponspe1", fallback: weaponspe1)
        out = fill(out, key: "weaponspe2", fallback: weaponspe2)
        out = fill(out, key: "weaponspe", fallback: weaponspe1)
        return out
    }
}
