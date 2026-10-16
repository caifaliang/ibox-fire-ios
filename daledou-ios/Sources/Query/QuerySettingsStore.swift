import Foundation

/// 对齐参考 SearchSettingDataBean / 查询设置。
/// 默认：不显示技能（与参考 App 一致）；其余与参考 bean 默认一致。
struct QueryDisplaySettings: Equatable {
    var showYongBingAll: Bool
    var showStqb: Bool
    var showJiNeng: Bool
    var showZhuanJing: Bool
    var showWuQiFuShi: Bool
    var showHuiZhang: Bool
    var showShenZhuang: Bool
    var showTeShuJiNeng: Bool
    var showYongBingTianFu: Bool
    var showYongBingZhuZhen: Bool
    var showJingMai: Bool

    init(
        showYongBingAll: Bool = true,
        showStqb: Bool = true,
        showJiNeng: Bool = false,
        showZhuanJing: Bool = true,
        showWuQiFuShi: Bool = true,
        showHuiZhang: Bool = true,
        showShenZhuang: Bool = true,
        showTeShuJiNeng: Bool = true,
        showYongBingTianFu: Bool = true,
        showYongBingZhuZhen: Bool = true,
        showJingMai: Bool = true
    ) {
        self.showYongBingAll = showYongBingAll
        self.showStqb = showStqb
        self.showJiNeng = showJiNeng
        self.showZhuanJing = showZhuanJing
        self.showWuQiFuShi = showWuQiFuShi
        self.showHuiZhang = showHuiZhang
        self.showShenZhuang = showShenZhuang
        self.showTeShuJiNeng = showTeShuJiNeng
        self.showYongBingTianFu = showYongBingTianFu
        self.showYongBingZhuZhen = showYongBingZhuZhen
        self.showJingMai = showJingMai
    }
}

final class QuerySettingsStore {
    static let shared = QuerySettingsStore()

    private let prefs: UserDefaults

    private init() {
        prefs = UserDefaults(suiteName: Self.prefsName) ?? .standard
    }

    func load() -> QueryDisplaySettings {
        QueryDisplaySettings(
            showYongBingAll: prefs.object(forKey: Self.keyYbAll) as? Bool ?? true,
            showStqb: prefs.object(forKey: Self.keyStqb) as? Bool ?? true,
            showJiNeng: prefs.object(forKey: Self.keyJineng) as? Bool ?? false,
            showZhuanJing: prefs.object(forKey: Self.keyZj) as? Bool ?? true,
            showWuQiFuShi: prefs.object(forKey: Self.keyFushi) as? Bool ?? true,
            showHuiZhang: prefs.object(forKey: Self.keyHz) as? Bool ?? true,
            showShenZhuang: prefs.object(forKey: Self.keySz) as? Bool ?? true,
            showTeShuJiNeng: prefs.object(forKey: Self.keyTeshu) as? Bool ?? true,
            showYongBingTianFu: prefs.object(forKey: Self.keyYbTf) as? Bool ?? true,
            showYongBingZhuZhen: prefs.object(forKey: Self.keyYbZz) as? Bool ?? true,
            showJingMai: prefs.object(forKey: Self.keyJm) as? Bool ?? true
        )
    }

    func save(_ s: QueryDisplaySettings) {
        prefs.set(s.showYongBingAll, forKey: Self.keyYbAll)
        prefs.set(s.showStqb, forKey: Self.keyStqb)
        prefs.set(s.showJiNeng, forKey: Self.keyJineng)
        prefs.set(s.showZhuanJing, forKey: Self.keyZj)
        prefs.set(s.showWuQiFuShi, forKey: Self.keyFushi)
        prefs.set(s.showHuiZhang, forKey: Self.keyHz)
        prefs.set(s.showShenZhuang, forKey: Self.keySz)
        prefs.set(s.showTeShuJiNeng, forKey: Self.keyTeshu)
        prefs.set(s.showYongBingTianFu, forKey: Self.keyYbTf)
        prefs.set(s.showYongBingZhuZhen, forKey: Self.keyYbZz)
        prefs.set(s.showJingMai, forKey: Self.keyJm)
    }

    private static let prefsName = "daledou_query_display"
    private static let keyYbAll = "show_yb_all"
    private static let keyStqb = "show_stqb"
    private static let keyJineng = "show_jineng"
    private static let keyZj = "show_zj"
    private static let keyFushi = "show_fushi"
    private static let keyHz = "show_hz"
    private static let keySz = "show_sz"
    private static let keyTeshu = "show_teshu"
    private static let keyYbTf = "show_yb_tf"
    private static let keyYbZz = "show_yb_zz"
    private static let keyJm = "show_jm"
}
