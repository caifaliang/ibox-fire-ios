import Foundation

struct BeiBaoItem: Identifiable, Hashable {
    var id: String
    var name: String
    var num: Int
    var storage: String
}

/// 背包查询（M9）：先刮 phonepk cmd=store，对齐 Android scrapePhoneBagHtml 主路径。
enum BeiBaoService {
    static let tabs: [(label: String, storage: String)] = [
        ("全部", "0"),
        ("药水", "1"),
        ("属性", "2"),
        ("强化", "3"),
        ("星石", "6"),
        ("魂珠", "4"),
        ("锦囊", "5"),
        ("其他", "10"),
        ("荣誉", "7"),
    ]

    static func loadCatalog(cookie: String, onLog: @escaping (String) -> Void) async -> [BeiBaoItem] {
        var out: [BeiBaoItem] = []
        var seen = Set<String>()
        func upsert(_ item: BeiBaoItem) {
            let key = item.id.isEmpty ? item.name : item.id
            guard !key.isEmpty, item.num > 0 else { return }
            if seen.insert(key).inserted {
                out.append(item.id.isEmpty ? BeiBaoItem(id: key, name: item.name, num: item.num, storage: item.storage) : item)
            }
        }

        let storeTypes: [(stype: String, storage: String)] = [
            ("", "10"), ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4"),
            ("5", "5"), ("6", "6"), ("7", "7"), ("10", "10"),
        ]
        var phoneHit = 0
        for (stype, storage) in storeTypes {
            var page = 1
            var emptyStreak = 0
            while page <= 8 {
                var extra: [String: String] = [:]
                if !stype.isEmpty { extra["store_type"] = stype }
                if page > 1 { extra["page"] = "\(page)" }
                let (_, html) = await LedouCGI.getPhonePk(cmd: "store", extra: extra, cookie: cookie)
                if html.isEmpty || html.contains("登陆校验失败") || html.contains("请先登录") {
                    if stype.isEmpty && page == 1 { onLog("phone store 未登录") }
                    break
                }
                let items = scrapePhoneStore(html: html, defaultStorage: storage)
                if items.isEmpty {
                    emptyStreak += 1
                    let hasNext = html.contains("下一页") || html.contains("page=\(page + 1)")
                    if !hasNext || emptyStreak >= 2 { break }
                    page += 1
                    continue
                }
                emptyStreak = 0
                items.forEach(upsert)
                phoneHit += items.count
                let hasNext = html.contains("下一页") || html.contains("page=\(page + 1)")
                if !hasNext { break }
                page += 1
            }
        }
        if phoneHit > 0 {
            onLog("phone store 解析约 \(phoneHit) 条")
        }
        return out
    }

    static func scrapePhoneStore(html: String, defaultStorage: String) -> [BeiBaoItem] {
        if html.isEmpty || html.contains("登陆校验失败") || html.contains("请先登录") {
            return []
        }
        var out: [BeiBaoItem] = []
        var seen = Set<String>()
        let lines = html
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .components(separatedBy: "\n")

        let idRe = try? NSRegularExpression(pattern: #"cmd=use(?:&amp;|&)id=(\d+)"#, options: .caseInsensitive)
        let numRe = try? NSRegularExpression(pattern: #"数量[：:]\s*(\d{1,7})|×\s*(\d{1,7})|\*(\d{1,7})"#)
        let nameRe = try? NSRegularExpression(pattern: #">([^<>]{2,24})</a>"#)

        for line in lines {
            guard line.lowercased().contains("cmd=use") || line.contains("数量") else { continue }
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            var id = ""
            if let m = idRe?.firstMatch(in: line, range: full), m.numberOfRanges >= 2 {
                id = ns.substring(with: m.range(at: 1))
            }
            var num = 0
            if let m = numRe?.firstMatch(in: line, range: full) {
                for i in 1..<m.numberOfRanges {
                    let r = m.range(at: i)
                    if r.location != NSNotFound {
                        let s = ns.substring(with: r)
                        if let n = Int(s) { num = n; break }
                    }
                }
            }
            if num <= 0, !id.isEmpty, line.contains("使用") { num = 1 }
            var name = ""
            if let matches = nameRe?.matches(in: line, range: full) {
                for m in matches where m.numberOfRanges >= 2 {
                    let n = ns.substring(with: m.range(at: 1))
                        .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                    if n == "使用" || n == "出售" || n == "查看" || n.contains("返回") { continue }
                    name = n
                    break
                }
            }
            name = name.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            guard name.count >= 2, num > 0 else { continue }
            if name.contains("返回") || name.contains("首页") || name.contains("下一页") { continue }
            let key = id.isEmpty ? name : id
            guard seen.insert(key).inserted else { continue }
            out.append(BeiBaoItem(id: id, name: name, num: num, storage: defaultStorage))
        }
        return out
    }
}
