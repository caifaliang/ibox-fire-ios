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
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let referer, !referer.isEmpty { req.setValue(referer, forHTTPHeaderField: "Referer") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            return (code, body)
        } catch {
            return (-3, error.localizedDescription)
        }
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
