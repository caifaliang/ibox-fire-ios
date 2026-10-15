import Foundation

enum SettingKind {
    case check
    case text
}

struct SettingItem: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let `default`: Bool
    let radioGroup: String?
    let kind: SettingKind

    init(
        _ key: String,
        _ label: String,
        _ defaultOn: Bool = false,
        radioGroup: String? = nil,
        kind: SettingKind = .check
    ) {
        self.key = key
        self.label = label
        self.default = defaultOn
        self.radioGroup = radioGroup
        self.kind = kind
    }
}

struct SettingSection: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let items: [SettingItem]
}

/// 真源：`SettingPageDefs.huoYue`（DaLedou_App_Dev）
enum HuoYueSettingDefs {
    static let sections: [SettingSection] = [
        SettingSection(title: "冲活跃分(官方20条)", items: [
            .init("lv_fight10", "乐斗10次", true),
            .init("lv_fight20", "乐斗20次"),
            .init("lv_fight_boss_hy", "好友Boss", true),
            .init("lv_fight_boss_bp", "帮派Boss", true),
            .init("lv_fight_boss_xb", "侠拜Boss", true),
            .init("lv_fight_shitu", "师徒", true),
            .init("lv_fight_fuqi", "夫妻", true),
            .init("lv_fight_jiebai", "结拜", true),
            .init("lv_fight_tili", "自动体力", true),
            .init("lv_tongmen", "同门切磋", true),
            .init("lv_wulin", "武林大会", true),
            .init("lv_share", "历程分享", true),
            .init("lv_inlay", "镶嵌魂珠", true),
        ]),
        SettingSection(title: "记录背包材料", items: [
            .init("cb_save_beibao", "代玩前保存背包材料数量", true),
        ]),
        SettingSection(title: "打铁", items: [
            .init("cb_dy_dt", "使用百炼钢打铁一次"),
        ]),
        SettingSection(title: "自动批量斗友（点击设置）", items: [
            .init("cb_dy_stqb", "师徒情拜"),
            .init("cb_dy_hy", "好友"),
            .init("cb_dy_by", "帮友"),
        ]),
        SettingSection(title: "自动代玩（点击设置）", items: [
            .init("cb_dw_ll", "历练", true),
            .init("cb_dw_hj", "画卷", true),
            .init("cb_dw_12", "12宫", true),
            .init("cb_dw_hjpm", "幻境", true),
            .init("cb_dw_boss", "Boss"),
            .init("cb_dw_hw", "会武"),
            .init("cb_dw_mp", "门派"),
            .init("cb_dw_df", "巅峰"),
            .init("cb_dw_fxll", "反向历练"),
        ]),
        SettingSection(title: "自动任务和活跃任务（点击设置）", items: [
            .init("cb_rw_rc", "日常任务", true),
            .init("cb_rw_bp", "帮派任务", true),
            .init("cb_rw_mp", "门派任务", true),
            .init("cb_rw_hl", "好友召回"),
            .init("cb_rw_zz", "佣兵助阵"),
            .init("cb_rw_gf", "帮派供奉"),
            .init("cb_rw_yb", "护送押镖"),
            .init("cb_rw_xf", "商店消费"),
            .init("cb_rw_dh", "兑换豆豆"),
            .init("cb_rw_cg12", "传功12次"),
            .init("cb_rw_cg_not_level", "解除5级传功限制（慎重勾选）"),
        ]),
        SettingSection(title: "自动监听（需要自行设置后台任务权限）", items: [
            .init("cb_dw_kd", "矿洞"),
            .init("cb_dw_jb", "劫镖"),
            .init("cb_dw_lc", "粮草"),
            .init("cb_dw_lhlw", "龙凰论武"),
        ]),
        SettingSection(title: "自动更多（点击设置）", items: [
            .init("cb_gd_dst", "斗神塔"),
            .init("cb_gd_jt", "祭坛"),
            .init("cb_gd_xw", "仙武"),
            .init("cb_gd_jjc", "竞技场"),
            .init("cb_gd_qdp", "抢地盘"),
            .init("cb_gd_tg", "踢馆"),
            .init("cb_gd_sy", "深渊秘境"),
            .init("cb_dw_wd", "打满问鼎"),
            .init("cb_dw_djc", "道聚城"),
            .init("cb_dw_hslj", "华山论剑"),
            .init("cb_dw_xcdl", "新春对联"),
            .init("cb_dw_wdgj", "微端挂机"),
            .init("cb_dw_yjzf", "遗迹征伐"),
            .init("cb_dw_hjls", "黄金联赛"),
            .init("cb_dw_mxzl", "梦想之旅"),
            .init("cb_dw_yjsd_dh", "遗迹商店兑换"),
        ]),
        SettingSection(title: "自动领奖", items: [
            .init("cb_lj_hy", "活跃礼包", true),
            .init("cb_lj_bc", "镖车奖励"),
            .init("cb_lj_wd", "微端活跃"),
            .init("cb_lj_wwj", "开心娃娃机"),
            .init("cb_lj_smzp", "神魔转盘"),
            .init("cb_lj_cds", "猜单双"),
            .init("cb_lj_symb", "深渊秘宝"),
            .init("cb_lj_yj", "游记任务"),
            .init("cb_lj_zi_dong_yi_jian", "一键领奖"),
            .init("cb_lj_djtm", "斗境探秘"),
        ]),
        SettingSection(title: "星盘升级", items: [
            .init("rb_xpsj_1", "日曜石", true, radioGroup: "xpsj"),
            .init("rb_xpsj_2", "玛瑙石", radioGroup: "xpsj"),
            .init("rb_xpsj_3", "迅捷石", radioGroup: "xpsj"),
            .init("rb_xpsj_4", "月光石", radioGroup: "xpsj"),
            .init("rb_xpsj_5", "翡翠石", radioGroup: "xpsj"),
            .init("rb_xpsj_6", "紫黑玉", radioGroup: "xpsj"),
            .init("rb_xpsj_7", "狂暴石", radioGroup: "xpsj"),
            .init("rb_xpsj_8", "神愈石", radioGroup: "xpsj"),
            .init("rb_xpsj_lv_1", "1", true, radioGroup: "xpsjlv"),
            .init("rb_xpsj_lv_2", "2", radioGroup: "xpsjlv"),
            .init("rb_xpsj_lv_3", "3", radioGroup: "xpsjlv"),
            .init("rb_xpsj_lv_4", "4", radioGroup: "xpsjlv"),
            .init("rb_xpsj_lv_5", "5", radioGroup: "xpsjlv"),
            .init("rb_xpsj_lv_6", "6", radioGroup: "xpsjlv"),
            .init("rb_xpsj_lv_7", "7", radioGroup: "xpsjlv"),
            .init("ed_xpsj_num", "输入星石的数量", kind: .text),
        ]),
        SettingSection(title: "魂珠升级", items: [
            .init("rb_hzsj_1", "剑军", true, radioGroup: "hzsj"),
            .init("rb_hzsj_2", "菜菜", radioGroup: "hzsj"),
            .init("rb_hzsj_3", "月璇", radioGroup: "hzsj"),
            .init("rb_hzsj_4", "帅帅", radioGroup: "hzsj"),
            .init("rb_hzsj_5", "血灵", radioGroup: "hzsj"),
            .init("rb_hzsj_6", "月影", radioGroup: "hzsj"),
            .init("rb_hzsj_7", "教主", radioGroup: "hzsj"),
            .init("rb_hzsj_lv_1", "1", true, radioGroup: "hzsjlv"),
            .init("rb_hzsj_lv_2", "2", radioGroup: "hzsjlv"),
            .init("rb_hzsj_lv_3", "3", radioGroup: "hzsjlv"),
            .init("rb_hzsj_lv_4", "4", radioGroup: "hzsjlv"),
            .init("rb_hzsj_lv_5", "5", radioGroup: "hzsjlv"),
            .init("rb_hzsj_lv_6", "6", radioGroup: "hzsjlv"),
            .init("rb_hzsj_lv_7", "7", radioGroup: "hzsjlv"),
            .init("ed_hzsj_num", "输入魂珠的数量", kind: .text),
        ]),
        SettingSection(title: "星盘换装", items: [
            .init("ed_xphz_1", "日曜石目标数", kind: .text),
            .init("ed_xphz_2", "玛瑙石目标数", kind: .text),
            .init("ed_xphz_3", "迅捷石目标数", kind: .text),
            .init("ed_xphz_4", "月光石目标数", kind: .text),
            .init("ed_xphz_5", "翡翠石目标数", kind: .text),
            .init("ed_xphz_6", "紫黑玉目标数", kind: .text),
            .init("cb_xphz_snap", "空目标时用当前星盘覆盖"),
        ]),
        SettingSection(title: "一键自动换装", items: [
            .init("rb_yjhz_1", "方案一(装扮1)", true, radioGroup: "yjhz"),
            .init("rb_yjhz_2", "方案二(装扮2)", radioGroup: "yjhz"),
            .init("rb_yjhz_3", "方案三(装扮3)", radioGroup: "yjhz"),
            .init("rb_yjhz_4", "方案四(装扮4)", radioGroup: "yjhz"),
            .init("rb_yjhz_5", "方案五(装扮5)", radioGroup: "yjhz"),
            .init("cb_yjhz_xp", "同时执行星盘换装"),
        ]),
    ]

    static var defaultMap: [String: Bool] {
        var map: [String: Bool] = [:]
        for sec in sections {
            for item in sec.items where item.kind == .check {
                map[item.key] = item.default
            }
        }
        return map
    }

    static let bucketNames = ["全部", "冲分", "代玩", "任务", "领奖", "更多"]

    static func matchesBucket(_ section: SettingSection, _ bucket: String) -> Bool {
        switch bucket {
        case "冲分": return section.title.contains("冲活跃")
        case "代玩": return section.title.contains("自动代玩") || section.title.contains("批量斗友")
        case "任务": return section.title.contains("任务")
        case "领奖": return section.title.contains("领奖")
        case "更多":
            return section.title.contains("更多")
                || section.title.contains("监听")
                || section.title.contains("星盘")
                || section.title.contains("魂珠")
                || section.title.contains("换装")
                || section.title.contains("打铁")
                || section.title.contains("背包")
        default: return true
        }
    }
}
