import Foundation

/// 大乐斗腾讯 CGI 薄封装（对齐 Android LedouClient.getPhonePk，仅本机 Cookie）。
enum LedouCGI {
    static let phonepkBase = "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk"
    static let petpkBase = "https://fight.pet.qq.com/cgi-bin/petpk"

    static func isAllowedHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        if h.hasSuffix(".qq.com") || h == "qq.com" { return true }
        if h.hasSuffix(".tencent.com") { return true }
        return false
    }

    static func getPhonePk(
        cmd: String,
        extra: [String: String] = [:],
        cookie: String
    ) async -> (code: Int, body: String) {
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

    static func get(
        url: URL,
        cookie: String,
        referer: String? = nil
    ) async -> (code: Int, body: String) {
        guard isAllowedHost(url.host) else { return (-2, "拒绝非腾讯域名") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(LoginURLs.iphoneUA, forHTTPHeaderField: "User-Agent")
        req.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        if !cookie.isEmpty {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let referer, !referer.isEmpty {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }
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
}
