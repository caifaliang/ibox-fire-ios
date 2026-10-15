import Foundation

/// 后台监听心跳：矿洞 / 劫镖 / 粮草（对齐 APK TaskRunner.runNow + 周期轮询）。
@MainActor
final class BackgroundListenRunner: ObservableObject {
    static let shared = BackgroundListenRunner()

    @Published private(set) var activeIds: Set<String> = []
    private var job: Task<Void, Never>?
    private let listenIds = ["kuangdong", "jiebiao", "liangcao", "wending"]

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
        default: return id
        }
    }
}

private extension Int {
    func nonZero(_ fallback: Int) -> Int { self > 0 ? self : fallback }
}
