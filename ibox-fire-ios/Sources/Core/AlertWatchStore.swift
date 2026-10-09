import Foundation

struct FollowItem: Identifiable, Equatable {
    var id: Int64 { groupId }
    var groupId: Int64
    var groupName: String
}

struct PriceAlertItem: Identifiable, Equatable {
    var id: Int64 { groupId }
    var groupId: Int64
    var groupName: String
    var alertUp: Double?
    var alertDown: Double?
    var enabled: Bool
}

/// 对齐 Android AlertWatchStore：四路独立开关 + 关注/屏蔽/预警缓存。
final class AlertWatchStore {
    static let shared = AlertWatchStore()
    private let p = UserDefaults.standard
    private let kMarket = "ibox.push.market"
    private let kPrice = "ibox.push.price"
    private let kAnnounce = "ibox.push.announce"
    private let kDiscover = "ibox.push.discover"
    private let kWx = "ibox.push.wxuid"
    private let kFollows = "ibox.push.follows"
    private let kBlocks = "ibox.push.blocks"
    private let kAlerts = "ibox.push.alerts"

    var marketWatchEnabled: Bool {
        get { p.bool(forKey: kMarket) }
        set { p.set(newValue, forKey: kMarket) }
    }
    var priceAlertWatchEnabled: Bool {
        get { p.bool(forKey: kPrice) }
        set { p.set(newValue, forKey: kPrice) }
    }
    var announcePushEnabled: Bool {
        get { p.bool(forKey: kAnnounce) }
        set { p.set(newValue, forKey: kAnnounce) }
    }
    var discoverPushEnabled: Bool {
        get { p.bool(forKey: kDiscover) }
        set { p.set(newValue, forKey: kDiscover) }
    }
    var wxpusherUid: String {
        get { p.string(forKey: kWx) ?? "" }
        set { p.set(newValue, forKey: kWx) }
    }
    var marketOrPriceEnabled: Bool { marketWatchEnabled || priceAlertWatchEnabled }
    var anyWatchEnabled: Bool { marketOrPriceEnabled || announcePushEnabled || discoverPushEnabled }

    var iboxToken: String = ""
    var platformToken: String = ""
    var siteBase: String = "https://ai.iboxai.top/api"

    func saveFollows(_ list: [FollowItem]) { savePairs(list, key: kFollows) }
    func loadFollows() -> [FollowItem] { loadPairs(kFollows) }
    func saveBlocks(_ list: [FollowItem]) { savePairs(list, key: kBlocks) }
    func loadBlocks() -> [FollowItem] { loadPairs(kBlocks) }

    func saveAlerts(_ list: [PriceAlertItem]) {
        let arr: [[String: Any]] = list.map {
            var o: [String: Any] = ["group_id": $0.groupId, "group_name": $0.groupName, "enabled": $0.enabled ? 1 : 0]
            if let u = $0.alertUp { o["alert_up"] = u }
            if let d = $0.alertDown { o["alert_down"] = d }
            return o
        }
        if let data = try? JSONSerialization.data(withJSONObject: arr),
           let s = String(data: data, encoding: .utf8) {
            p.set(s, forKey: kAlerts)
        }
    }

    func loadAlerts() -> [PriceAlertItem] {
        guard let raw = p.string(forKey: kAlerts),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { a in
            let gid = JSONX.int64Val(a["group_id"]) ?? 0
            guard gid > 0 else { return nil }
            let up = JSONX.doubleVal(a["alert_up"]).flatMap { $0 > 0 ? $0 : nil }
            let down = JSONX.doubleVal(a["alert_down"]).flatMap { $0 > 0 ? $0 : nil }
            let en = (JSONX.int64Val(a["enabled"]) ?? 1) == 1
            return PriceAlertItem(
                groupId: gid,
                groupName: JSONX.stringVal(a["group_name"]).isEmpty ? "GID \(gid)" : JSONX.stringVal(a["group_name"]),
                alertUp: up,
                alertDown: down,
                enabled: en
            )
        }
    }

    private func savePairs(_ list: [FollowItem], key: String) {
        let arr: [[String: Any]] = list.map { ["group_id": $0.groupId, "group_name": $0.groupName] }
        if let data = try? JSONSerialization.data(withJSONObject: arr),
           let s = String(data: data, encoding: .utf8) {
            p.set(s, forKey: key)
        }
    }

    private func loadPairs(_ key: String) -> [FollowItem] {
        guard let raw = p.string(forKey: key),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { a in
            let gid = JSONX.int64Val(a["group_id"]) ?? 0
            guard gid > 0 else { return nil }
            return FollowItem(groupId: gid, groupName: JSONX.stringVal(a["group_name"]))
        }
    }
}
