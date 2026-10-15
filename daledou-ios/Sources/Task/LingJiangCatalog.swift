import Foundation

struct LingJiangItem: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let title: String
    let type: Int
    let url: String
    let formatUrl: String
    let urlList: [String]
    let checkboxKey: String?
}

enum LingJiangStepOutcome {
    case ok, busyRetry, loginFail, skip
}

/// 真源：assets `lingjiang_keymap.json` + `lingjiang_cb_to_key.json`
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
        let cbMap = loadCbMap()
        let keyToCb = Dictionary(uniqueKeysWithValues: cbMap.map { ($0.value, $0.key) })
            .merging(sharedProtocolCb) { _, new in new }
        guard let data = loadData("lingjiang_keymap"),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            cached = []
            return []
        }
        let items: [LingJiangItem] = arr.compactMap { r in
            guard let key = r["key"] as? String, !key.isEmpty else { return nil }
            let title = (r["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let typeStr = r["type"] as? String
            let type = Int(typeStr ?? "") ?? (r["type"] as? Int) ?? 0
            let urlList = (r["urlList"] as? [String]) ?? []
            return LingJiangItem(
                key: key,
                title: (title?.isEmpty == false ? title! : key),
                type: type,
                url: (r["url"] as? String) ?? "",
                formatUrl: (r["fromatUrl"] as? String) ?? "",
                urlList: urlList,
                checkboxKey: keyToCb[key]
            )
        }
        cached = items
        return items
    }

    static func checkboxToProtocol() -> [String: String] { loadCbMap() }

    static func protocolToCheckbox() -> [String: String] {
        let base = Dictionary(uniqueKeysWithValues: loadCbMap().map { ($0.value, $0.key) })
        return base.merging(sharedProtocolCb) { _, new in new }
    }

    private static func loadCbMap() -> [String: String] {
        if let cbToKey { return cbToKey }
        guard let data = loadData("lingjiang_cb_to_key"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            cbToKey = [:]
            return [:]
        }
        cbToKey = obj
        return obj
    }

    private static func loadData(_ name: String) -> Data? {
        if let u = Bundle.main.url(forResource: name, withExtension: "json") {
            return try? Data(contentsOf: u)
        }
        // XcodeGen folder resources may nest under Resources/
        if let u = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: nil) {
            return try? Data(contentsOf: u)
        }
        return nil
    }
}
