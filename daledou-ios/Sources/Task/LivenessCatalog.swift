import Foundation

struct LivenessCatalogEntry: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let title: String
    let points: Int
    let storeKey: String?
    let wired: Bool
    let displayOnly: Bool
}

/// 真源：`DaLedou_App_Dev` LivenessCatalog.kt
enum LivenessCatalog {
    static let entries: [LivenessCatalogEntry] = [
        .init(index: 1, title: "乐斗10次", points: 1, storeKey: "lv_fight10", wired: true, displayOnly: false),
        .init(index: 2, title: "完成任务", points: 1, storeKey: "cb_rw_rc", wired: true, displayOnly: false),
        .init(index: 3, title: "历练", points: 1, storeKey: "cb_dw_ll", wired: true, displayOnly: false),
        .init(index: 4, title: "回流好友召回", points: 1, storeKey: "cb_rw_hl", wired: true, displayOnly: false),
        .init(index: 5, title: "护送押镖", points: 2, storeKey: "cb_rw_yb", wired: true, displayOnly: false),
        .init(index: 6, title: "挑战深渊", points: 5, storeKey: "cb_gd_sy", wired: true, displayOnly: false),
        .init(index: 7, title: "画卷迷踪", points: 5, storeKey: "cb_dw_hj", wired: true, displayOnly: false),
        .init(index: 8, title: "同门切磋", points: 6, storeKey: "lv_tongmen", wired: true, displayOnly: false),
        .init(index: 9, title: "武林大会", points: 5, storeKey: "lv_wulin", wired: true, displayOnly: false),
        .init(index: 10, title: "飘渺幻境", points: 2, storeKey: "cb_dw_hjpm", wired: true, displayOnly: false),
        .init(index: 11, title: "分享", points: 1, storeKey: "lv_share", wired: true, displayOnly: false),
        .init(index: 12, title: "供奉", points: 5, storeKey: "cb_rw_gf", wired: true, displayOnly: false),
        .init(index: 13, title: "乐斗20次", points: 7, storeKey: "lv_fight20", wired: true, displayOnly: false),
        .init(index: 14, title: "镶嵌魂珠", points: 5, storeKey: "lv_inlay", wired: true, displayOnly: false),
        .init(index: 15, title: "传功12次", points: 5, storeKey: "cb_rw_cg12", wired: true, displayOnly: false),
        .init(index: 16, title: "提升助阵属性", points: 1, storeKey: "cb_rw_zz", wired: true, displayOnly: false),
        .init(index: 17, title: "兑换100斗豆", points: 10, storeKey: "cb_hy_dh_1", wired: true, displayOnly: false),
        .init(index: 18, title: "商店消费", points: 5, storeKey: "cb_rw_xf", wired: true, displayOnly: false),
        .init(index: 19, title: "成为达人", points: 10, storeKey: "lv_daren", wired: false, displayOnly: true),
        .init(index: 20, title: "兑换500斗豆", points: 20, storeKey: "cb_hy_dh_2", wired: true, displayOnly: false),
    ]

    static let fightTargetKeys: [(String, String)] = [
        ("lv_fight_boss_hy", "好友Boss"),
        ("lv_fight_boss_bp", "帮派Boss"),
        ("lv_fight_boss_xb", "侠拜Boss"),
        ("lv_fight_shitu", "师徒"),
        ("lv_fight_fuqi", "夫妻"),
        ("lv_fight_jiebai", "结拜"),
        ("lv_fight_tili", "自动体力"),
    ]

    static let extraToggles: [(String, String, Bool)] = [
        ("cb_lj_hy", "活跃礼包", true),
        ("cb_rw_bp", "帮派任务", false),
        ("cb_rw_mp", "门派任务", false),
        ("cb_lj_smzp", "神魔转盘", false),
        ("cb_lj_wwj", "开心娃娃机", false),
        ("cb_lj_cds", "猜单双", false),
        ("cb_lj_bc", "镖车奖励", false),
        ("cb_dy_dt", "打铁一次", false),
    ]

    static let scoreDefaultsOn: Set<String> = [
        "lv_fight10", "lv_tongmen", "lv_wulin", "lv_share", "lv_inlay",
        "lv_fight_boss_hy", "lv_fight_boss_bp", "lv_fight_boss_xb",
        "lv_fight_shitu", "lv_fight_fuqi", "lv_fight_jiebai", "lv_fight_tili",
        "cb_lj_hy",
    ]

    static func estimatePoints(isOn: (String) -> Bool) -> Int {
        var sum = 0
        for e in entries {
            if !e.wired || e.displayOnly { continue }
            switch e.index {
            case 2:
                if isOn("cb_rw_rc") || isOn("cb_rw_bp") || isOn("cb_rw_mp") { sum += e.points }
            case 17:
                if isOn("cb_rw_dh") && isOn("cb_hy_dh_1") { sum += e.points }
            case 20:
                if isOn("cb_rw_dh") && isOn("cb_hy_dh_2") { sum += e.points }
            default:
                guard let key = e.storeKey, isOn(key) else { continue }
                sum += e.points
            }
        }
        return sum
    }
}
