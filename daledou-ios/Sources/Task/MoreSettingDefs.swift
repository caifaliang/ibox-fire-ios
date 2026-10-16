import Foundation

/// 真源：`SettingPageDefs.more` 精简版 — 悬浮窗「更多」CGI 实际读取的键。
enum MoreSettingDefs {
    static let feature = "more_settings"

    static let sections: [SettingSection] = [
        SettingSection(title: "祭坛", items: [
            .init("cb_jitan_fufei", "使用转转券"),
        ]),
        SettingSection(title: "开锦囊", items: [
            .init("cb_jn_jn", "扫锦囊页使用", true),
            .init("cb_jn_zzjn", "至尊锦囊"),
            .init("cb_jn_jqjn", "惊奇锦囊"),
            .init("cb_jn_jxjn", "觉醒锦囊"),
            .init("cb_jn_lslb", "炼神礼包"),
        ]),
        SettingSection(title: "仙武修真", items: [
            .init("rg_xwxz_1", "力量山", true, radioGroup: "xwxz"),
            .init("rg_xwxz_2", "敏捷山", radioGroup: "xwxz"),
            .init("rg_xwxz_3", "速度山", radioGroup: "xwxz"),
            .init("cb_xwxz_auto", "按爆率自动选山"),
            .init("cb_xwxz_auto_shuaxin", "免费刷新"),
        ]),
        SettingSection(title: "武器充能", items: [
            .init("cb_wqcn_lsg", "龙舌弓"),
            .init("cb_wqcn_xyj", "轩辕剑"),
            .init("cb_wqcn_jgb", "金箍棒"),
            .init("cb_wqcn_xtcs", "玄铁磁石"),
            .init("cb_wqcn_pjp", "啤酒瓶"),
            .init("cb_wqcn_hta", "黑桃A"),
            .init("cb_wqcn_xhz", "绣花针"),
            .init("cb_wqcn_ldqt", "乐斗拳套"),
        ]),
        SettingSection(title: "遗迹征伐", items: [
            .init("cb_yjzf_1", "异兽洞穴"),
            .init("cb_yjzf_auto", "洞穴自动多层"),
            .init("cb_yjzf_2", "联合征伐-每日", true),
            .init("cb_yjzf_3", "联合征伐-周四窗"),
        ]),
        SettingSection(title: "五行夺宝", items: [
            .init("rb_wx_db_1", "沙漠", true, radioGroup: "wx_db"),
            .init("rb_wx_db_2", "海底", radioGroup: "wx_db"),
            .init("rb_wx_db_3", "密林", radioGroup: "wx_db"),
            .init("rb_wx_db_4", "太空", radioGroup: "wx_db"),
        ]),
        SettingSection(title: "打造符石", items: [
            .init("cb_fs_1", "分解/合成1级"),
            .init("cb_fs_2", "分解/合成2级"),
        ]),
        SettingSection(title: "长梦副本", items: [
            .init("cb_fb_count_1", "只刷一次", true),
            .init("cb_fb_count_max", "刷完单副本"),
            .init("cb_fb_max_all", "刷完所有副本"),
            .init("rb_fb_type_2", "优先奇遇(默认优先战斗)"),
            .init("rb_fb_zhan_bai_2", "战败后重开(默认停)"),
        ]),
        SettingSection(title: "帮派远征战力", items: [
            .init("ed_bpyz_zl_min", "战力下限", kind: .text),
            .init("ed_bpyz_zl_max", "战力上限", kind: .text),
        ]),
        SettingSection(title: "黄金联赛战力", items: [
            .init("ed_hjls_zl_min", "战力下限", kind: .text),
            .init("ed_hjls_zl_max", "战力上限", kind: .text),
        ]),
        SettingSection(title: "梦想之旅", items: [
            .init("ed_mxzl_min", "补机票最少完成数(默认5)", kind: .text),
        ]),
        SettingSection(title: "新春对联答案", items: [
            .init("ed_xcdl_answers", "每行：关键字|答案", kind: .text),
        ]),
        SettingSection(title: "遗迹商店", items: [
            .init("cb_yjsd_4", "商品4"),
            .init("cb_yjsd_1", "商品1"),
            .init("cb_yjsd_2", "商品2"),
            .init("cb_yjsd_3", "商品3"),
            .init("cb_yjsd_8", "商品8"),
            .init("cb_yjsd_5", "商品5"),
            .init("cb_yjsd_6", "商品6"),
            .init("cb_yjsd_7", "商品7"),
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

final class MoreStore {
    static let shared = MoreStore()
    static let feature = MoreSettingDefs.feature
    private let toggles = FeatureToggleStore.shared
    private let defaultsKey = "_defaults_applied_ios_v1"

    private init() { ensureDefaults() }

    func on(_ key: String) -> Bool {
        let def = MoreSettingDefs.defaultMap[key] ?? false
        return toggles.getBool(Self.feature, key, default: def)
    }

    func set(_ key: String, _ checked: Bool) {
        toggles.setBool(Self.feature, key, checked)
    }

    func text(_ key: String) -> String {
        toggles.getString(Self.feature, key)
    }

    func setText(_ key: String, _ value: String) {
        toggles.setString(Self.feature, key, value)
    }

    private func ensureDefaults() {
        guard !toggles.getBool(Self.feature, defaultsKey, default: false) else { return }
        for (key, def) in MoreSettingDefs.defaultMap where def {
            if toggles.objectExists(Self.feature, key) { continue }
            toggles.setBool(Self.feature, key, true)
        }
        toggles.setBool(Self.feature, defaultsKey, true)
    }
}
