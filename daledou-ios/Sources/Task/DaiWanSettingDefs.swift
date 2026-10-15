import Foundation

/// 真源：`SettingPageDefs.daiWan`（历练/画卷/12宫/幻境/Boss/会武/门派/巅峰细项）。
enum DaiWanSettingDefs {
    static let sections: [SettingSection] = [
        SettingSection(title: "历练设置", items: [
            .init("rg_lilian_tianfu", "优先天赋丹", radioGroup: "lilian_mode"),
            .init("cb_lilian_xiaobao", "优先小宝"),
            .init("rg_lilian_tianshu", "优先阅历", radioGroup: "lilian_mode"),
            .init("rg_lilian_diy", "自定义顺序", radioGroup: "lilian_mode"),
            .init("cb_lilian_auto", "自动活力（推荐）"),
            .init("rg_lilian_da", "大活力", radioGroup: "lilian_huoli"),
            .init("rg_lilian_xiao", "小活力", radioGroup: "lilian_huoli"),
        ]),
        SettingSection(title: "画卷迷踪设置", items: [
            .init("cb_huajuan_fufei", "使用付费次数", radioGroup: "huajuan"),
            .init("cb_huajuan_mianfei", "不付费", radioGroup: "huajuan"),
        ]),
        SettingSection(title: "12宫设置", items: [
            .init("rb_12gong_sao", "免费扫荡", radioGroup: "gong12"),
            .init("rb_12gong_dan", "不扫荡", radioGroup: "gong12"),
        ]),
        SettingSection(title: "幻境设置", items: [
            .init("rb_huanjing_dao1", "打最后关卡", radioGroup: "huanjing"),
            .init("rb_huanjing_dao2", "打倒数第二", radioGroup: "huanjing"),
        ]),
        SettingSection(title: "乐斗boss设置", items: [
            .init("cb_boss_haoyou", "好友"),
            .init("cb_boss_bangpai", "帮派"),
            .init("cb_boss_xiabai", "侠拜"),
            .init("cb_boss_tili", "自动体力"),
            .init("cb_boss_gongxian", "自动贡献"),
        ]),
        SettingSection(title: "会武设置", items: [
            .init("rb_huiwu_mianfi", "打免费", true, radioGroup: "huiwu"),
            .init("rb_huiwu_fufei", "打付费", radioGroup: "huiwu"),
            .init("cb_huiwu_huanshu", "自动换1试炼书"),
        ]),
        SettingSection(title: "门派设置", items: [
            .init("cb_menpai_xianglu", "普通香炉"),
            .init("cb_menpai_xianglu_gaoji", "高级香炉"),
            .init("cb_menpai_xianglu_gaoji_huan", "换高香"),
            .init("cb_menpai_muzhuang", "木桩"),
            .init("cb_menpai_qiecuo", "同门切磋(免费打完)"),
            .init("cb_menpai_qiecuo_1", "同门切磋(耗战书打满)"),
            .init("cb_menpai_qiecuo_huan", "战书不足时自动换1本"),
            .init("cb_menpai_qiecuo_boss", "一键切磋所有门派boss"),
            .init("cb_menpai_yaoqingsai", "打邀请赛"),
            .init("cb_menpai_yaoqingsai_huan", "次数打满"),
            .init("cb_menpai_yaoqingsai_zhouri", "周日不打"),
        ]),
        SettingSection(title: "巅峰(后台)设置", items: [
            .init("rb_dianfeng_suiji", "随机", true, radioGroup: "dianfeng"),
            .init("rb_dianfeng_1", "1线", radioGroup: "dianfeng"),
            .init("rb_dianfeng_2", "2线", radioGroup: "dianfeng"),
            .init("rb_dianfeng_3", "3线", radioGroup: "dianfeng"),
        ]),
    ]

    static var defaultMap: [String: Bool] {
        var m: [String: Bool] = [:]
        for sec in sections {
            for item in sec.items where item.kind == .check {
                m[item.key] = item.default
            }
        }
        return m
    }
}

final class DaiWanStore {
    static let shared = DaiWanStore()
    static let feature = "daiwan"
    private let toggles = FeatureToggleStore.shared
    private let defaultsKey = "_defaults_applied_ios_v1"

    private init() { ensureDefaults() }

    func on(_ key: String) -> Bool {
        let def = DaiWanSettingDefs.defaultMap[key] ?? false
        return toggles.getBool(Self.feature, key, default: def)
    }

    func set(_ key: String, _ checked: Bool) {
        toggles.setBool(Self.feature, key, checked)
    }

    private func ensureDefaults() {
        guard !toggles.getBool(Self.feature, defaultsKey, default: false) else { return }
        for (key, def) in DaiWanSettingDefs.defaultMap where def {
            if toggles.objectExists(Self.feature, key) { continue }
            toggles.setBool(Self.feature, key, true)
        }
        toggles.setBool(Self.feature, defaultsKey, true)
    }
}
