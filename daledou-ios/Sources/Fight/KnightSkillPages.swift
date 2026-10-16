import Foundation

/// 真源：`KnightSkillPages.kt` + `KnightFightReplayHtml.skillViewUrls`。
/// 侠士技能/装备页缓存；phonepk 偶发无 charset，按 UTF-8/GBK 容错。
enum KnightSkillPages {
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    static func decodeHtml(_ body: String) -> String {
        if body.isEmpty { return "" }
        if body.contains("系统繁忙") || body.contains("很抱歉") { return body }
        if body.range(of: #"[一-龥]{2,}"#, options: .regularExpression) != nil { return body }
        // LedouCGI 偶发按 ISO-8859-1 读入 GBK 字节；试转 GB18030
        guard let latin = body.data(using: .isoLatin1) else { return body }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let recovered = String(data: latin, encoding: String.Encoding(rawValue: gb18030)),
           recovered.range(of: #"[一-龥]{2,}"#, options: .regularExpression) != nil
        {
            return recovered
        }
        return body
    }

    /// 技能 type=5 / 装备 type=3，与参考 QXLXDataActivity.F 一致。
    static func skillViewUrls(id: Int) -> [String] {
        let base =
            "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=view"
        switch id {
        case 10...99:
            return ["\(base)&type=5&id=20\(id)", "\(base)&type=3&id=10\(id)"]
        case 100..<4000:
            return ["\(base)&type=5&id=2\(id)", "\(base)&type=3&id=1\(id)"]
        case 4000...:
            return ["\(base)&type=3&id=1\(id)"]
        default:
            return []
        }
    }

    static func parseSkillNameFromPage(_ page: String) -> String {
        if page.isEmpty { return "" }
        let first = page
            .components(separatedBy: "<br />").first?
            .components(separatedBy: "<br/>").first?
            .components(separatedBy: "<br>").first
            ?? page
        let last = first.components(separatedBy: "<p>").last?
            .components(separatedBy: "<P>").last
            ?? first
        return last
            .replacingOccurrences(of: "【", with: "")
            .replacingOccurrences(of: "】", with: "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolveName(id: Int, cookie: String) async -> String {
        for url in skillViewUrls(id: id) {
            let page = await cachedPage(url: url, cookie: cookie)
            let name = parseSkillNameFromPage(page)
            if !name.isEmpty { return name }
        }
        return "\(id)"
    }

    static func resolveNames(ids: [Int], cookie: String, limit: Int = 8) async -> [String] {
        var out: [String] = []
        for id in ids.prefix(limit) {
            out.append(await resolveName(id: id, cookie: cookie))
        }
        return out
    }

    private static func cachedPage(url: String, cookie: String) async -> String {
        lock.lock()
        if let hit = cache[url] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        guard let u = URL(string: url) else { return "" }
        let body = await LedouCGI.get(url: u, cookie: cookie, referer: LedouCGI.phonepkBase).1
        let decoded = decodeHtml(body)
        lock.lock()
        cache[url] = decoded
        lock.unlock()
        return decoded
    }
}
