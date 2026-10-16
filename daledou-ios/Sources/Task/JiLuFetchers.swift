import Foundation

/// 真源：`JiLuRankSyncFetcher` + `JiLuSnapshotFetcher`
enum JiLuFetchers {
    struct SyncResult {
        var ok: Bool
        var tip: String
        var rank: String = ""
        var day: Int = 0
        var year: Int = 0
        var month: Int = 0
    }

    struct SnapshotResult {
        var ok: Bool
        var tip: String
        var day: LiShiDay? = nil
        var giftNum: String? = nil
    }

    static func syncWuLin(cookie: String) async -> SyncResult {
        var bodies: [String] = []
        for type in ["0", "1", "2"] {
            bodies.append(await LedouCGI.getPetPk(
                cmd: "showwulinmsg", extra: ["type": type], cookie: cookie
            ).1)
            bodies.append(await LedouCGI.getPhonePk(
                cmd: "showwulinmsg", extra: ["type": type], cookie: cookie
            ).1)
        }
        if bodies.contains(where: { $0.contains("登陆校验失败") || $0.contains("登录校验失败") }) {
            return SyncResult(ok: false, tip: "Cookie 无效或已过期")
        }
        var lastFail = "未找到可识别的武林荣誉成绩"
        for body in Set(bodies) where !body.isEmpty {
            if let hit = parseWuLinJson(body) { return hit }
            if body.contains("<"), body.contains("武林") || body.contains("强") || body.contains("冠军") {
                let htmlRank = parseWuLinDesc(body).ifBlank(parseQunXiaRecent(body))
                if !htmlRank.isEmpty { return todayOk("已同步今日武林：\(htmlRank)", htmlRank) }
            }
            if let root = extractJsonObject(body) {
                let result = stringField(root, "result")
                if result != "0" && result != "" {
                    lastFail = stringField(root, "msg").ifBlank("武林成绩接口失败")
                } else if result == "" {
                    lastFail = "武林成绩解析失败"
                }
            }
        }
        return SyncResult(ok: false, tip: lastFail)
    }

    static func syncQunXia(cookie: String) async -> SyncResult {
        var bodies = [
            await LedouCGI.getPhonePk(cmd: "knightfight", cookie: cookie).1,
        ]
        if let u = URL(string: "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?zapp_uin=&B_UID=0&sid=&channel=0&g_ut=1&cmd=knightfight") {
            bodies.append(await LedouCGI.get(url: u, cookie: cookie).1)
        }
        if bodies.contains(where: { $0.contains("登陆校验失败") || $0.contains("登录校验失败") }) {
            return SyncResult(ok: false, tip: "Cookie 无效或已过期")
        }
        var rank = ""
        var html = ""
        for body in bodies where !body.isEmpty {
            html = body
            rank = parseQunXiaRecent(body)
            if !rank.isEmpty { break }
        }
        if rank == "冠军", !html.isEmpty {
            let feeds = await LedouCGI.getPhonePk(
                cmd: "knightfight", extra: ["op": "view_feeds"], cookie: cookie
            ).1
            if feeds.contains("总冠军赛决赛战胜") { rank = "总冠" }
            else if feeds.contains("总冠军赛决赛惜败") { rank = "总亚" }
        }
        if rank.isEmpty { return SyncResult(ok: false, tip: "未找到侠士最近参赛成绩") }
        return todayOk("已同步今日侠士：\(rank)", rank)
    }

    static func fetchTodayHistory(cookie: String, uin: String) async -> SnapshotResult {
        if uin.isEmpty { return SnapshotResult(ok: false, tip: "未登陆 QQ，无法拉取") }
        let visit = await LedouCGI.getPetPk(
            cmd: "visit", extra: ["puin": uin, "kind": "1"], cookie: cookie
        ).1
        let attr = await LedouCGI.getPetPk(
            cmd: "viewattr", extra: ["puin": uin, "kind": "1"], cookie: cookie
        ).1
        if visit.contains("登陆校验失败") || attr.contains("登陆校验失败")
            || visit.contains("登录校验失败") || attr.contains("登录校验失败")
        {
            return SnapshotResult(ok: false, tip: "Cookie 无效或已过期")
        }
        let visitObj = extractJsonObject(visit.replacingOccurrences(of: "\\速度高于对手时", with: "速度高于对手时"))
        let attrObj = extractJsonObject(attr)
        if visitObj == nil && attrObj == nil {
            return SnapshotResult(ok: false, tip: "visit 解析失败")
        }
        let base = visitObj?["baseinfo"] as? [String: Any]
        let name = firstNonEmpty(
            stringField(attrObj, "nickname"),
            stringField(base, "name"),
            "?"
        )
        let levelNum = intField(attrObj, "level").flatMap { $0 > 0 ? $0 : nil }
            ?? intField(base, "lilian")
            ?? 0
        let combat = doubleField(attrObj, "combat").flatMap { $0 > 0 ? $0 : nil }
            ?? doubleField(base, "combat")
            ?? 0
        let zhanLi = trimNum(combat / 10.0)
        let bangPai = stringField(base, "factionname")
        let exp = firstNonEmpty(stringField(attrObj, "exp"), stringField(base, "exp"), "")
        let day = chinaDay()
        return SnapshotResult(
            ok: true,
            tip: "已记录今日：\(name)",
            day: LiShiDay(
                day: day.day, name: name, bangPai: bangPai,
                dengJi: "\(levelNum)", zhanLi: zhanLi, exp: exp
            )
        )
    }

    static func fetchShangHuiGift(cookie: String) async -> SnapshotResult {
        let body = await LedouCGI.getPetPk(
            cmd: "fac_corp", extra: ["page": "1", "op": "0"], cookie: cookie
        ).1
        if body.contains("登陆校验失败") || body.contains("登录校验失败") {
            return SnapshotResult(ok: false, tip: "Cookie 无效或已过期")
        }
        guard let obj = extractJsonObject(body) else {
            return SnapshotResult(ok: false, tip: "商会接口解析失败")
        }
        let gift = stringField(obj, "totalGiftNum")
        if gift.isEmpty && intField(obj, "result") != 0 {
            return SnapshotResult(
                ok: false,
                tip: stringField(obj, "msg").ifBlank("商会无数据（可能未入帮）")
            )
        }
        return SnapshotResult(ok: true, tip: "今日全帮礼包：\(gift.ifBlank("0"))", giftNum: gift.ifBlank("0"))
    }

    // MARK: - parsers

    private static func parseWuLinJson(_ body: String) -> SyncResult? {
        guard let root = extractJsonObject(body) else { return nil }
        let result = stringField(root, "result").ifBlank("\(intField(root, "result") ?? -1)")
        if result != "0" { return nil }
        let arr = (root["info"] as? [Any]) ?? (root["Info"] as? [Any]) ?? []
        if arr.isEmpty { return nil }
        let cal = chinaDay()
        for el in arr {
            guard let o = el as? [String: Any] else { continue }
            let desc = ["desc", "msg", "text", "content"].map { stringField(o, $0) }.joined()
            let time = stringField(o, "time")
            if !time.isEmpty && !isWuLinTimeOk(time) { continue }
            let rank = parseWuLinDesc(desc).ifBlank(parseQunXiaRecent(desc))
            if rank.isEmpty { continue }
            let (y, m, d) = dayFromTime(time, fallback: cal)
            return SyncResult(ok: true, tip: "已同步武林：\(rank)", rank: rank, day: d, year: y, month: m)
        }
        return nil
    }

    static func parseWuLinDesc(_ desc: String) -> String {
        let t = desc.replacingOccurrences(of: "！", with: "!")
            .replacingOccurrences(of: "，", with: ",")
        if t.contains("总冠军赛决赛战胜") || t.contains("总冠军赛第3轮战胜") { return "总冠" }
        if t.contains("总冠军赛决赛中惜败") || t.contains("总冠军赛决赛惜败")
            || t.contains("总冠军赛第3轮惜败") { return "总亚" }
        if t.contains("总冠军赛第1轮") { return "冠军" }
        if t.contains("总冠军赛第2轮") {
            let tail = t.components(separatedBy: "总冠军赛第2轮").last ?? ""
            if tail.contains("四等武林宝箱") || tail.contains("三等武林宝箱") || tail.contains("战胜") {
                return "冠军"
            }
            if tail.contains("惜败") || tail.contains("二等武林宝箱") || tail.contains("一等武林宝箱") {
                return "亚军"
            }
        }
        if t.contains("决战之巅")
            && (t.contains("战胜") || t.contains("四等武林宝箱") || t.contains("三等武林宝箱"))
        {
            return "冠军"
        }
        if t.contains("决战之巅")
            && (t.contains("惜败") || t.contains("二等武林宝箱") || t.contains("一等武林宝箱"))
        {
            return "亚军"
        }
        if let n = rankFromNQiang(t) { return n }
        if t.contains("四等武林宝箱") || t.contains("三等武林宝箱") { return "冠军" }
        if t.contains("二等武林宝箱") { return "亚军" }
        if t.contains("一等武林宝箱") { return "四强" }
        if t.contains("冠军") && !t.contains("总冠军") { return "冠军" }
        if t.contains("亚军") { return "亚军" }
        return ""
    }

    static func parseQunXiaRecent(_ html: String) -> String {
        let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if let m = plain.range(of: #"最近参赛成绩\s*[:：]\s*([^\s<]+)"#, options: .regularExpression) {
            let token = String(plain[m]).replacingOccurrences(
                of: #"最近参赛成绩\s*[:：]\s*"#, with: "", options: .regularExpression
            )
            if let r = rankFromToken(token) { return r }
        }
        let pairs: [(String, String)] = [
            ("最近参赛成绩：冠军", "冠军"), ("最近参赛成绩:冠军", "冠军"),
            ("最近参赛成绩：亚军", "亚军"), ("最近参赛成绩:亚军", "亚军"),
            ("最近参赛成绩：2048强", "2048"), ("最近参赛成绩：1024强", "1024"),
            ("最近参赛成绩：512强", "512"), ("最近参赛成绩：256强", "256"),
            ("最近参赛成绩：128强", "128"), ("最近参赛成绩：64强", "64强"),
            ("最近参赛成绩：32强", "32强"), ("最近参赛成绩：16强", "16强"),
            ("最近参赛成绩：8强", "八强"), ("最近参赛成绩：八强", "八强"),
            ("最近参赛成绩：4强", "四强"), ("最近参赛成绩：四强", "四强"),
        ]
        for (needle, rank) in pairs {
            if html.contains(needle) || plain.contains(needle) { return rank }
        }
        return ""
    }

    private static func rankFromNQiang(_ text: String) -> String? {
        let re = try? NSRegularExpression(pattern: #"(?:止步|你在)?\s*([0-9０-９]+)\s*强"#)
        let ns = text as NSString
        var nums: [Int] = []
        re?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 2 else { return }
            let raw = ns.substring(with: m.range(at: 1))
            let nStr = raw.map { c -> Character in
                if c >= "０" && c <= "９" {
                    return Character(UnicodeScalar(UInt32(c.unicodeScalars.first!.value - 0xFF10 + 0x30))!)
                }
                return c
            }
            if let n = Int(String(nStr)), [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048].contains(n) {
                nums.append(n)
            }
        }
        guard !nums.isEmpty else { return nil }
        return nQiangLabel(nums.max() ?? nums[0])
    }

    private static func nQiangLabel(_ n: Int) -> String? {
        switch n {
        case 4: return "四强"
        case 8: return "八强"
        case 16: return "16强"
        case 32: return "32强"
        case 64: return "64强"
        case 128: return "128"
        case 256: return "256"
        case 512: return "512"
        case 1024: return "1024"
        case 2048: return "2048"
        default: return nil
        }
    }

    private static func rankFromToken(_ token: String) -> String? {
        let t = token.trimmingCharacters(in: .whitespaces)
        if t.contains("总冠") { return "总冠" }
        if t.contains("总亚") { return "总亚" }
        if t.contains("冠军") { return "冠军" }
        if t.contains("亚军") { return "亚军" }
        if t.contains("四强") { return "四强" }
        if t.contains("八强") { return "八强" }
        if let r = rankFromNQiang(t) { return r }
        if let n = Int(t.filter(\.isNumber)) { return nQiangLabel(n) }
        return nil
    }

    private static func todayOk(_ tip: String, _ rank: String) -> SyncResult {
        let d = chinaDay()
        return SyncResult(ok: true, tip: tip, rank: rank, day: d.day, year: d.year, month: d.month)
    }

    private static func chinaDay() -> (year: Int, month: Int, day: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        return (
            cal.component(.year, from: now),
            cal.component(.month, from: now),
            cal.component(.day, from: now)
        )
    }

    private static func isWuLinTimeOk(_ time: String) -> Bool {
        if time.isEmpty { return true }
        let nums = time.split { !$0.isNumber }.compactMap { Int($0) }.filter { $0 > 0 }
        switch nums.count {
        case 2: return (1...12).contains(nums[0]) && (1...31).contains(nums[1])
        case 3: return (1...12).contains(nums[1]) && (1...31).contains(nums[2])
        default: return time.contains("月") && time.contains("日")
        }
    }

    private static func dayFromTime(
        _ time: String, fallback: (year: Int, month: Int, day: Int)
    ) -> (Int, Int, Int) {
        let nums = time.split { !$0.isNumber }.compactMap { Int($0) }.filter { $0 > 0 }
        switch nums.count {
        case 2: return (fallback.year, nums[0], nums[1])
        case 3: return (nums[0] < 100 ? 2000 + nums[0] : nums[0], nums[1], nums[2])
        default: return (fallback.year, fallback.month, fallback.day)
        }
    }

    private static func extractJsonObject(_ raw: String) -> [String: Any]? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        if t.isEmpty || t.hasPrefix("<") { return nil }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") , start < end else {
            return nil
        }
        let slice = String(t[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func stringField(_ obj: [String: Any]?, _ key: String) -> String {
        guard let v = obj?[key] else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    private static func intField(_ obj: [String: Any]?, _ key: String) -> Int? {
        guard let v = obj?[key] else { return nil }
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.filter { $0.isNumber || $0 == "-" }) }
        return nil
    }

    private static func doubleField(_ obj: [String: Any]?, _ key: String) -> Double? {
        guard let v = obj?[key] else { return nil }
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        values.first(where: { !$0.isEmpty }) ?? ""
    }

    private static func trimNum(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v == Double(Int(v)) { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
