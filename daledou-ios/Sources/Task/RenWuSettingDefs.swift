import Foundation

/// 真源：`SettingPageDefs.renWu`（精简：轮询用得上的勾选 + 修炼/供奉/押镖）。
enum RenWuSettingDefs {
    static let feature = "renwu"

    static let sections: [SettingSection] = [
        SettingSection(title: "轮询总开关", items: [
            .init("cb_rw_rc", "日常任务", true),
            .init("cb_rw_bp", "帮派任务", true),
            .init("cb_rw_mp", "门派任务", true),
        ]),
        SettingSection(title: "游记任务", items: [
            .init("cb_youji_1", "任务积分"),
            .init("cb_youji_2", "任务奖励"),
            .init("cb_youji_3", "积分换传功"),
        ]),
        SettingSection(title: "刷新门派任务", items: [
            .init("cb_menpai_shuaxin", "30斗豆刷新门徒委派"),
        ]),
        SettingSection(title: "门派心法", items: [
            .init("rb_mp_xf_jc", "基础心法", true, radioGroup: "mpxf"),
            .init("rb_mp_xf_sc", "上层心法", radioGroup: "mpxf"),
            .init("rb_mp_sl", "少林", true, radioGroup: "mp"),
            .init("rb_mp_em", "峨眉", radioGroup: "mp"),
            .init("rb_mp_hs", "华山", radioGroup: "mp"),
            .init("rb_mp_gb", "丐帮", radioGroup: "mp"),
            .init("rb_mp_wd", "武当", radioGroup: "mp"),
            .init("rb_mp_mz", "明教", radioGroup: "mp"),
        ]),
        SettingSection(title: "帮派修炼", items: [
            .init("rg_bp_xl_1", "紫霞秘籍", true, radioGroup: "bpxl"),
            .init("rg_bp_xl_2", "逍遥心法", radioGroup: "bpxl"),
            .init("rg_bp_xl_3", "铁砂掌", radioGroup: "bpxl"),
            .init("rg_bp_xl_4", "真元护体", radioGroup: "bpxl"),
            .init("rg_bp_xl_5", "九阳神功", radioGroup: "bpxl"),
            .init("rg_bp_xl_6", "金钟罩", radioGroup: "bpxl"),
            .init("rg_bp_xl_7", "北冥神功", radioGroup: "bpxl"),
            .init("rg_bp_xl_8", "乾坤大挪移", radioGroup: "bpxl"),
            .init("rg_bp_xl_9", "养生之道", radioGroup: "bpxl"),
        ]),
        SettingSection(title: "帮派供奉", items: [
            .init("rg_bp_gf_1", "被动经验药水", true, radioGroup: "bpgf"),
            .init("rg_bp_gf_2", "还魂丹", radioGroup: "bpgf"),
            .init("rg_bp_gf_3", "神来拳套", radioGroup: "bpgf"),
            .init("rg_bp_gf_4", "奥秘元素", radioGroup: "bpgf"),
            .init("rg_bp_gf_5", "黄金卷轴", radioGroup: "bpgf"),
            .init("rg_bp_gf_6", "经验药水", radioGroup: "bpgf"),
            .init("rg_bp_gf_7", "五级幸运石", radioGroup: "bpgf"),
            .init("rg_bp_gf_8", "神将碎片宝箱", radioGroup: "bpgf"),
            .init("rg_bp_gf_9", "百炼钢", radioGroup: "bpgf"),
            .init("rg_bp_gf_10", "奔流气息", radioGroup: "bpgf"),
            .init("rg_bp_gf_11", "神秘精华", radioGroup: "bpgf"),
            .init("rg_bp_gf_12", "俊猴王7天", radioGroup: "bpgf"),
            .init("rg_bp_gf_13", "四级幸运石", radioGroup: "bpgf"),
        ]),
        SettingSection(title: "护送押镖", items: [
            .init("cb_hy_yb_1", "温良恭", true),
            .init("cb_hy_yb_2", "吕青橙", true),
            .init("cb_hy_yb_3", "蔡八斗"),
            .init("cb_hy_yb_s", "刷不到温良恭就压老板娘"),
        ]),
        SettingSection(title: "铭刻 / 徽章 / 商店", items: [
            .init("ed_renwu_mk", "铭刻强化完整URL", kind: .text),
            .init("ed_renwu_huizhang_id", "徽章achievement_id", kind: .text),
            .init("ed_hy_sf", "商店消费URL", kind: .text),
            .init("ed_hy_sf_num", "购买次数", kind: .text),
            .init("ed_hy_zz", "助阵完整URL", kind: .text),
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

final class RenWuStore {
    static let shared = RenWuStore()
    static let feature = RenWuSettingDefs.feature
    private let toggles = FeatureToggleStore.shared
    private let defaultsKey = "_defaults_applied_ios_v1"

    private init() { ensureDefaults() }

    func on(_ key: String, default def: Bool? = nil) -> Bool {
        let d = def ?? RenWuSettingDefs.defaultMap[key] ?? false
        return toggles.getBool(Self.feature, key, default: d)
    }

    func set(_ key: String, _ checked: Bool) {
        toggles.setBool(Self.feature, key, checked)
    }

    func text(_ key: String, default def: String = "") -> String {
        toggles.getString(Self.feature, key, default: def)
    }

    func setText(_ key: String, _ value: String) {
        toggles.setString(Self.feature, key, value)
    }

    func radioIndex(_ keys: [String], defaultIndex: Int = 0) -> Int {
        let i = keys.firstIndex(where: { on($0) })
        return i ?? defaultIndex
    }

    private func ensureDefaults() {
        guard !toggles.getBool(Self.feature, defaultsKey, default: false) else { return }
        for (key, def) in RenWuSettingDefs.defaultMap where def {
            if toggles.objectExists(Self.feature, key) { continue }
            toggles.setBool(Self.feature, key, true)
        }
        toggles.setBool(Self.feature, defaultsKey, true)
    }
}
