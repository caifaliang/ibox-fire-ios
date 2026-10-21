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
        LedouCGI.recoverIfMojibake(body)
    }

    /// 技能 type=5 / 装备 type=3。`preferWeapon` 时先试装备页（Act 武器 id）。
    static func skillViewUrls(id: Int, preferWeapon: Bool = false) -> [String] {
        let base =
            "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=view"
        let skillFirst: [String]
        let weaponFirst: [String]
        switch id {
        case 10...99:
            skillFirst = ["\(base)&type=5&id=20\(id)", "\(base)&type=3&id=10\(id)"]
            weaponFirst = ["\(base)&type=3&id=10\(id)", "\(base)&type=5&id=20\(id)"]
        case 100..<4000:
            skillFirst = ["\(base)&type=5&id=2\(id)", "\(base)&type=3&id=1\(id)"]
            weaponFirst = ["\(base)&type=3&id=1\(id)", "\(base)&type=5&id=2\(id)"]
        case 4000...:
            skillFirst = ["\(base)&type=3&id=1\(id)"]
            weaponFirst = skillFirst
        default:
            return []
        }
        return preferWeapon ? weaponFirst : skillFirst
    }

    static func parseSkillNameFromPage(_ page: String) -> String {
        if page.isEmpty { return "" }
        let decoded = decodeHtml(page)
        if decoded.contains("登陆校验") || decoded.contains("请先登录") || decoded.contains("系统繁忙") {
            return ""
        }
        let first = decoded
            .components(separatedBy: "<br />").first?
            .components(separatedBy: "<br/>").first?
            .components(separatedBy: "<br>").first
            ?? decoded
        let last = first.components(separatedBy: "<p>").last?
            .components(separatedBy: "<P>").last
            ?? first
        let name = last
            .replacingOccurrences(of: "【", with: "")
            .replacingOccurrences(of: "】", with: "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 拒掉整页噪声 / 纯数字（解析失败）
        if name.isEmpty || name.count > 40 { return "" }
        if name.range(of: #"^\d+$"#, options: .regularExpression) != nil { return "" }
        if name.contains("http") || name.contains("cmd=") { return "" }
        return name
    }

    static func resolveName(id: Int, cookie: String, preferWeapon: Bool = false) async -> String {
        for url in skillViewUrls(id: id, preferWeapon: preferWeapon) {
            let page = await cachedPage(url: url, cookie: cookie)
            let name = parseSkillNameFromPage(page)
            if !name.isEmpty { return name }
        }
        return "\(id)"
    }

    static func resolveNames(ids: [Int], cookie: String, limit: Int = 16) async -> [String] {
        var out: [String] = []
        for id in ids.prefix(limit) {
            // 阵容栏技能/武器混排：两边都试
            let skill = await resolveName(id: id, cookie: cookie, preferWeapon: false)
            if skill != "\(id)" {
                out.append(skill)
                continue
            }
            out.append(await resolveName(id: id, cookie: cookie, preferWeapon: true))
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
