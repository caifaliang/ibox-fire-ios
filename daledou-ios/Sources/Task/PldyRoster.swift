import Foundation

/// 真源：`PldyRoster` — 批量斗友名册（好友/帮友/陌生人）。
enum PldyRoster {
    static let fid = "piliang_douyou"
    static let loadCounts = [10, 20, 50, 100, 200, 400, 800]

    struct Row: Hashable {
        var qq: String
        var name: String
        var level: Int
        var zhanli: Double
        var info: String = ""
        var isSq: Bool = false
        var isFight: Bool = false
    }

    static func loadLimit() -> Int {
        let idx = FeatureToggleStore.shared.getInt(fid, "setting_pldy_type", default: 0)
        let i = min(max(0, idx), loadCounts.count - 1)
        return loadCounts[i]
    }

    static func fetch(mode: String, cookie: String, onLog: @escaping (String) -> Void) async -> [Row] {
        let selfUin = SessionStore.shared.qq.filter(\.isNumber)
        switch mode {
        case "by":
            return await fetchBangYou(cookie: cookie, onLog: onLog)
        case "msr":
            return await fetchView(kindSub: ("1", "3"), cookie: cookie, selfUin: selfUin, onLog: onLog, fail: "陌生人列表失败")
        default:
            let friends = await fetchView(kindSub: ("1", "1"), cookie: cookie, selfUin: selfUin, onLog: onLog, fail: "好友列表失败")
            if mode == "stqb" {
                return await overlayXiaLv(friends, cookie: cookie)
            }
            return friends
        }
    }

    static func filter(
        _ raw: [Row],
        minDj: Int,
        maxDj: Int,
        maxZl: Int,
        onlyShenQuan: Bool,
        sortByLevel: Bool,
        limit: Int
    ) -> [Row] {
        let src = sortByLevel ? raw.sorted { $0.level < $1.level } : raw
        var out: [Row] = []
        for row in src {
            if row.isFight { continue }
            if row.level > 0 && (row.level < minDj || row.level > maxDj) { continue }
            if row.zhanli > Double(maxZl) { continue }
            if onlyShenQuan && !row.isSq { continue }
            out.append(row)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - fetchers

    private static func fetchView(
        kindSub: (String, String),
        cookie: String,
        selfUin: String,
        onLog: @escaping (String) -> Void,
        fail: String
    ) async -> [Row] {
        var extra = ["kind": kindSub.0, "sub": kindSub.1]
        if !selfUin.isEmpty { extra["selfuin"] = selfUin }
        let body = await retryPet(cmd: "view", extra: extra, cookie: cookie, onLog: onLog)
        guard let obj = jsonObject(body) else { return [] }
        if intField(obj, "result") != 0 {
            onLog(stringField(obj, "msg").ifBlankPldy(fail))
            return []
        }
        let info = arrayField(obj, "info")
        return await mergeRows(info, enableKey: "enable")
    }

    private static func fetchBangYou(cookie: String, onLog: @escaping (String) -> Void) async -> [Row] {
        let body = await retryPet(cmd: "viewmember", extra: [:], cookie: cookie, onLog: onLog)
        guard let obj = jsonObject(body) else { return [] }
        if intField(obj, "result") != 0 {
            onLog(stringField(obj, "msg").ifBlankPldy("帮友列表失败"))
            return []
        }
        let list = arrayField(obj, "list")
        return await mergeRows(list, enableKey: "fight", bangPos: true)
    }

    private static func mergeRows(
        _ items: [[String: Any]],
        enableKey: String,
        bangPos: Bool = false
    ) async -> [Row] {
        let known = await MainActor.run { Dictionary(uniqueKeysWithValues: ChaQuStore.shared.all().map { ($0.uin, $0) }) }
        var writes: [ChaQuStore.Entry] = []
        var out: [Row] = []
        for it in items {
            var uin = stringField(it, "uin")
            if uin.count < 5, let n = intField(it, "uin"), n > 0 { uin = "\(n)" }
            guard uin.count >= 5 else { continue }
            let name = stripHtml(stringField(it, "name"))
            var level = intField(it, "lilian") ?? 0
            if level <= 0 { level = intField(it, "level") ?? 0 }
            let flag = intField(it, enableKey) ?? -1
            let isSq = flag == 2
            let isFight = flag == 0
            let old = known[uin]
            let saved = ChaQuStore.Entry(
                uin: uin,
                name: name.isEmpty ? (old?.name ?? "") : name,
                level: level > 0 ? level : (old?.level ?? 0),
                value: old?.value ?? 0,
                saiqu: old?.saiqu ?? 0,
                lzn: old?.lzn ?? 0
            )
            writes.append(saved)
            var info = ""
            if bangPos {
                switch intField(it, "pos") ?? -1 {
                case 0: info = "众"
                case 1: info = "帮"
                case 2: info = "副"
                case 3: info = "护"
                case 4: info = "长"
                case 5: info = "堂"
                case 6: info = "精"
                default: break
                }
            }
            out.append(Row(
                qq: uin,
                name: saved.name.isEmpty ? name : saved.name,
                level: saved.level > 0 ? saved.level : level,
                zhanli: Double(saved.value),
                info: info,
                isSq: isSq,
                isFight: isFight
            ))
        }
        await MainActor.run { ChaQuStore.shared.upsertAll(writes) }
        return out
    }

    private static func overlayXiaLv(_ friends: [Row], cookie: String) async -> [Row] {
        let (_, html) = await LedouCGI.getPhonePk(cmd: "viewxialv", cookie: cookie)
        if html.isEmpty { return friends }
        var tagged: [String: String] = [:]
        let chunks = html
            .replacingOccurrences(of: "&amp;", with: "&")
            .components(separatedBy: CharacterSet(charactersIn: "\n"))
            .flatMap { $0.components(separatedBy: "<br />") }
            .flatMap { $0.components(separatedBy: "<br/>") }
            .flatMap { $0.components(separatedBy: "<br>") }
        for line in chunks {
            let tag: String
            if line.contains("情：<a href=") { tag = "情" }
            else if line.contains("师：<a href=") { tag = "师" }
            else if line.contains("徒：<a href=") { tag = "徒" }
            else if line.contains("拜：<a href=") { tag = "拜" }
            else { continue }
            guard let re = try? NSRegularExpression(pattern: #"B_UID=(\d{5,})"#),
                  let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: line)
            else { continue }
            tagged[String(line[r])] = tag
        }
        if tagged.isEmpty { return friends }
        return friends.compactMap { row in
            guard let t = tagged[row.qq] else { return nil }
            var copy = row
            copy.info = t
            return copy
        }
    }

    private static func retryPet(
        cmd: String, extra: [String: String], cookie: String, onLog: @escaping (String) -> Void
    ) async -> String {
        for n in 0..<4 {
            let (_, body) = await LedouCGI.getPetPk(cmd: cmd, extra: extra, cookie: cookie)
            if !body.contains("系统繁忙") { return body }
            onLog("系统繁忙，重试\(n + 1)")
            try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (n + 1)))
        }
        return ""
    }

    // MARK: - json helpers

    private static func jsonObject(_ raw: String) -> [String: Any]? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        if t.isEmpty || t.hasPrefix("<") { return nil }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(t[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func arrayField(_ obj: [String: Any], _ key: String) -> [[String: Any]] {
        (obj[key] as? [[String: Any]])
            ?? (obj[key] as? [Any])?.compactMap { $0 as? [String: Any] }
            ?? []
    }

    private static func stringField(_ obj: [String: Any], _ key: String) -> String {
        guard let v = obj[key] else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    private static func intField(_ obj: [String: Any], _ key: String) -> Int? {
        guard let v = obj[key] else { return nil }
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.filter { $0.isNumber || $0 == "-" }) }
        return nil
    }

    private static func stripHtml(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func ifBlankPldy(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
