import Foundation

/// 对齐 Android `LingJiangStore`。
final class LingJiangStore {
    static let shared = LingJiangStore()
    static let feature = "lingjiang"

    static let defaultCheckboxes: Set<String> = [
        "cb_day_login",
        "cb_day_chuangongfu",
        "cb_day_daren",
        "cb_day_tianshu",
        "cb_day_doubi",
        "cb_day_fenxiang",
    ]

    private let toggles = FeatureToggleStore.shared
    private let defaultsKey = "_defaults_applied_v1"

    private init() {
        ensureDefaults()
    }

    func isChecked(_ checkboxKey: String, default def: Bool = false) -> Bool {
        toggles.getBool(Self.feature, checkboxKey, default: def)
    }

    func setChecked(_ checkboxKey: String, _ checked: Bool) {
        toggles.setBool(Self.feature, checkboxKey, checked)
    }

    func shouldRun(protocolKey: String) -> Bool {
        guard let cb = LingJiangCatalog.protocolToCheckbox()[protocolKey] else { return false }
        let def = Self.defaultCheckboxes.contains(cb)
        return isChecked(cb, default: def)
    }

    func enabledTitles() -> [String] {
        LingJiangCatalog.items().compactMap { item in
            guard shouldRun(protocolKey: item.key) else { return nil }
            return item.title
        }
    }

    private func ensureDefaults() {
        guard !toggles.getBool(Self.feature, defaultsKey, default: false) else { return }
        for cb in Self.defaultCheckboxes {
            toggles.setBool(Self.feature, cb, true)
        }
        toggles.setBool(Self.feature, defaultsKey, true)
    }
}
