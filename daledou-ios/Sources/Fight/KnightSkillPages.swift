import Foundation

/// 真源：`KnightSkillPages.kt` + `KnightFightHtmlFormatter.resolveSkillIdLabel`。
/// 阵容：字段 6/7 → type=5 技能；字段 8 → type=3 武器（只打对应 URL，勿交叉误命中）。
/// 过程：按 kind 优先顺序试，再兜底另一类。
enum KnightSkillPages {
    enum Kind {
        case skill
        case weapon
        /// 过程解析：优先 kind 再兜底
        case autoSkill
        case autoWeapon
    }

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

    /// 技能 type=5 / 装备 type=3。
    static func skillViewUrls(id: Int, kind: Kind) -> [String] {
        let base =
            "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?zapp_uin=&sid=&channel=0&g_ut=1&cmd=view"
        let skill: [String]
        let weapon: [String]
        switch id {
        case 10...99:
            skill = ["\(base)&type=5&id=20\(id)"]
            weapon = ["\(base)&type=3&id=10\(id)"]
        case 100..<4000:
            skill = ["\(base)&type=5&id=2\(id)"]
            weapon = ["\(base)&type=3&id=1\(id)"]
        case 4000...:
            // 大 id：技能仍试 type=5，武器 type=3（对齐 Java resolveSkillIdLabel）
            skill = ["\(base)&type=5&id=2\(id)"]
            weapon = ["\(base)&type=3&id=1\(id)"]
        default:
            return []
        }
        switch kind {
        case .skill:
            return skill
        case .weapon:
            return weapon
        case .autoSkill:
            return skill + weapon
        case .autoWeapon:
            return weapon + skill
        }
    }

    /// 兼容旧签名。
    static func skillViewUrls(id: Int, preferWeapon: Bool = false) -> [String] {
        skillViewUrls(id: id, kind: preferWeapon ? .autoWeapon : .autoSkill)
    }

    static func parseSkillNameFromPage(_ page: String) -> String {
        if page.isEmpty { return "" }
        let decoded = decodeHtml(page)
        if decoded.contains("登陆校验") || decoded.contains("请先登录")
            || decoded.contains("系统繁忙") || decoded.contains("很抱歉")
        {
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
        if name.isEmpty || name.count > 40 { return "" }
        if name.range(of: #"^\d+$"#, options: .regularExpression) != nil { return "" }
        if name.contains("http") || name.contains("cmd=") { return "" }
        return name
    }

    static func resolveName(id: Int, cookie: String, kind: Kind) async -> String {
        for url in skillViewUrls(id: id, kind: kind) {
            let page = await cachedPage(url: url, cookie: cookie, retries: 3)
            let name = parseSkillNameFromPage(page)
            if !name.isEmpty { return name }
        }
        return "\(id)"
    }

    static func resolveName(id: Int, cookie: String, preferWeapon: Bool = false) async -> String {
        await resolveName(id: id, cookie: cookie, kind: preferWeapon ? .autoWeapon : .autoSkill)
    }

    /// Act 过程：`(idString, "weapon"|"skill")` → 中文名。
    static func resolveLabel(id: String, kind: String, cookie: String) async -> String {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        guard let v = Int(trimmed), v > 1 else { return trimmed }
        let k: Kind = kind.lowercased().contains("weapon") ? .autoWeapon : .autoSkill
        return await resolveName(id: v, cookie: cookie, kind: k)
    }

    /// 阵容栏：技能/武器分列，只打对应 type（避免武器 id 误打到技能页拿错名）。
    static func resolveRosterNames(
        skillIds: [Int],
        weaponIds: [Int],
        cookie: String,
        limit: Int = 16
    ) async -> [String] {
        var out: [String] = []
        for id in skillIds.prefix(limit) {
            out.append(await resolveName(id: id, cookie: cookie, kind: .skill))
        }
        let remain = max(0, limit - out.count)
        for id in weaponIds.prefix(remain) {
            out.append(await resolveName(id: id, cookie: cookie, kind: .weapon))
        }
        return out
    }

    static func resolveNames(ids: [Int], cookie: String, limit: Int = 16) async -> [String] {
        var out: [String] = []
        for id in ids.prefix(limit) {
            let skill = await resolveName(id: id, cookie: cookie, kind: .autoSkill)
            out.append(skill)
        }
        return out
    }

    private static func cachedPage(url: String, cookie: String, retries: Int) async -> String {
        lock.lock()
        if let hit = cache[url] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        guard let u = URL(string: url) else { return "" }
        var body = ""
        for attempt in 0..<max(1, retries) {
            body = await LedouCGI.get(url: u, cookie: cookie, referer: LedouCGI.phonepkBase).1
            let decoded = decodeHtml(body)
            if !decoded.isEmpty,
               !decoded.contains("系统繁忙"),
               !decoded.contains("很抱歉")
            {
                lock.lock()
                cache[url] = decoded
                lock.unlock()
                return decoded
            }
            if attempt + 1 < retries {
                try? await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
            }
        }
        let decoded = decodeHtml(body)
        lock.lock()
        cache[url] = decoded
        lock.unlock()
        return decoded
    }
}
