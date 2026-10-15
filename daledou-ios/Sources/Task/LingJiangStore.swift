import Foundation

/// 真源：`LingJiangStore.kt` — `lingjiang.<cb_*>`
final class LingJiangStore {
    static let shared = LingJiangStore()
    static let feature = "lingjiang"
    private let toggles = FeatureToggleStore.shared
    private let defaultsKey = "_defaults_applied_ios_v1"

    static let defaultCheckboxes: Set<String> = [
        "cb_day_login", "cb_day_chuangongfu", "cb_day_daren",
        "cb_day_tianshu", "cb_day_doubi", "cb_day_fenxiang",
    ]

    private init() { ensureDefaults() }

    func on(_ key: String) -> Bool {
        let def = LingJiangSettingDefs.defaultMap[key]
            ?? Self.defaultCheckboxes.contains(key)
        return toggles.getBool(Self.feature, key, default: def)
    }

    func set(_ key: String, _ checked: Bool) {
        toggles.setBool(Self.feature, key, checked)
    }

    func shouldRun(protocolKey: String) -> Bool {
        guard let cb = LingJiangCatalog.protocolToCheckbox()[protocolKey] else { return false }
        return on(cb)
    }

    private func ensureDefaults() {
        guard !toggles.getBool(Self.feature, defaultsKey, default: false) else { return }
        for cb in Self.defaultCheckboxes {
            if toggles.objectExists(Self.feature, cb) { continue }
            toggles.setBool(Self.feature, cb, true)
        }
        // also apply SettingPageDefs defaults
        for (key, def) in LingJiangSettingDefs.defaultMap where def {
            if toggles.objectExists(Self.feature, key) { continue }
            toggles.setBool(Self.feature, key, true)
        }
        toggles.setBool(Self.feature, defaultsKey, true)
    }
}
