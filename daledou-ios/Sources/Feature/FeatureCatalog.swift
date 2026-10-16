import Foundation

/// 真源：`F:\DaLedou_App_Dev\daledou\...\FeatureCatalog.kt`（标签一字不差）。
enum MenuSection: String, CaseIterable, Identifiable {
    case background
    case settings
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .background: return "后台"
        case .settings: return "设置相关"
        case .more: return "更多"
        }
    }

    var subtitle: String? {
        switch self {
        case .background: return "(日志页可查看设置后台权限方法)"
        case .settings, .more: return nil
        }
    }
}

struct FeatureItem: Identifiable, Hashable {
    let id: String
    let label: String
    let pageTitle: String
    let section: MenuSection
    let emphasize: Bool
    let wide: Bool
    /// iOS 是否已接线（与 APK Ready 无关；未接线点击只提示）
    let iosWired: Bool

    init(
        id: String,
        label: String,
        section: MenuSection,
        pageTitle: String? = nil,
        emphasize: Bool = false,
        wide: Bool = false,
        iosWired: Bool = false
    ) {
        self.id = id
        self.label = label
        self.pageTitle = pageTitle ?? label
        self.section = section
        self.emphasize = emphasize
        self.wide = wide
        self.iosWired = iosWired
    }
}

enum FeatureCatalog {
    /// APK 当前 topActions 为空
    static let topActions: [String] = []

    static let items: [FeatureItem] = [
        // —— 后台 ——
        .init(id: "hejiu", label: "喝酒", section: .background, iosWired: true),
        .init(id: "jiebiao", label: "劫镖", section: .background, iosWired: true),
        .init(id: "kuangdong", label: "矿洞", section: .background, iosWired: true),
        .init(id: "liangcao", label: "粮草", section: .background, pageTitle: "粮草掠夺", iosWired: true),
        .init(id: "wending", label: "问鼎", section: .background, iosWired: true),
        .init(id: "fuchou_wending", label: "复仇问鼎", section: .background, pageTitle: "问鼎复仇", iosWired: true),
        .init(id: "open_kd", label: "开启矿洞", section: .background, pageTitle: "开矿洞设置", iosWired: true),
        .init(id: "change_guard", label: "更换守护", section: .background, pageTitle: "换守护神设置", iosWired: true),
        .init(id: "paiqian", label: "任务派遣", section: .background, iosWired: true),
        .init(id: "menpai_shouye", label: "门派守夜", section: .background, iosWired: true),
        .init(id: "friend_mgmt", label: "好友管理", section: .background, iosWired: true),
        .init(id: "xkx", label: "侠客行", section: .background, iosWired: true),
        .init(
            id: "diy_auto_daiwan",
            label: "付费用户专属 【定时自定义代玩】",
            section: .background,
            pageTitle: "定时自定义代玩",
            emphasize: true,
            wide: true,
            iosWired: true
        ),
        .init(
            id: "diy_task",
            label: "免费高阶玩法 【定时自定义任务】",
            section: .background,
            pageTitle: "定时自定义任务",
            wide: true,
            iosWired: true
        ),

        // —— 设置相关 ——
        .init(id: "huoyue", label: "活跃代玩", section: .settings, pageTitle: "活跃代玩", iosWired: true),
        .init(id: "daiwan", label: "代玩", section: .settings, pageTitle: "代玩设置(下滑更多)", iosWired: true),
        .init(id: "lingjiang", label: "领奖报名", section: .settings, pageTitle: "自动领奖报名设置(下滑更多)", iosWired: true),
        .init(id: "renwu", label: "任务", section: .settings, pageTitle: "任务设置(下滑更多)"),
        .init(id: "paomadeng", label: "跑马灯", section: .settings, pageTitle: "跑马灯设置"),
        .init(id: "more_settings", label: "更多", section: .settings, pageTitle: "更多设置(下滑更多)", iosWired: true),

        // —— 更多 ——
        .init(id: "huanzhuang", label: "换装", section: .more, pageTitle: "换装", iosWired: true),
        .init(id: "zidong_qianghua", label: "自动强化", section: .more, pageTitle: "自动强化", iosWired: true),
        .init(id: "beibao", label: "背包查询", section: .more, iosWired: true),
        .init(id: "chaqu", label: "武林查区", section: .more, pageTitle: "查区", iosWired: true),
        .init(id: "daiwan_ui", label: "代玩界面", section: .more, pageTitle: "代玩-记录", iosWired: true),
        .init(id: "piliang_douyou", label: "批量斗友", section: .more, iosWired: true),
        .init(id: "doudou_mall", label: "斗豆商城", section: .more, pageTitle: "斗豆红包商城", iosWired: true),
        .init(id: "xianshi_qianggou", label: "限时抢购", section: .more, pageTitle: "限时抢购", iosWired: true),
        .init(id: "longhuang", label: "龙凰论武", section: .more, iosWired: true),
        .init(id: "bagua", label: "八卦迷阵", section: .more, iosWired: true),
        .init(id: "xydb", label: "幸运夺宝", section: .more, iosWired: true),
        .init(id: "wulin_chiyao", label: "武林吃药", section: .more, iosWired: true),
        .init(id: "qiangdipan", label: "抢地盘", section: .more, iosWired: true),
        .init(id: "qunxia_luxiang", label: "群侠录像", section: .more, iosWired: true),
        .init(id: "pc_game", label: "PC端", section: .more),
        .init(id: "bangpai_wakuang", label: "帮派挖矿", section: .more, emphasize: true, iosWired: true),
        .init(id: "shuqian", label: "书签", section: .more, pageTitle: "书签", iosWired: true),
        .init(id: "account_switch", label: "账号切换", section: .more, iosWired: true),
        .init(id: "about", label: "关于大乐斗", section: .more, emphasize: true, iosWired: true),
        .init(id: "join_qq_group", label: "加入群聊", section: .more, emphasize: true, iosWired: true),
        .init(id: "scan_login", label: "扫码登陆", section: .more, emphasize: true, iosWired: true),
        .init(id: "one_login", label: "一键登陆", section: .more, emphasize: true, iosWired: true),
        .init(id: "logout", label: "退出登陆", section: .more, emphasize: true, iosWired: true),
        .init(id: "exit_app", label: "退出大乐斗", section: .more, emphasize: true, iosWired: true),
        .init(id: "note_settings", label: "大乐斗会员", section: .more, pageTitle: "大乐斗会员", emphasize: true),
    ]

    static func items(in section: MenuSection) -> [FeatureItem] {
        items.filter { $0.section == section }
    }

    static func item(id: String) -> FeatureItem? {
        items.first { $0.id == id }
    }
}

/// 真源：`ShellCatalog.kt` —— 「我的」入口
enum ShellCatalog {
    struct HubEntry: Identifiable, Hashable {
        var id: String { featureId }
        let featureId: String
        let label: String
        let section: String
    }

    static let mine: [HubEntry] = [
        .init(featureId: "one_login", label: "一键登陆", section: "账号"),
        .init(featureId: "scan_login", label: "扫码登陆", section: "账号"),
        .init(featureId: "account_switch", label: "账号切换", section: "账号"),
        .init(featureId: "logout", label: "退出登陆", section: "账号"),
        .init(featureId: "note_settings", label: "会员", section: "关于"),
        .init(featureId: "about", label: "关于大乐斗", section: "关于"),
        .init(featureId: "join_qq_group", label: "加入群聊", section: "关于"),
        .init(featureId: "exit_app", label: "退出大乐斗", section: "关于"),
    ]
}
