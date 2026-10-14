import Foundation

/// 对齐 Android `FeatureCatalog.autoDaiWanTypes`（一字不差）。
enum DaiWanCatalog {
    static let autoDaiWanTypes: [String] = [
        "一键活跃代玩", "一键领奖", "会武", "祭坛", "仙武修真", "竞技场", "华山论剑",
        "深渊秘境", "打满问鼎", "遗迹征伐", "门派任务", "龙凰论武", "道聚城", "武器充能",
        "报名电脑武林", "报名手机武林", "报名群侠", "矿洞监听",
        "批量斗友-师徒情拜", "批量斗友-好友", "批量斗友-帮友", "历练",
        "自动换装-id：1", "自动换装-id：2", "自动换装-id：3", "自动换装-id：4", "自动换装-id：5",
        "劫镖",
    ]

    static func typeId(_ index: Int) -> String { "daiwan_type_\(index)" }

    static func typeName(forId id: String) -> String? {
        guard id.hasPrefix("daiwan_type_"),
              let i = Int(id.dropFirst("daiwan_type_".count)),
              autoDaiWanTypes.indices.contains(i) else { return nil }
        return autoDaiWanTypes[i]
    }
}
