import Foundation

/// 后台监听心跳：矿洞 / 劫镖 / 粮草（对齐 APK TaskRunner.runNow + 周期轮询）。
@MainActor
final class BackgroundListenRunner: ObservableObject {
    static let shared = BackgroundListenRunner()

    @Published private(set) var activeIds: Set<String> = []
    private var job: Task<Void, Never>?
    private let listenIds = [
        "kuangdong", "jiebiao", "liangcao", "wending",
        "fuchou_wending", "open_kd", "change_guard", "paiqian",
        "menpai_shouye", "hejiu", "xkx", "friend_mgmt",
        "diy_auto_daiwan", "diy_task", "shuqian", "xianshi_qianggou", "doudou_mall", "bangpai_wakuang",
        "bagua", "xydb", "wulin_chiyao",
    ]

    private init() {}

    var isAnyActive: Bool { !activeIds.isEmpty }

    func isActive(_ featureId: String) -> Bool {
        activeIds.contains(featureId)
    }

    func start(_ featureId: String) {
        guard listenIds.contains(featureId) else { return }
        FeatureToggleStore.shared.setEnabled(featureId, true)
        activeIds.insert(featureId)
        ensureLoop()
        TaskLogStore.shared.append(label(featureId), "监听已开启")
        // 立即跑一轮
        Task { await tickOne(featureId) }
    }

    func stop(_ featureId: String) {
        FeatureToggleStore.shared.setEnabled(featureId, false)
        activeIds.remove(featureId)
        TaskLogStore.shared.append(label(featureId), "监听已停止")
        if activeIds.isEmpty {
            job?.cancel()
            job = nil
        }
    }

    func stopAll() {
        for id in Array(activeIds) { stop(id) }
    }

    /// 冷启：恢复上次 isEnabled 的监听。
    func restoreFromStore() {
        for id in listenIds where FeatureToggleStore.shared.isEnabled(id) {
            activeIds.insert(id)
        }
        if !activeIds.isEmpty { ensureLoop() }
    }

    private func ensureLoop() {
        guard job == nil else { return }
        job = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let ids = Array(self.activeIds)
                if ids.isEmpty { break }
                for id in ids {
                    if Task.isCancelled { break }
                    // 被 farm* 自行关掉时同步 UI
                    if !FeatureToggleStore.shared.isEnabled(id) {
                        self.activeIds.remove(id)
                        continue
                    }
                    await self.tickOne(id)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                let sec = max(5, UserDefaults.standard.integer(forKey: "daledou.shell.bg_interval").nonZero(10))
                try? await Task.sleep(nanoseconds: UInt64(sec) * 1_000_000_000)
            }
            await MainActor.run { self?.job = nil }
        }
    }

    private func tickOne(_ featureId: String) async {
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            TaskLogStore.shared.append(label(featureId), "请先登录")
            return
        }
        let tag = label(featureId)
        let live: (String) -> Void = { line in
            Task { @MainActor in TaskLogStore.shared.append(tag, line) }
        }
        let msg: String
        switch featureId {
        case "kuangdong":
            msg = await DailyListenActions.farmKuangDong(cookie: cookie, onLog: live)
        case "jiebiao":
            msg = await DailyListenActions.farmJieBiao(cookie: cookie, onLog: live)
        case "liangcao":
            msg = await DailyListenActions.farmLiangCao(cookie: cookie, onLog: live)
        case "wending":
            msg = await DailyListenActions.farmWenDingListen(cookie: cookie, onLog: live)
        case "fuchou_wending":
            msg = await DailyListenActions.farmFuChouWenDing(cookie: cookie, onLog: live)
        case "open_kd":
            msg = await DailyListenActions.farmOpenKd(cookie: cookie, onLog: live)
        case "change_guard":
            msg = await DailyListenActions.farmChangeGuard(cookie: cookie, onLog: live)
        case "paiqian":
            msg = await DailyListenActions.farmPaiQian(cookie: cookie, onLog: live)
        case "menpai_shouye":
            msg = await DailyListenActions.farmMenPaiShouYe(cookie: cookie, onLog: live)
        case "hejiu":
            msg = await DailyListenActions.farmHeJiu(cookie: cookie, onLog: live)
        case "xkx":
            msg = await DailyListenActions.farmXkx(cookie: cookie, onLog: live)
        case "friend_mgmt":
            msg = await DailyListenActions.farmFriendMgmt(cookie: cookie, onLog: live)
        case "diy_auto_daiwan", "diy_task", "shuqian":
            msg = await DiyUrlActions.run(featureId: featureId, cookie: cookie, onLog: live)
        case "xianshi_qianggou":
            msg = await XianShiQiangGouActions.farm(cookie: cookie, onLog: live)
        case "doudou_mall":
            msg = await DouDouMallActions.farm(cookie: cookie, onLog: live)
        case "bangpai_wakuang":
            msg = await BangPaiWaKuangActions.farm(cookie: cookie, onLog: live)
        case "bagua":
            msg = await BaGuaActions.farm(cookie: cookie, onLog: live)
        case "xydb":
            msg = await XingYunDuoBaoActions.farm(cookie: cookie, onLog: live)
        case "wulin_chiyao":
            msg = await WuLinChiYaoActions.farm(cookie: cookie, onLog: live)
        default:
            return
        }
        _ = msg
        if !FeatureToggleStore.shared.isEnabled(featureId) {
            activeIds.remove(featureId)
        }
    }

    private func label(_ id: String) -> String {
        switch id {
        case "kuangdong": return "矿洞"
        case "jiebiao": return "劫镖"
        case "liangcao": return "粮草"
        case "wending": return "问鼎"
        case "fuchou_wending": return "问鼎复仇"
        case "open_kd": return "开矿洞"
        case "change_guard": return "换守护神"
        case "paiqian": return "任务派遣"
        case "menpai_shouye": return "门派守夜"
        case "hejiu": return "喝酒"
        case "xkx": return "侠客行"
        case "friend_mgmt": return "好友管理"
        case "diy_auto_daiwan": return "定时代玩"
        case "diy_task": return "定时任务"
        case "shuqian": return "书签"
        case "xianshi_qianggou": return "限时抢购"
        case "doudou_mall": return "斗豆商城"
        case "bangpai_wakuang": return "帮派挖矿"
        case "bagua": return "八卦迷阵"
        case "xydb": return "幸运夺宝"
        case "wulin_chiyao": return "武林吃药"
        default: return id
        }
    }
}

private extension Int {
    func nonZero(_ fallback: Int) -> Int { self > 0 ? self : fallback }
}
