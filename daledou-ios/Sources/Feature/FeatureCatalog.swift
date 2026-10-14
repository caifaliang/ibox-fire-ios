import Foundation

/// 对齐 Android `FeatureCatalog`：菜单真源（标签一字不差）。本切片只做入口与路由，Worker 另开。
enum FeaturePortStatus: String {
    case ready
    case partial
    case upcoming
}

enum FeatureMenuSection: String, CaseIterable, Identifiable {
    case background = "后台任务"
    case settings = "设置相关"
    case more = "更多"

    var id: String { rawValue }

    var subtitle: String? {
        switch self {
        case .background: return "(后台脚本将按模块接入)"
        case .settings, .more: return nil
        }
    }
}

struct FeatureItem: Identifiable, Hashable {
    let id: String
    let label: String
    let pageTitle: String
    let section: FeatureMenuSection
    let portStatus: FeaturePortStatus
    let emphasize: Bool

    init(
        id: String,
        label: String,
        section: FeatureMenuSection,
        pageTitle: String? = nil,
        portStatus: FeaturePortStatus = .upcoming,
        emphasize: Bool = false
    ) {
        self.id = id
        self.label = label
        self.pageTitle = pageTitle ?? label
        self.section = section
        self.portStatus = portStatus
        self.emphasize = emphasize
    }
}

enum FeatureCatalog {
    static let topActions = ["帮助", "截图", "查询"]

    static let items: [FeatureItem] = [
        // —— 后台任务 ——
        .init(id: "hejiu", label: "喝酒", section: .background),
        .init(id: "jiebiao", label: "劫镖", section: .background),
        .init(id: "kuangdong", label: "矿洞", section: .background),
        .init(id: "liangcao", label: "粮草", section: .background, pageTitle: "粮草掠夺"),
        .init(id: "wending", label: "问鼎", section: .background),
        .init(id: "fuchou_wending", label: "复仇问鼎", section: .background, pageTitle: "问鼎复仇"),
        .init(id: "open_kd", label: "开启矿洞", section: .background, pageTitle: "开矿洞设置"),
        .init(id: "change_guard", label: "更换守护", section: .background, pageTitle: "换守护神设置"),
        .init(id: "paiqian", label: "任务派遣", section: .background),
        .init(id: "menpai_shouye", label: "门派守夜", section: .background),
        .init(id: "friend_mgmt", label: "好友管理", section: .background),
        .init(id: "xkx", label: "侠客行", section: .background),
        .init(
            id: "diy_auto_daiwan",
            label: "付费用户专属 【定时自定义代玩】",
            section: .background,
            pageTitle: "定时自定义代玩",
            emphasize: true
        ),
        .init(
            id: "diy_task",
            label: "免费高阶玩法 【定时自定义任务】",
            section: .background,
            pageTitle: "定时自定义任务"
        ),

        // —— 设置相关 ——
        .init(id: "huoyue", label: "活跃代玩", section: .settings, pageTitle: "活跃代玩"),
        .init(id: "daiwan", label: "代玩", section: .settings, pageTitle: "代玩设置(下滑更多)"),
        .init(id: "lingjiang", label: "领奖报名", section: .settings, pageTitle: "自动领奖报名设置(下滑更多)"),
        .init(id: "renwu", label: "任务", section: .settings, pageTitle: "任务设置(下滑更多)"),
        .init(id: "paomadeng", label: "跑马灯", section: .settings, pageTitle: "跑马灯设置"),
        .init(id: "more_settings", label: "更多", section: .settings, pageTitle: "更多设置(下滑更多)"),

        // —— 更多 ——
        .init(id: "chaqu", label: "武林查区", section: .more, pageTitle: "查区"),
        .init(id: "daiwan_ui", label: "代玩界面", section: .more, pageTitle: "代玩-记录"),
        .init(id: "piliang_douyou", label: "批量斗友", section: .more),
        .init(id: "doudou_mall", label: "斗豆商城", section: .more, pageTitle: "斗豆红包商城"),
        .init(id: "xianshi_qianggou", label: "限时抢购", section: .more),
        .init(id: "longhuang", label: "龙凰论武", section: .more),
        .init(id: "bagua", label: "八卦迷阵", section: .more),
        .init(id: "xydb", label: "幸运夺宝", section: .more),
        .init(id: "wulin_chiyao", label: "武林吃药", section: .more),
        .init(id: "qiangdipan", label: "抢地盘", section: .more),
        .init(id: "beibao", label: "背包查询", section: .more),
        .init(id: "qunxia_luxiang", label: "群侠录像", section: .more, portStatus: .partial),
        .init(id: "bangpai_wakuang", label: "帮派挖矿", section: .more, emphasize: true),
        .init(id: "shuqian", label: "书签", section: .more),
        .init(id: "account_switch", label: "账号切换", section: .more, portStatus: .ready),
        .init(id: "about", label: "关于大乐斗", section: .more, emphasize: true),
        .init(id: "scan_login", label: "扫码登陆", section: .more, portStatus: .ready, emphasize: true),
        .init(id: "one_login", label: "一键登陆", section: .more, portStatus: .ready, emphasize: true),
        .init(id: "logout", label: "退出登陆", section: .more, portStatus: .ready, emphasize: true),
        .init(id: "exit_app", label: "退出大乐斗", section: .more, portStatus: .partial, emphasize: true),
        .init(id: "note_settings", label: "大乐斗会员", section: .more, pageTitle: "大乐斗会员", emphasize: true),
    ]

    static func items(in section: FeatureMenuSection) -> [FeatureItem] {
        items.filter { $0.section == section }
    }

    static func item(id: String) -> FeatureItem? {
        items.first { $0.id == id }
    }
}
