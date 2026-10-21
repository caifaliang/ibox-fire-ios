import Foundation

enum LedouCGI {
    static let phonepkBase = "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk"
    static let petpkBase = "https://fight.pet.qq.com/cgi-bin/petpk"

    static func isAllowedHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        return h.hasSuffix(".qq.com") || h == "qq.com"
            || h.hasSuffix(".tencent.com") || h == "tencent.com"
    }

    static func getPhonePk(cmd: String, extra: [String: String] = [:], cookie: String) async -> (Int, String) {
        var comps = URLComponents(string: phonepkBase)!
        var items: [URLQueryItem] = [
            .init(name: "zapp_uin", value: ""),
            .init(name: "sid", value: ""),
            .init(name: "channel", value: "0"),
            .init(name: "g_ut", value: "1"),
            .init(name: "cmd", value: cmd),
        ]
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) {
            items.append(.init(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else { return (-1, "") }
        return await get(url: url, cookie: cookie, referer: phonepkBase)
    }

    static func getPetPk(cmd: String, extra: [String: String] = [:], cookie: String) async -> (Int, String) {
        var comps = URLComponents(string: petpkBase)!
        var items = [URLQueryItem(name: "cmd", value: cmd)]
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) {
            items.append(.init(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else { return (-1, "") }
        return await get(url: url, cookie: cookie, referer: petpkBase)
    }

    static func get(url: URL, cookie: String, referer: String? = nil) async -> (Int, String) {
        guard isAllowedHost(url.host) else { return (-2, "拒绝非腾讯域名") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(LoginURLs.iphoneUA, forHTTPHeaderField: "User-Agent")
        // 明示接受中文页：phonepk/petpk 常无 charset，默认按 GBK/GB18030
        req.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let referer, !referer.isEmpty { req.setValue(referer, forHTTPHeaderField: "Referer") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let code = http?.statusCode ?? -1
            return (code, decodeBody(data, response: http))
        } catch {
            return (-3, error.localizedDescription)
        }
    }

    /// phonepk/petpk 常无 charset：UTF-8 失败时按 GB18030（含 GBK），禁止先落 Latin-1（会把中文打成乱码）。
    static func decodeBody(_ data: Data, response: HTTPURLResponse? = nil) -> String {
        if data.isEmpty { return "" }
        if let name = contentCharset(response),
           let enc = encoding(named: name),
           let s = String(data: data, encoding: enc)
        {
            return recoverIfMojibake(s)
        }
        if let s = String(data: data, encoding: .utf8) {
            return recoverIfMojibake(s)
        }
        if let s = String(data: data, encoding: gb18030) {
            return s
        }
        if let s = String(data: data, encoding: .isoLatin1) {
            return recoverIfMojibake(s)
        }
        return ""
    }

    /// 若已误按 Latin-1 读入 GBK 字节，尝试还原。
    static func recoverIfMojibake(_ body: String) -> String {
        if body.isEmpty { return body }
        if hasCJK(body) { return body }
        guard let latin = body.data(using: .isoLatin1),
              let recovered = String(data: latin, encoding: gb18030),
              hasCJK(recovered)
        else { return body }
        return recovered
    }

    private static var gb18030: String.Encoding {
        let raw = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: raw)
    }

    private static func hasCJK(_ s: String) -> Bool {
        s.range(of: #"[一-龥]{2,}"#, options: .regularExpression) != nil
    }

    private static func contentCharset(_ response: HTTPURLResponse?) -> String? {
        guard let raw = response?.value(forHTTPHeaderField: "Content-Type")?.lowercased() else { return nil }
        guard let range = raw.range(of: "charset=") else { return nil }
        var name = String(raw[range.upperBound...])
        if let semi = name.firstIndex(of: ";") { name = String(name[..<semi]) }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return name.isEmpty ? nil : name
    }

    private static func encoding(named name: String) -> String.Encoding? {
        switch name.lowercased().replacingOccurrences(of: "-", with: "") {
        case "utf8": return .utf8
        case "gbk", "gb2312", "gb18030", "gb180302000": return gb18030
        case "iso88591", "latin1", "windows1252": return .isoLatin1
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf == kCFStringEncodingInvalidId { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
    }

    /// 解析页面 href（相对/绝对 phonepk|petpk），仅腾讯域。
    static func getHref(_ href: String, cookie: String) async -> (Int, String) {
        var s = href.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        if s.hasPrefix("//") { s = "https:" + s }
        if !s.contains("://") {
            if s.contains("petpk") || s.hasPrefix("cgi-bin/petpk") {
                s = "https://fight.pet.qq.com/" + s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else if s.contains("?") {
                s = phonepkBase + (s.contains("cmd=") ? "?" + s.split(separator: "?").last! : "?" + s)
            } else {
                s = phonepkBase + "?" + s
            }
        }
        guard let url = URL(string: s) else { return (-1, "") }
        let ref = (url.host ?? "").contains("pet") ? petpkBase : phonepkBase
        return await get(url: url, cookie: cookie, referer: ref)
    }

    static func shortBody(_ body: String, code: Int) -> String {
        if code == -2 { return "拒绝非腾讯域名" }
        if code < 0 { return "网络失败(\(code))" }
        if body.contains("登陆校验失败") || body.contains("请先登录") { return "会话失效" }
        let plain = body
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.isEmpty { return "HTTP \(code) 空体" }
        return String(plain.prefix(80))
    }
}
