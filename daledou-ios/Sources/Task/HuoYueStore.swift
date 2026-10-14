import Foundation

/// 对齐 Android `HuoYueStore`：`huoyue.<key>` 勾选。
final class HuoYueStore {
    static let shared = HuoYueStore()
    static let feature = "huoyue"

    private let toggles = FeatureToggleStore.shared
    private let defaultsKey = "_defaults_applied_v1"

    private init() {
        ensureDefaults()
    }

    func on(_ key: String) -> Bool {
        let def = defaultFor(key)
        return toggles.getBool(Self.feature, key, default: def)
    }

    func set(_ key: String, _ checked: Bool) {
        toggles.setBool(Self.feature, key, checked)
    }

    func enabledLabels() -> [String] {
        var out: [String] = []
        for e in LivenessCatalog.entries {
            guard let key = e.storeKey, !e.displayOnly, on(key) else { continue }
            out.append(e.title)
        }
        for t in LivenessCatalog.extraToggles where on(t.key) {
            out.append(t.label)
        }
        return out
    }

    private func defaultFor(_ key: String) -> Bool {
        if LivenessCatalog.scoreDefaultsOn.contains(key) { return true }
        if let t = LivenessCatalog.extraToggles.first(where: { $0.key == key }) {
            return t.defaultOn
        }
        return false
    }

    private func ensureDefaults() {
        guard !toggles.getBool(Self.feature, defaultsKey, default: false) else { return }
        for key in LivenessCatalog.scoreDefaultsOn {
            toggles.setBool(Self.feature, key, true)
        }
        for t in LivenessCatalog.extraToggles where t.defaultOn {
            toggles.setBool(Self.feature, t.key, true)
        }
        toggles.setBool(Self.feature, defaultsKey, true)
    }
}
