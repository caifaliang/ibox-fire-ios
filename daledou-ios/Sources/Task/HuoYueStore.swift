import Foundation

/// 真源：`HuoYueStore.kt` — `huoyue.<key>` 勾选；default 与设置页同一套。
final class HuoYueStore {
    static let shared = HuoYueStore()
    static let feature = "huoyue"
    private let toggles = FeatureToggleStore.shared
    private let defaultsKey = "_defaults_applied_ios_v1"
    private let defaultMap = HuoYueSettingDefs.defaultMap

    private init() { ensureDefaults() }

    func on(_ key: String) -> Bool {
        let def = defaultMap[key] ?? false
        return toggles.getBool(Self.feature, key, default: def)
    }

    func set(_ key: String, _ checked: Bool) {
        toggles.setBool(Self.feature, key, checked)
    }

    func enabledLabels() -> [String] {
        HuoYueSettingDefs.sections.flatMap { sec in
            sec.items.filter { $0.kind == .check && on($0.key) }.map(\.label)
        }
    }

    private func ensureDefaults() {
        guard !toggles.getBool(Self.feature, defaultsKey, default: false) else { return }
        for (key, def) in defaultMap where def {
            if toggles.objectExists(Self.feature, key) { continue }
            toggles.setBool(Self.feature, key, true)
        }
        toggles.setBool(Self.feature, defaultsKey, true)
    }
}
