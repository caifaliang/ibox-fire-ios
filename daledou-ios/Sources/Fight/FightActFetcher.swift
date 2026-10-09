import Foundation

struct FightActFetchResult {
    let act: String
    let errMsg: String
    let petUrl: String
}

enum FightActFetcher {
    private static let androidUA =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/120.0.0.0 Mobile Safari/537.36"

    /// petpk 常为 GBK/GB18030；纯 UTF-8 解码会得到空串 → 误报「空响应」
    static func decodeBody(_ data: Data) -> String {
        if data.isEmpty { return "" }
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            // 全是替换符则再试 GBK
            if !s.contains("\u{FFFD}") { return s }
        }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb18030)), !s.isEmpty {
            return s
        }
        let gbk = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
        )
        if let s = String(data: data, encoding: String.Encoding(rawValue: gbk)), !s.isEmpty {
            return s
        }
        return String(decoding: data, as: UTF8.self)
    }

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

    static func parseError(_ body: String, httpCode: Int, byteCount: Int) -> String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            if byteCount > 0 {
                return "解码失败 HTTP\(httpCode) \(byteCount)B"
            }
            return "空响应 HTTP\(httpCode)"
        }
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
        if t.contains("登录") || t.contains("登陆") { return "登录失效，请重新扫码" }
        return String(t.prefix(48))
    }

    /// 按候选依次请求；仅「系统繁忙」短退避重试同一 URL
    static func fetch(pageUrl: String, cookieHeader: String) async -> FightActFetchResult {
        let candidates = FightPetCandidates.urls(from: pageUrl)
        guard !candidates.isEmpty else {
            return FightActFetchResult(act: "", errMsg: "无法映射 petpk 动画接口", petUrl: "")
        }
        if cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FightActFetchResult(act: "", errMsg: "无 Cookie，请重新登录", petUrl: "")
        }
        seedHTTPCookies(from: cookieHeader)

        var lastMsg = ""
        for petUrl in candidates {
            for attempt in 0..<2 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000 * attempt))
                }
                do {
                    guard let url = URL(string: petUrl) else { continue }
                    var req = URLRequest(url: url)
                    req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                    req.setValue(androidUA, forHTTPHeaderField: "User-Agent")
                    req.setValue("https://fight.pet.qq.com/", forHTTPHeaderField: "Referer")
                    req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
                    req.setValue("*/*", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = 20
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    let body = decodeBody(data)
                    let act = extractReplayString(body)
                    if !act.isEmpty {
                        return FightActFetchResult(act: act, errMsg: "", petUrl: petUrl)
                    }
                    lastMsg = parseError(body, httpCode: code, byteCount: data.count)
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

    /// 写入共享 Cookie 存储，避免仅靠 Header 时部分跳转丢会话
    private static func seedHTTPCookies(from header: String) {
        let pairs = header
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("=") }
        let domains = [".qq.com", "fight.pet.qq.com", ".pet.qq.com"]
        for domain in domains {
            for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                var props: [HTTPCookiePropertyKey: Any] = [
                    .name: parts[0],
                    .value: parts[1],
                    .domain: domain,
                    .path: "/",
                    .secure: "TRUE",
                ]
                if let cookie = HTTPCookie(properties: props) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }
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
