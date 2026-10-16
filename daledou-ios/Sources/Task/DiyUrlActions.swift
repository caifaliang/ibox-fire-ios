import Foundation

/// 真源：`TimerWorkers.runDiy` — 按行请求腾讯 CGI URL。
enum DiyUrlActions {
    static func run(
        featureId: String,
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let label = featureId == "diy_auto_daiwan" ? "定时代玩" : "定时任务"
        let raw = FeatureToggleStore.shared.getString(featureId, "urls")
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        if lines.isEmpty {
            let tip = "未配置 URL（粘贴 phonepk/petpk 链接，每行一条）"
            onLog(tip)
            return tip
        }
        var parts: [String] = []
        for line in lines.prefix(30) {
            if Task.isCancelled { break }
            guard let url = URL(string: line) else {
                parts.append("无效:\(line.prefix(40))")
                continue
            }
            guard LedouCGI.isAllowedHost(url.host) else {
                parts.append("已拦截:\(url.host ?? "?")")
                continue
            }
            let (_, body) = await LedouCGI.get(url: url, cookie: cookie)
            let msg = CombatLog.fromBody(body)
            parts.append(msg.isEmpty ? LedouCGI.shortBody(body, code: 200) : String(msg.prefix(40)))
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        let tip = parts.joined(separator: " | ")
        onLog(tip.isEmpty ? "\(label)空响应" : tip)
        return tip
    }
}
