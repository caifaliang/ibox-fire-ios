import Foundation

/// 真源：`ChaQuStore` — 武林查区本地名册（按 uin 去重）。
@MainActor
final class ChaQuStore: ObservableObject {
    static let shared = ChaQuStore()

    struct Entry: Codable, Hashable, Identifiable {
        var id: String { uin }
        var uin: String
        var name: String = ""
        var level: Int = 0
        var value: Int = 0
        var saiqu: Int = 0
        var lzn: Int = 0
        var updatedAt: Double = Date().timeIntervalSince1970
    }

    @Published private(set) var revision = 0

    private let defaults = UserDefaults.standard
    private let key = "daledou.chaqu.roster"

    private init() {}

    func all() -> [Entry] {
        loadMap().values.sorted { $0.value > $1.value }
    }

    func size() -> Int { loadMap().count }

    func upsertAll(_ entries: [Entry]) {
        guard !entries.isEmpty else { return }
        var cur = loadMap()
        for e in entries where !e.uin.isEmpty {
            cur[e.uin] = e
        }
        saveMap(cur)
        revision &+= 1
    }

    func clear() {
        defaults.removeObject(forKey: key)
        revision &+= 1
    }

    func sample(_ limit: Int = 8) -> [String] {
        all().prefix(limit).map { "\($0.name)(\($0.uin)) Lv\($0.level) 战力\($0.value)" }
    }

    private func loadMap() -> [String: Entry] {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return map
    }

    private func saveMap(_ map: [String: Entry]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: key)
        }
    }
}
