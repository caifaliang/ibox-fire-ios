import Foundation

/// 代玩执行骨架（M12）：按 L4 子类型顺序跑；已接少量报名 CGI，其余记 stub。
@MainActor
final class DaiWanRunner: ObservableObject {
    static let shared = DaiWanRunner()

    @Published private(set) var running = false

    private let toggles = FeatureToggleStore.shared
    private let log = TaskLogStore.shared
    private var job: Task<Void, Never>?

    private init() {}

    func stop() {
        job?.cancel()
        job = nil
        running = false
        log.append("Runner", "已停止")
    }

    /// 对齐 hub `daiwan_ui`：跑所有已启用子类型。
    func runHub(cookie: String) {
        guard !running else {
            log.append("Runner", "已有任务在跑")
            return
        }
        guard LoginURLs.hasGameSession(cookie) else {
            log.append("Runner", "请先登录")
            return
        }
        job = Task { await runHubAsync(cookie: cookie) }
    }

    /// 单独跑一个中文名（调试 / 未来定时用）。
    func runNamed(_ name: String, cookie: String) {
        guard !running else {
            log.append("Runner", "已有任务在跑")
            return
        }
        guard LoginURLs.hasGameSession(cookie) else {
            log.append("Runner", "请先登录")
            return
        }
        job = Task {
            running = true
            defer { running = false; job = nil }
            let msg = await executeTypePublic(name, cookie: cookie)
            log.append(name, msg)
        }
    }

    private func runHubAsync(cookie: String) async {
        running = true
        defer { running = false; job = nil }
        log.append("代玩界面", "开始聚合代玩")
        var parts: [String] = []
        for (i, name) in DaiWanCatalog.autoDaiWanTypes.enumerated() {
            if Task.isCancelled { break }
            guard toggles.isEnabled(DaiWanCatalog.typeId(i)) else { continue }
            let msg = await executeTypePublic(name, cookie: cookie)
            parts.append("\(name):\(String(msg.prefix(32)))")
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        let summary = parts.isEmpty ? "无启用子类型" : parts.joined(separator: " | ")
        log.append("代玩界面", summary)
    }

    /// 供 Hub / 活跃矩阵复用。
    func executeTypePublic(_ typeName: String, cookie: String) async -> String {
        log.append(typeName, "开始")
        switch true {
        case typeName.contains("一键活跃"):
            // 避免与 runHub 互锁：活跃单独编排
            let tip = await HuoYueRunner.shared.runOnceAwait(cookie: cookie)
            log.append(typeName, tip)
            return tip
        case typeName.contains("一键领奖"):
            let tip = await LingJiangRunner.shared.runOnceAwait(cookie: cookie)
            log.append(typeName, tip)
            return tip
        case typeName.contains("手机武林"):
            return await signupWuLinPhone(cookie: cookie)
        case typeName.contains("电脑武林"):
            let tip = "电脑武林需解析 showwulin（后续切片）"
            log.append(typeName, tip)
            return tip
        case typeName.contains("群侠"):
            return await signupQunXia(cookie: cookie)
        default:
            let tip = "stub：CGI 循环待接"
            log.append(typeName, tip)
            return tip
        }
    }

    private func signupWuLinPhone(cookie: String) async -> String {
        let (code, body) = await LedouCGI.getPhonePk(
            cmd: "fastSignWulin",
            extra: ["ifFirstSign": "1"],
            cookie: cookie
        )
        let msg = Self.shortBody(body, code: code)
        log.append("报名手机武林", msg)
        return msg
    }

    private func signupQunXia(cookie: String) async -> String {
        var comps = URLComponents(string: LedouCGI.petpkBase)!
        comps.queryItems = [
            .init(name: "cmd", value: "knightfight"),
            .init(name: "op", value: "signup"),
        ]
        guard let url = comps.url else { return "URL 错误" }
        let (code, body) = await LedouCGI.get(url: url, cookie: cookie, referer: LedouCGI.petpkBase)
        let msg = Self.shortBody(body, code: code)
        log.append("报名群侠", msg)
        return msg
    }

    private static func shortBody(_ body: String, code: Int) -> String {
        if code == -2 { return "拒绝非腾讯域名" }
        if code < 0 { return "网络失败(\(code))" }
        if body.contains("登陆校验失败") || body.contains("请先登录") { return "会话失效" }
        let plain = body
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.isEmpty { return "HTTP \(code) 空体" }
        return String(plain.prefix(80))
    }
}
