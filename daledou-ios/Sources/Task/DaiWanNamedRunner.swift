import Foundation

/// 真源：`DaiWanWorkers.executeByName` — 悬浮窗「代玩-记录」按钮中文名 → 已有 CGI。
@MainActor
final class DaiWanNamedRunner: ObservableObject {
    static let shared = DaiWanNamedRunner()

    @Published private(set) var running = false
    @Published private(set) var activeName: String?
    private var job: Task<Void, Never>?

    private init() {}

    func stop() {
        job?.cancel()
        job = nil
        running = false
        activeName = nil
        TaskLogStore.shared.setRunning(false)
        TaskLogStore.shared.append("代玩", "已停止")
    }

    func run(_ action: String) {
        let name = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // 一键转交现有 Runner（可与单任务互斥：一键优先）
        if name.contains("一键活跃") {
            HuoYueRunner.shared.start(cookie: SessionStore.shared.cookieHeader)
            return
        }
        if name.contains("一键领奖") {
            LingJiangRunner.shared.start(cookie: SessionStore.shared.cookieHeader)
            return
        }

        guard !running else {
            TaskLogStore.shared.append(name, "已有任务在跑：\(activeName ?? "")")
            return
        }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            TaskLogStore.shared.append(name, "请先登录")
            return
        }

        job = Task { await execute(name, cookie: cookie) }
    }

    private func execute(_ name: String, cookie: String) async {
        running = true
        activeName = name
        TaskLogStore.shared.setRunning(true, name: name)
        defer {
            running = false
            activeName = nil
            TaskLogStore.shared.setRunning(false)
            job = nil
        }
        TaskLogStore.shared.append(name, "点击触发")
        let live: (String) -> Void = { line in
            Task { @MainActor in TaskLogStore.shared.append(name, line) }
        }
        let msg = await dispatch(name, cookie: cookie, onLog: live)
        if Task.isCancelled { return }
        if !msg.isEmpty {
            TaskLogStore.shared.append(name, msg)
        }
    }

    private func dispatch(
        _ name: String,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        // 后台监听类：打开对应设置页由 UI 处理；这里直接跑一轮 CGI
        switch name {
        case "历练":
            return await HuoYueCombat.farmLilian(cookie: cookie, onLog: onLog)
        case "反向历练":
            return await HuoYueCombat.farmLilian(cookie: cookie, reverse: true, onLog: onLog)
        case "画卷":
            return await HuoYueCombat.farmHuaJuan(cookie: cookie, onLog: onLog)
        case "12宫":
            return await HuoYueCombat.farmGong12(cookie: cookie, onLog: onLog)
        case "幻境":
            return await HuoYueCombat.farmHuanJing(cookie: cookie, onLog: onLog)
        case "Boss":
            return await HuoYueCombat.farmBoss(cookie: cookie, onLog: onLog)
        case "会武":
            return await HuoYueCombat.farmHuiWu(cookie: cookie, onLog: onLog)
        case "门派":
            return await HuoYueCombat.farmMenPai(cookie: cookie, onLog: onLog)
        case "巅峰(后台)", "巅峰":
            return await HuoYueCombat.farmDianFeng(cookie: cookie, onLog: onLog)
        case "竞技场":
            return await HuoYueCombat.farmJingJiChang(cookie: cookie, onLog: onLog)
        case "华山论剑":
            return await HuoYueCombat.farmHuaShan(cookie: cookie, onLog: onLog)
        case "深渊秘境":
            return await HuoYueCombat.farmShenYuan(cookie: cookie, onLog: onLog)
        case "打满问鼎":
            return await HuoYueCombat.farmWenDing(cookie: cookie, onLog: onLog)
        case "斗神塔(后台)", "斗神塔":
            return await HuoYueCombat.farmDouShenTa(cookie: cookie, onLog: onLog)
        case "抢地盘":
            return await HuoYueCombat.farmQiangDiPan(cookie: cookie, onLog: onLog)
        case "日常任务":
            let (_, b) = await LedouCGI.getPhonePk(cmd: "task", extra: ["sub": "7"], cookie: cookie)
            return LedouCGI.shortBody(b, code: 200)
        case "帮派任务":
            let (_, b) = await LedouCGI.getPhonePk(cmd: "factiontask", extra: ["sub": "1"], cookie: cookie)
            return LedouCGI.shortBody(b, code: 200)
        case "门派任务":
            let (_, b) = await LedouCGI.getPhonePk(cmd: "sect_task", cookie: cookie)
            return LedouCGI.shortBody(b, code: 200)
        case "矿洞":
            return await DailyListenActions.farmKuangDong(cookie: cookie, onLog: onLog)
        case "劫镖":
            return await DailyListenActions.farmJieBiao(cookie: cookie, onLog: onLog)
        case "粮草":
            return await DailyListenActions.farmLiangCao(cookie: cookie, onLog: onLog)
        case "问鼎":
            return await DailyListenActions.farmWenDingListen(cookie: cookie, onLog: onLog)
        case "问鼎复仇":
            return await DailyListenActions.farmFuChouWenDing(cookie: cookie, onLog: onLog)
        case "开矿洞", "开启矿洞":
            return await DailyListenActions.farmOpenKd(cookie: cookie, onLog: onLog)
        case "换守护", "更换守护":
            return await DailyListenActions.farmChangeGuard(cookie: cookie, onLog: onLog)
        case "矿洞排行":
            return await bangPaiPeek(cmd: "factionmine", pet: true, cookie: cookie, onLog: onLog, title: "矿洞排行")
        case "问鼎帮资", "帮战设置":
            return await bangPaiPeek(
                cmd: "factionhr", extra: ["subtype": "14"], pet: false,
                cookie: cookie, onLog: onLog, title: name
            )
        case "祭坛排行":
            return await bangPaiPeek(
                cmd: "factionop", extra: ["subtype": "8", "pageno": "1", "type": "2"], pet: false,
                cookie: cookie, onLog: onLog, title: "祭坛排行"
            )
        case "踢馆排行":
            return await bangPaiPeek(
                cmd: "fac_challenge", extra: ["subtype": "10"], pet: true,
                cookie: cookie, onLog: onLog, title: "踢馆排行"
            )
        case "问鼎出战":
            return await bangPaiPeek(
                cmd: "factionempire", extra: ["op": "0"], pet: true,
                cookie: cookie, onLog: onLog, title: "问鼎出战"
            )
        case "任务派遣":
            return await DailyListenActions.farmPaiQian(cookie: cookie, onLog: onLog)
        case "群侠":
            return await MoreExtraActions.signupQunXia(cookie: cookie, onLog: onLog)
        case "手机武林":
            return await MoreExtraActions.signupWuLinPhone(cookie: cookie, onLog: onLog)
        case "电脑武林":
            return await MoreExtraActions.signupWuLinPc(cookie: cookie, onLog: onLog)
        case "随机飞升":
            return await MoreExtraActions.signupFeiSheng(cookie: cookie, onLog: onLog)
        case "手机侠侣":
            return await MoreExtraActions.signupXiaLvPhone(cookie: cookie, onLog: onLog)
        case "电脑侠侣":
            return await MoreExtraActions.signupXiaLvPc(cookie: cookie, onLog: onLog)
        case "游记任务":
            return await MoreExtraActions.farmYouJi(cookie: cookie, onLog: onLog)
        case "踢馆":
            return await MoreExtraActions.farmTiGuan(cookie: cookie, onLog: onLog)
        case "祭坛":
            return await MoreExtraActions.farmJiTan(cookie: cookie, onLog: onLog)
        case "开锦囊":
            return await MoreExtraActions.farmKaiJinNang(cookie: cookie, onLog: onLog)
        case "梦想之旅":
            return await MoreExtraActions.farmMengXiangZhiLv(cookie: cookie, onLog: onLog)
        case "仙武修真", "仙武":
            return await MoreExtraActions.farmXianWu(cookie: cookie, onLog: onLog)
        case "武器充能":
            return await MoreExtraActions.farmWuQiChongNeng(cookie: cookie, onLog: onLog)
        case "遗迹征伐":
            return await MoreExtraActions.farmYiJiZhengFa(cookie: cookie, onLog: onLog)
        case "龙吟破阵":
            return await MoreExtraActions.farmLongYin(cookie: cookie, onLog: onLog)
        case "天地宝匣":
            return await MoreExtraActions.farmTianDiBaoXia(cookie: cookie, onLog: onLog)
        case "五行夺宝":
            return await MoreExtraActions.farmWuXing(cookie: cookie, onLog: onLog)
        case "打造符石":
            return await MoreExtraActions.farmDaZaoFuShi(cookie: cookie, onLog: onLog)
        case "遗迹商店兑换":
            return await MoreExtraActions.farmYiJiShangDian(cookie: cookie, onLog: onLog)
        case "帮派远征":
            return await MoreExtraActions.farmBangPaiYuanZheng(cookie: cookie, onLog: onLog)
        case "黄金联赛":
            return await MoreExtraActions.farmHuangJinLianSai(cookie: cookie, onLog: onLog)
        case "长梦副本", "长梦":
            return await MoreExtraActions.farmChangMeng(cookie: cookie, onLog: onLog)
        case "PC解锁", "修改PC锁", "重置PC锁", "设置PC锁密码":
            return await MoreExtraActions.pcSuo(action: name, cookie: cookie, onLog: onLog)
        case "新春对联":
            return await MoreExtraActions.farmXinChunDuiLian(cookie: cookie, onLog: onLog)
        case "掌上道聚城", "道聚城":
            return await MoreExtraActions.farmDaoJuCheng(cookie: cookie, onLog: onLog)
        case "一键自动换装", "换装":
            return await MoreExtraActions.farmYiJianHuanZhuang(onLog: onLog)
        case let name where name.hasPrefix("自动换装"):
            let id = Int(name.filter(\.isNumber)) ?? 1
            return await MoreExtraActions.applyOutfitPlan(planId: id, cookie: cookie, onLog: onLog)
        case "定时代玩":
            return await DiyUrlActions.run(featureId: "diy_auto_daiwan", cookie: cookie, onLog: onLog)
        case "定时任务", "自定义任务":
            return await DiyUrlActions.run(featureId: "diy_task", cookie: cookie, onLog: onLog)
        case "批量斗友":
            return await PiLiangDouYouActions.farm(onLog: onLog)
        case "批量斗友-师徒", "师徒情拜":
            return await PiLiangDouYouActions.farm(forceModes: ["stqb"], onLog: onLog)
        case "批量斗友-帮友", "帮友":
            return await PiLiangDouYouActions.farm(forceModes: ["by"], onLog: onLog)
        case "批量斗友-好友", "好友":
            return await PiLiangDouYouActions.farm(forceModes: ["hy"], onLog: onLog)
        case "门派守夜":
            return await DailyListenActions.farmMenPaiShouYe(cookie: cookie, onLog: onLog)
        case "喝酒":
            return await DailyListenActions.farmHeJiu(cookie: cookie, onLog: onLog)
        case "侠客行":
            return await DailyListenActions.farmXkx(cookie: cookie, onLog: onLog)
        case "好友管理":
            return await DailyListenActions.farmFriendMgmt(cookie: cookie, onLog: onLog)
        case "微端经验礼包":
            return await MoreExtraActions.weiDuanJingYan(cookie: cookie, onLog: onLog)
        case "微端挂机":
            return await MoreExtraActions.weiDuanGuaJi(cookie: cookie, onLog: onLog)
        case "结束挂机":
            return await MoreExtraActions.weiDuanStop(cookie: cookie, onLog: onLog)
        default:
            let tip = "「\(name)」尚未对接协议，已跳过"
            onLog(tip)
            return tip
        }
    }

    /// 帮派轨：打开对应排行/设置页并摘日志（笔记侧多为查看页，非长循环）。
    private func bangPaiPeek(
        cmd: String,
        extra: [String: String] = [:],
        pet: Bool,
        cookie: String,
        onLog: @escaping (String) -> Void,
        title: String
    ) async -> String {
        onLog("\(title)拉取中…")
        let (_, body) = pet
            ? await LedouCGI.getPetPk(cmd: cmd, extra: extra, cookie: cookie)
            : await LedouCGI.getPhonePk(cmd: cmd, extra: extra, cookie: cookie)
        let msg = CombatLog.fromBody(body)
        let tip = msg.isEmpty ? LedouCGI.shortBody(body, code: 200) : msg
        onLog(tip)
        return tip
    }
}

/// 悬浮窗轨组定义（真源 `DaiWanRecordScreen.RAIL_GROUPS`）。
enum DaiWanRecordRails {
    struct Tile: Identifiable, Hashable {
        var id: String { action }
        let action: String
        let title: String
        let hint: String?
        let wide: Bool
        let cornerAction: String?

        init(
            _ action: String,
            title: String? = nil,
            hint: String? = nil,
            wide: Bool = false,
            cornerAction: String? = nil
        ) {
            self.action = action
            self.title = title ?? action
            self.hint = hint
            self.wide = wide
            self.cornerAction = cornerAction
        }
    }

    struct Group: Identifiable {
        var id: String { title }
        let title: String
        let settingId: String?
        let tiles: [Tile]
    }

    static let groups: [Group] = [
        Group(title: "一键", settingId: "huoyue", tiles: [
            .init("一键活跃代玩", hint: "今天主路径", wide: true, cornerAction: "活跃设置"),
            .init("一键领奖", hint: "报名领奖", wide: true, cornerAction: "报名领奖设置"),
        ]),
        Group(title: "代玩", settingId: "daiwan", tiles:
            ["会武", "幻境", "历练", "Boss", "12宫", "门派", "画卷", "巅峰(后台)"].map { .init($0) }
        ),
        Group(title: "任务", settingId: "renwu", tiles:
            ["日常任务", "帮派任务", "门派任务", "游记任务"].map { .init($0) }
        ),
        Group(title: "报名", settingId: "lingjiang", tiles:
            ["群侠", "手机武林", "电脑武林", "随机飞升", "电脑侠侣", "手机侠侣"].map { .init($0) }
        ),
        Group(title: "帮派", settingId: nil, tiles:
            ["开启矿洞", "更换守护", "帮战设置", "问鼎出战",
             "矿洞排行", "问鼎帮资", "祭坛排行", "踢馆排行"].map { .init($0) }
        ),
        Group(title: "更多", settingId: "more_settings", tiles:
            ["竞技场", "华山论剑", "祭坛", "仙武修真", "深渊秘境", "踢馆",
             "武器充能", "打满问鼎", "开锦囊", "批量斗友", "梦想之旅", "反向历练",
             "遗迹征伐", "龙吟破阵", "长梦副本", "五行夺宝", "天地宝匣", "打造符石",
             "新春对联", "黄金联赛", "掌上道聚城", "帮派远征", "遗迹商店兑换", "斗神塔(后台)"
            ].map { .init($0) }
        ),
        Group(title: "电脑", settingId: nil, tiles:
            ["PC解锁", "修改PC锁", "重置PC锁", "设置PC锁密码",
             "微端经验礼包", "微端挂机", "结束挂机"].map { .init($0) }
        ),
        Group(title: "后台", settingId: nil, tiles:
            ["矿洞", "劫镖", "粮草", "问鼎", "问鼎复仇", "开矿洞",
             "换守护", "喝酒", "任务派遣", "门派守夜", "侠客行", "好友管理",
             "定时代玩", "定时任务"].map { .init($0) }
        ),
    ]

    /// 点后台类 → 开监听设置页；其余跑 NamedRunner。
    static func openFeatureId(for action: String) -> String? {
        switch action {
        case "开启矿洞", "开矿洞": return "open_kd"
        case "更换守护", "换守护": return "change_guard"
        case "矿洞": return "kuangdong"
        case "劫镖": return "jiebiao"
        case "粮草": return "liangcao"
        case "问鼎": return "wending"
        case "问鼎复仇": return "fuchou_wending"
        case "任务派遣": return "paiqian"
        case "喝酒": return "hejiu"
        case "门派守夜": return "menpai_shouye"
        case "侠客行": return "xkx"
        case "好友管理": return "friend_mgmt"
        case "定时代玩": return "diy_auto_daiwan"
        case "定时任务", "自定义任务": return "diy_task"
        case "批量斗友": return "piliang_douyou"
        default: return nil
        }
    }

    static func settingsFeatureId(for corner: String) -> String? {
        switch corner {
        case "活跃设置", "一键活跃设置": return "huoyue"
        case "报名领奖设置", "报名设置": return "lingjiang"
        case "代玩设置": return "daiwan"
        case "任务设置": return "renwu"
        case "更多设置": return "more_settings"
        default: return nil
        }
    }
}
