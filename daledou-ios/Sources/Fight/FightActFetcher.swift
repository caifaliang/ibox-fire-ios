import Foundation

struct FightActFetchResult {
    let act: String
    let errMsg: String
    let petUrl: String
}

enum FightActFetcher {
    /// 从 petpk 响应提取 Act（对齐 `KnightFightHtmlFormatter.extractReplayString`）
    static func extractReplayString(_ jsonOrRaw: String) -> String {
        let s = jsonOrRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("&Build:") { return s }
        guard let i = s.range(of: "\"string\"") else {
            return s.contains("&Build:") ? s : ""
        }
        guard let colon = s[i.upperBound...].firstIndex(of: ":") else { return "" }
        guard let q1 = s[s.index(after: colon)...].firstIndex(of: "\"") else { return "" }
        var sb = ""
        var p = s.index(after: q1)
        while p < s.endIndex {
            let c = s[p]
            if c == "\\" {
                let nIdx = s.index(after: p)
                guard nIdx < s.endIndex else { break }
                let n = s[nIdx]
                switch n {
                case "n": sb.append("\n")
                case "r": sb.append("\r")
                case "t": sb.append("\t")
                case "\"", "\\", "/": sb.append(n)
                case "u":
                    let hexStart = s.index(after: nIdx)
                    if let hexEnd = s.index(hexStart, offsetBy: 4, limitedBy: s.endIndex),
                       let code = UInt32(s[hexStart..<hexEnd], radix: 16),
                       let scalar = UnicodeScalar(code) {
                        sb.append(Character(scalar))
                        p = hexEnd
                        continue
                    }
                    sb.append(n)
                default: sb.append(n)
                }
                p = s.index(after: nIdx)
                continue
            }
            if c == "\"" { break }
            sb.append(c)
            p = s.index(after: p)
        }
        return sb
    }

    static func parseError(_ body: String) -> String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "空响应" }
        if t.hasPrefix("{"),
           let data = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let msg = (obj["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let result = "\(obj["result"] ?? "")"
            if !msg.isEmpty { return msg }
            if !result.isEmpty { return "result=\(result)" }
        }
        if t.contains("系统繁忙") { return "系统繁忙" }
        if t.contains("回收") { return "录像已回收" }
        return String(t.prefix(40))
    }

    /// 按候选依次请求；仅「系统繁忙」短退避重试同一 URL
    static func fetch(pageUrl: String, cookieHeader: String) async -> FightActFetchResult {
        let candidates = FightPetCandidates.urls(from: pageUrl)
        guard !candidates.isEmpty else {
            return FightActFetchResult(act: "", errMsg: "无法映射 petpk 动画接口", petUrl: "")
        }
        var lastMsg = ""
        for petUrl in candidates {
            for attempt in 0..<2 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000 * attempt))
                }
                do {
                    var req = URLRequest(url: URL(string: petUrl)!)
                    req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                    req.setValue(
                        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent"
                    )
                    req.timeoutInterval = 20
                    let (data, _) = try await URLSession.shared.data(for: req)
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let act = extractReplayString(body)
                    if !act.isEmpty {
                        return FightActFetchResult(act: act, errMsg: "", petUrl: petUrl)
                    }
                    lastMsg = parseError(body)
                    let busy = lastMsg.contains("系统繁忙") || lastMsg.contains("稍后再试")
                    if !busy { break }
                } catch {
                    lastMsg = error.localizedDescription
                }
            }
        }
        return FightActFetchResult(
            act: "",
            errMsg: lastMsg.isEmpty ? "无战斗 Act 数据" : lastMsg,
            petUrl: candidates.last ?? ""
        )
    }

    static func replayId(from pageUrl: String) -> String {
        if let comps = URLComponents(string: pageUrl),
           let id = comps.queryItems?.first(where: { $0.name == "id" || $0.name == "repid" })?.value,
           !id.isEmpty {
            return id
        }
        return "benti_viewfight"
    }
}
