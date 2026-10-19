import Foundation

/// 换装配置。专精 / 附魔编辑器仍待接入。
struct LoadoutConfig: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var enabled: [String: Bool]
    /// pos "0"/"1" → "knightId|name"；"0|不设置侠士" 跳过；空=未编辑
    var knight: [String: String]
    /// trigger "1"…"3" → "mercId|name"；"0|不设置佣兵" 卸下
    var mercenary: [String: String]
    /// storage "1"…"4" → "skillId|name"；"0|不设置技能" 跳过
    var aoyi: [String: String]
    /// "profileId|name"
    var avatar: String

    static let sections = ["专精", "奥义", "佣兵", "侠士", "附魔", "头像"]
    static let wiredSections: Set<String> = ["奥义", "佣兵", "侠士", "头像"]
    static let mercSlots = ["状态", "战斗", "防御"]
    static let aoyiSlots = ["青龙", "白虎", "朱雀", "玄武"]

    static func empty(name: String) -> LoadoutConfig {
        var en: [String: Bool] = [:]
        for s in sections { en[s] = true }
        var merc: [String: String] = [:]
        for i in 1...3 { merc["\(i)"] = "" }
        var aoyi: [String: String] = [:]
        for i in 1...4 { aoyi["\(i)"] = "" }
        return LoadoutConfig(
            id: String(Int(Date().timeIntervalSince1970 * 1000)),
            name: name,
            enabled: en,
            knight: ["0": "", "1": ""],
            mercenary: merc,
            aoyi: aoyi,
            avatar: ""
        )
    }

    init(
        id: String,
        name: String,
        enabled: [String: Bool],
        knight: [String: String],
        mercenary: [String: String],
        aoyi: [String: String],
        avatar: String
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.knight = knight
        self.mercenary = mercenary
        self.aoyi = aoyi
        self.avatar = avatar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent([String: Bool].self, forKey: .enabled) ?? [:]
        knight = try c.decodeIfPresent([String: String].self, forKey: .knight) ?? ["0": "", "1": ""]
        var merc = try c.decodeIfPresent([String: String].self, forKey: .mercenary) ?? [:]
        for n in 1...3 where merc["\(n)"] == nil { merc["\(n)"] = "" }
        mercenary = merc
        var ay = try c.decodeIfPresent([String: String].self, forKey: .aoyi) ?? [:]
        for n in 1...4 where ay["\(n)"] == nil { ay["\(n)"] = "" }
        aoyi = ay
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
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
            for n in 1...3 where configs[i].mercenary["\(n)"] == nil { configs[i].mercenary["\(n)"] = "" }
            for n in 1...4 where configs[i].aoyi["\(n)"] == nil { configs[i].aoyi["\(n)"] = "" }
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
