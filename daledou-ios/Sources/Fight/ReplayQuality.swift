import Foundation

/// 官方动画清晰度（对齐 flashreplay `qualityScales`）。
enum ReplayQuality {
    static let defaultsKey = "daledou.replay.quality"
    /// 默认清晰（比 standard 更清楚）；极致档易掉帧/OOM。
    static let fallback = "medium"
    static let order = ["standard", "medium", "mediumHigh", "high"]

    static var current: String {
        get {
            let v = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback
            return order.contains(v) ? v : fallback
        }
        set {
            let v = order.contains(newValue) ? newValue : fallback
            UserDefaults.standard.set(v, forKey: defaultsKey)
        }
    }

    static func label(for key: String) -> String {
        switch key {
        case "standard": return "流畅"
        case "medium": return "清晰"
        case "mediumHigh": return "高清"
        case "high": return "超清"
        default: return "清晰"
        }
    }

    static func next(after key: String) -> String {
        guard let i = order.firstIndex(of: key) else { return fallback }
        return order[(i + 1) % order.count]
    }
}
