import Foundation

/// 真源：`MoreExtraActions.loadBeiBaoCatalog` / `useBeiBaoItem`
enum BeiBaoCatalog {
    struct Item: Identifiable, Hashable {
        var id: String
        var name: String
        var desc: String
        var num: Int
        var storage: String
        var canuse: String = ""
        var pic: String = ""

        var imageURL: URL? {
            if id.hasPrefix("-") { return nil }
            let key = (pic.isEmpty ? id : pic).filter(\.isNumber)
            guard !key.isEmpty else { return nil }
            return URL(string: "https://fightimg.pet.qq.com/img/\(key).png")
        }
    }

    /// storage：0全部；1药水 2属性 3强化 6星石 4魂珠 5锦囊 7荣誉 10其他
    static let tabs: [(String, String)] = [
        ("全部", "0"), ("药水", "1"), ("属性", "2"), ("强化", "3"),
        ("星石", "6"), ("魂珠", "4"), ("锦囊", "5"), ("荣誉", "7"), ("其他", "10"),
    ]

    private static let storageOk: Set<String> = ["1", "2", "3", "4", "5", "6", "7", "10"]

    static func load(cookie: String, onLog: @escaping (String) -> Void) async -> [Item] {
        let t0 = Date()
        var uin = LoginURLs.extractQq(cookie) ?? SessionStore.shared.qq.filter(\.isNumber)
        var out: [Item] = []

        func upsert(_ item: Item) {
            if item.id.isEmpty && item.name.isEmpty { return }
            let key = item.id.isEmpty ? item.name : item.id
            if let i = out.firstIndex(where: { $0.id == key || ($0.id.isEmpty && $0.name == item.name) }) {
                out.remove(at: i)
            }
            if item.num > 0 || item.id.hasPrefix("-") {
                var copy = item
                if copy.id.isEmpty { copy.id = key }
                out.append(copy)
            }
        }

        if !uin.isEmpty {
            let urlStr =
                "https://fight.pet.qq.com/cgi-bin/petpk?cmd=view&kind=0&sub=2&type=4&selfuin=\(uin)"
            if let url = URL(string: urlStr) {
                let (_, body) = await LedouCGI.get(url: url, cookie: cookie, referer: LedouCGI.petpkBase)
                if let root = jsonObject(body), resultOk(root) || root["bag"] != nil {
                    parseBagJson(root, upsert: upsert)
                } else {
                    let tip = (CombatLog.jsonField(body, "msg") ?? "")
                        .ifBlankBag(CombatLog.fromBody(body))
                        .ifBlankBag("view 空")
                    onLog("材料：\(tip)")
                }
            }
        }

        if out.isEmpty {
            let storeTypes: [(String, String)] = [
                ("", "10"), ("1", "1"), ("2", "2"), ("3", "3"),
                ("4", "4"), ("5", "5"), ("6", "6"), ("7", "7"),
            ]
            for (stype, storage) in storeTypes {
                var page = 1
                while page <= 4 {
                    var extra: [String: String] = [:]
                    if !stype.isEmpty { extra["store_type"] = stype }
                    if page > 1 { extra["page"] = "\(page)" }
                    let (_, html) = await LedouCGI.getPhonePk(cmd: "store", extra: extra, cookie: cookie)
                    if html.isEmpty || html.contains("登陆校验失败") || html.contains("请先登录")
                        || html.contains("登录校验失败")
                    {
                        break
                    }
                    let items = scrapePhoneBagHtml(html, defaultStorage: storage)
                    if items.isEmpty { break }
                    items.forEach(upsert)
                    let h = html.replacingOccurrences(of: "&amp;", with: "&")
                    if !h.contains("下一页") && !h.contains("page=\(page + 1)") { break }
                    page += 1
                }
            }
        }

        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if out.isEmpty {
            onLog(uin.isEmpty ? "无QQ，请重新一键登陆" : "背包为空（uin=\(uin)） \(ms)ms")
        } else {
            onLog("已加载 \(out.count) 件（uin=\(uin)） \(ms)ms")
        }
        return out
    }

    static func use(item: Item, cookie: String, onLog: @escaping (String) -> Void) async -> (String, Int?) {
        if item.canuse != "1" {
            onLog("该道具不支持使用")
            return ("该道具不支持使用", nil)
        }
        let uin = LoginURLs.extractQq(cookie) ?? SessionStore.shared.qq.filter(\.isNumber)
        if uin.isEmpty { return ("无QQ", nil) }
        let (_, body) = await LedouCGI.getPetPk(
            cmd: "use", extra: ["selfuin": uin, "id": item.id], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: 80_000_000)
        let msg = CombatLog.fromBody(body).ifBlankBag("已使用")
        onLog(msg)
        var delta: Int?
        if let root = jsonObject(body),
           let arr = root["goods_dt"] as? [[String: Any]]
        {
            for o in arr {
                if stringField(o, "id") == item.id {
                    delta = intField(o, "num")
                    break
                }
            }
        }
        return (msg, delta)
    }

    // MARK: - parse

    private static func parseBagJson(_ root: [String: Any], upsert: (Item) -> Void) {
        let bag = (root["bag"] as? [[String: Any]])
            ?? (root["bag"] as? [Any])?.compactMap { $0 as? [String: Any] }
            ?? []
        for o in bag {
            let id = stringField(o, "id")
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { continue }
            let name = stringField(o, "name").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let num = intField(o, "num") ?? 0
            guard num > 0 else { continue }
            let stRaw = stringField(o, "storage")
            let st = storageOk.contains(stRaw) ? stRaw : "10"
            let pic = stringField(o, "pic").filter(\.isNumber)
            upsert(Item(
                id: id,
                name: String(name.prefix(120)),
                desc: String(stringField(o, "desc").prefix(500)),
                num: num,
                storage: st,
                canuse: stringField(o, "canuse"),
                pic: pic
            ))
        }
    }

    private static func scrapePhoneBagHtml(_ html: String, defaultStorage: String) -> [Item] {
        if html.isEmpty || html.contains("登陆校验失败") || html.contains("请先登录") { return [] }
        var out: [Item] = []
        var seen = Set<String>()
        func add(_ id: String, _ nameRaw: String, _ num: Int) {
            let n = nameRaw
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if n.count < 2 || num <= 0 { return }
            if n.contains("返回") || n.contains("首页") || n.contains("下一页") || n.contains("上一页") { return }
            if n == "使用" || n == "出售" || n == "查看" { return }
            let key = id.isEmpty ? n : id
            if !seen.insert(key).inserted { return }
            out.append(Item(
                id: id, name: n, desc: "", num: num,
                storage: defaultStorage, canuse: id.isEmpty ? "" : "1"
            ))
        }
        for line in html.components(separatedBy: CharacterSet(charactersIn: "\n"))
            .flatMap({ $0.components(separatedBy: "<br />") })
            .flatMap({ $0.components(separatedBy: "<br/>") })
            .flatMap({ $0.components(separatedBy: "<br>") })
        {
            if !line.localizedCaseInsensitiveContains("cmd=use") && !line.contains("数量") { continue }
            let id = firstMatch(line, #"cmd=use(?:&amp;|&)id=(\d+)"#) ?? ""
            let num = firstMatch(line, #"数量[：:]\s*(\d{1,7})"#)
                .flatMap(Int.init)
                ?? firstMatch(line, #"[×*]\s*(\d{1,7})"#).flatMap(Int.init)
                ?? ((id.isEmpty || !line.contains("使用")) ? 0 : 1)
            let name = firstMatch(line, #">([^<>]{2,24})</a>"#)
                ?? firstMatch(
                    line.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression),
                    #"([\u4e00-\u9fff·A-Za-z0-9_]{2,24})\s*(?:数量|[×*])"#
                )
            if let name, num > 0 { add(id, name, num) }
        }
        return out
    }

    private static func resultOk(_ o: [String: Any]) -> Bool {
        guard o["result"] != nil else { return true }
        if let i = intField(o, "result") { return i == 0 }
        let s = stringField(o, "result")
        return s == "0" || s.lowercased() == "ok"
    }

    private static func jsonObject(_ raw: String) -> [String: Any]? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(t[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
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

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }
}

private extension String {
    func ifBlankBag(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
