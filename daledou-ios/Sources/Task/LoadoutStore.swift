import Foundation

/// 换装配置（本切片只落盘侠士 / 头像；专精/奥义/佣兵/附魔键位预留）。
struct LoadoutConfig: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var enabled: [String: Bool]
    /// pos "0"/"1" → "knightId|name"；"0|不设置侠士" 跳过；空=未编辑
    var knight: [String: String]
    /// "profileId|name"
    var avatar: String

    static let sections = ["专精", "奥义", "佣兵", "侠士", "附魔", "头像"]
    static let wiredSections: Set<String> = ["侠士", "头像"]

    static func empty(name: String) -> LoadoutConfig {
        var en: [String: Bool] = [:]
        for s in sections { en[s] = true }
        return LoadoutConfig(
            id: String(Int(Date().timeIntervalSince1970 * 1000)),
            name: name,
            enabled: en,
            knight: ["0": "", "1": ""],
            avatar: ""
        )
    }

    func tokenName(_ token: String) -> String {
        let name = token.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        if !name.isEmpty { return name }
        let id = token.split(separator: "|").first.map(String.init) ?? token
        return id.isEmpty ? "未设置" : id
    }
}

enum LoadoutStore {
    private static let key = "fd_loadout_local"

    struct Snapshot: Codable {
        var configs: [LoadoutConfig]
        var active: Int
    }

    static func load() -> Snapshot {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              !snap.configs.isEmpty
        else {
            return Snapshot(configs: [.empty(name: "配置1"), .empty(name: "配置2")], active: 0)
        }
        var configs = snap.configs
        for i in configs.indices {
            for s in LoadoutConfig.sections where configs[i].enabled[s] == nil {
                configs[i].enabled[s] = true
            }
            if configs[i].knight["0"] == nil { configs[i].knight["0"] = "" }
            if configs[i].knight["1"] == nil { configs[i].knight["1"] = "" }
        }
        let active = min(max(0, snap.active), configs.count - 1)
        return Snapshot(configs: configs, active: active)
    }

    static func save(_ snap: Snapshot) {
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
