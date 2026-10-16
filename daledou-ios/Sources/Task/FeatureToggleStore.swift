import Foundation

final class FeatureToggleStore {
    static let shared = FeatureToggleStore()
    private let defaults = UserDefaults.standard
    private let prefix = "daledou.toggle."
    private init() {}

    func isEnabled(_ featureId: String) -> Bool {
        defaults.bool(forKey: prefix + featureId)
    }

    func setEnabled(_ featureId: String, _ enabled: Bool) {
        defaults.set(enabled, forKey: prefix + featureId)
    }

    func getBool(_ featureId: String, _ option: String, default def: Bool = false) -> Bool {
        let key = prefix + featureId + "." + option
        if defaults.object(forKey: key) == nil { return def }
        return defaults.bool(forKey: key)
    }

    func setBool(_ featureId: String, _ option: String, _ value: Bool) {
        defaults.set(value, forKey: prefix + featureId + "." + option)
    }

    func objectExists(_ featureId: String, _ option: String) -> Bool {
        defaults.object(forKey: prefix + featureId + "." + option) != nil
    }

    func getString(_ featureId: String, _ option: String, default def: String = "") -> String {
        defaults.string(forKey: prefix + featureId + "." + option) ?? def
    }

    func setString(_ featureId: String, _ option: String, _ value: String) {
        defaults.set(value, forKey: prefix + featureId + "." + option)
    }

    func getInt(_ featureId: String, _ option: String, default def: Int = 0) -> Int {
        let key = prefix + featureId + "." + option
        if defaults.object(forKey: key) == nil { return def }
        return defaults.integer(forKey: key)
    }

    func setInt(_ featureId: String, _ option: String, _ value: Int) {
        defaults.set(value, forKey: prefix + featureId + "." + option)
    }
}
