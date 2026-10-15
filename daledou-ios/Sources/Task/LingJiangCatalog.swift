import Foundation

/// 对齐 Android `LingJiangCatalog`：从 Bundle 加载 keymap + checkbox 映射。
enum LingJiangCatalog {
    private static let sharedProtocolCb: [String: String] = [
        "ShengRiZhuFuDaLi": "cb_sr_dl",
        "JieBaiDouBi": "cb_jiebai_lingjiang",
        "KEY_XS_TBSH_LB": "cb_xs_tbsh",
        "KEY_XS_TBSH_FS": "cb_xs_tbsh",
        "KEY_XS_XCBN_LQ": "cb_xs_xcbn",
    ]

    private static var cached: [LingJiangItem]?
    private static var cbToKey: [String: String]?

    static func items() -> [LingJiangItem] {
        if let cached { return cached }
        let cbMap = checkboxToProtocol()
        var keyToCb = Dictionary(uniqueKeysWithValues: cbMap.map { ($0.value, $0.key) })
        for (k, v) in sharedProtocolCb { keyToCb[k] = v }

        guard let url = Bundle.main.url(forResource: "lingjiang_keymap", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let list: [LingJiangItem] = raw.compactMap { r in
            guard let key = r["key"] as? String, !key.isEmpty else { return nil }
            let title = (r["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let typeStr = r["type"] as? String ?? "\(r["type"] as? Int ?? 0)"
            let urlList = (r["urlList"] as? [String]) ?? []
            return LingJiangItem(
                key: key,
                title: (title?.isEmpty == false ? title! : key),
                type: Int(typeStr) ?? 0,
                url: (r["url"] as? String) ?? "",
                formatUrl: (r["fromatUrl"] as? String) ?? "",
                urlList: urlList,
                checkboxKey: keyToCb[key]
            )
        }
        cached = list
        return list
    }

    static func checkboxToProtocol() -> [String: String] {
        if let cbToKey { return cbToKey }
        guard let url = Bundle.main.url(forResource: "lingjiang_cb_to_key", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        cbToKey = map
        return map
    }

    static func protocolToCheckbox() -> [String: String] {
        var base = Dictionary(uniqueKeysWithValues: checkboxToProtocol().map { ($0.value, $0.key) })
        for (k, v) in sharedProtocolCb { base[k] = v }
        return base
    }

    /// UI：每个 checkbox 一条，标题取对应协议 title。
    static func checkboxRows() -> [(cb: String, title: String, protocolKey: String)] {
        let items = items()
        var seen = Set<String>()
        var rows: [(String, String, String)] = []
        for item in items {
            guard let cb = item.checkboxKey, seen.insert(cb).inserted else { continue }
            rows.append((cb, item.title, item.key))
        }
        // 映射里有、但 keymap 未挂上的 cb
        for (cb, key) in checkboxToProtocol() where !seen.contains(cb) {
            seen.insert(cb)
            let title = items.first(where: { $0.key == key })?.title ?? key
            rows.append((cb, title, key))
        }
        return rows.sorted { $0.0 < $1.0 }
    }
}
