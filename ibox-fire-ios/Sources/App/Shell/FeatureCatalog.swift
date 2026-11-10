import Foundation

/// 对齐 Android `ui/shell/FeatureCatalog` — key/label 一字不改；壳上不含矩星 ts_*。
struct ShellTechTab: Identifiable, Hashable {
    let key: String
    let label: String
    let localReady: Bool
    let isNew: Bool
    var id: String { key }
    var mode: TechMode? { TechMode(rawValue: key) }
}

struct ShellFeatureCat: Identifiable, Hashable {
    let key: String
    let label: String
    let features: [ShellTechTab]
    var id: String { key }
}

enum FeatureCatalog {
    static let techFeatures: [ShellTechTab] = [
        .init(key: "seg_snipe", label: "全盘捡漏", localReady: true, isNew: true),
        .init(key: "recommend_lock", label: "推荐锁定", localReady: true, isNew: true),
        .init(key: "announce", label: "公告锁定", localReady: true, isNew: false),
        .init(key: "buy", label: "捡漏", localReady: true, isNew: false),
        .init(key: "batch", label: "上下架", localReady: true, isNew: false),
        .init(key: "sell", label: "卖求购", localReady: true, isNew: false),
        .init(key: "synth", label: "抢合", localReady: true, isNew: false),
        .init(key: "presale", label: "抢购", localReady: true, isNew: false),
        .init(key: "sweep", label: "点对点", localReady: true, isNew: true),
        .init(key: "precision", label: "精准射", localReady: true, isNew: true),
    ]

    static let queryFeatures: [ShellTechTab] = [
        .init(key: "query_purchase", label: "查求购", localReady: true, isNew: true),
        .init(key: "query_consignment", label: "查挂单", localReady: true, isNew: true),
        .init(key: "holdings", label: "个人持仓", localReady: true, isNew: true),
    ]

    static let pushFeatures: [ShellTechTab] = [
        .init(key: "price_alert", label: "单图价格预警", localReady: true, isNew: true),
        .init(key: "market_push", label: "全图异动推送", localReady: true, isNew: true),
        .init(key: "announce_push", label: "公告推送", localReady: true, isNew: true),
        .init(key: "discover_push", label: "发现趋势推送", localReady: true, isNew: true),
    ]

    static let iboxCats: [ShellFeatureCat] = [
        .init(key: "tech", label: "科技", features: techFeatures),
        .init(key: "query_info", label: "查询信息", features: queryFeatures),
        .init(key: "push_cat", label: "推送", features: pushFeatures),
    ]

    static let nbTabs: [ShellTechTab] = [
        .init(key: "nb_presale", label: "抢购", localReady: true, isNew: true),
        .init(key: "nb_snipe", label: "捡漏", localReady: true, isNew: true),
    ]

    static let ibTabs: [ShellTechTab] = [
        .init(key: "ib_presale", label: "抢购", localReady: true, isNew: true),
        .init(key: "ib_snipe", label: "捡漏", localReady: true, isNew: true),
        .init(key: "ib_sell", label: "卖求购", localReady: true, isNew: true),
        .init(key: "ib_query", label: "查挂单", localReady: true, isNew: true),
    ]

    static let allTechTabs: [ShellTechTab] =
        techFeatures + queryFeatures + pushFeatures + nbTabs + ibTabs + [
            .init(key: "push_watch", label: "推送", localReady: true, isNew: false),
            .init(key: "query", label: "查询", localReady: true, isNew: false),
        ]

    static func tabsForPlatform(_ platform: String) -> [ShellTechTab] {
        switch platform {
        case "newbee": return nbTabs
        case "ibpro": return ibTabs
        default:
            return allTechTabs.filter { !$0.key.hasPrefix("nb_") && !$0.key.hasPrefix("ib_") }
        }
    }

    static func catsForPlatform(_ platform: String) -> [ShellFeatureCat] {
        switch platform {
        case "newbee": return [.init(key: "nb", label: "NewBee", features: nbTabs)]
        case "ibpro": return [.init(key: "ib", label: "ibPro", features: ibTabs)]
        default: return iboxCats
        }
    }

    static func defaultCategory(_ platform: String) -> String {
        catsForPlatform(platform).first?.key ?? "tech"
    }

    static func filterFeatures(platform: String, category: String, query: String) -> [ShellTechTab] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool: [ShellTechTab]
        if q.isEmpty {
            pool = catsForPlatform(platform).first(where: { $0.key == category })?.features
                ?? tabsForPlatform(platform)
        } else {
            pool = tabsForPlatform(platform)
        }
        guard !q.isEmpty else { return pool }
        return pool.filter {
            $0.label.localizedCaseInsensitiveContains(q) || $0.key.localizedCaseInsensitiveContains(q)
        }
    }

    static func labelOf(_ mode: String) -> String {
        allTechTabs.first(where: { $0.key == mode })?.label ?? ""
    }

    static func platformKey(_ p: AppPlatform) -> String {
        switch p {
        case .ibox: return "ibox"
        case .newbee: return "newbee"
        case .ibpro: return "ibpro"
        case .topstar: return "ibox" // 壳上隐藏矩星，回落到 iBox
        }
    }
}
