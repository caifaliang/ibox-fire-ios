import Foundation
import SwiftUI

/// 官方动画播放页调试日志。
/// 同时：落盘 Documents +（若有 debug_log_url.txt）POST 到电脑 LogReceiver，便于远端实时查看。
@MainActor
final class ReplayDebugLog: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published var showPanel = true

    private let maxLines = 400
    private let started = Date()
    private var dedupeCounts: [String: Int] = [:]
    private var pendingShip: [String] = []
    private var shipTask: Task<Void, Never>?
    private var endpoint: URL?
    private var endpointResolved = false

    var joinedText: String { lines.joined(separator: "\n") }

    func clear() {
        lines.removeAll()
        dedupeCounts.removeAll()
        pendingShip.removeAll()
    }

    private static func dedupeKey(_ message: String) -> String? {
        let m = message
        if m.contains("loadingSWC") { return "loadingSWC" }
        if m.contains("ui-v10") { return "ui-v10" }
        if m.contains("bg/") || m.contains("bg1") || m.contains("bg2") { return "bg" }
        if m.contains("npc") { return "npc" }
        if m.contains("mercenary") { return "mercenary" }
        if m.contains("xianxia") { return "xianxia" }
        if m.contains("STUB wrong-gender") || m.contains("STUB apk-heavy") { return "stub" }
        if m.contains("action_mm") { return "action_mm" }
        if m.contains("POST treated") && m.contains("/remote/") {
            if let r = m.range(of: "gres/") {
                let rest = String(m[r.upperBound...])
                let name = rest.split(separator: " ").first.map(String.init) ?? "remote"
                return "POST-\(name)"
            }
            return "POST-remote"
        }
        return nil
    }

    func append(_ message: String) {
        if let key = Self.dedupeKey(message) {
            let n = (dedupeCounts[key] ?? 0) + 1
            dedupeCounts[key] = n
            if n > 1 {
                if n % 10 == 0 {
                    let t = Date().timeIntervalSince(started)
                    let line = String(format: "[%6.2fs] … %@ ×%d", t, key, n)
                    lines.append(line)
                    if lines.count > maxLines {
                        lines.removeFirst(lines.count - maxLines)
                    }
                    enqueueShip(line)
                }
                return
            }
        }
        let t = Date().timeIntervalSince(started)
        let line = String(format: "[%6.2fs] %@", t, message)
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        enqueueShip(line)

        let critical = message.contains("FAIL") || message.contains("err")
            || message.contains("STREAM") || message.contains("PACK")
            || message.contains("CloseFlash") || message.contains("closeflash")
            || message.contains("OOM") || message.contains("boot ")
            || message.contains("FightReady") || message.contains("sound")
        if critical || lines.count % 3 == 0 {
            flushToDisk()
        }
    }

    func flushToDisk() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("ruffle_replay_debug.log")
        try? joinedText.write(to: url, atomically: false, encoding: .utf8)
        let stamp = docs.appendingPathComponent("ruffle_replay_last.txt")
        try? joinedText.write(to: stamp, atomically: false, encoding: .utf8)
    }

    // MARK: - Ship to PC LogReceiver

    private func enqueueShip(_ line: String) {
        guard !line.isEmpty else { return }
        pendingShip.append(line)
        scheduleShip()
    }

    private func scheduleShip() {
        guard shipTask == nil else { return }
        shipTask = Task { [weak self] in
            // 小批量合并，避免每行一个 HTTP
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self?.flushShip()
        }
    }

    private func resolveEndpointIfNeeded() {
        guard !endpointResolved else { return }
        endpointResolved = true
        let candidates: [URL] = [
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("debug_log_url.txt"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DaLedou/debug_log_url.txt"),
        ]
        for u in candidates {
            if let s = try? String(contentsOf: u, encoding: .utf8) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: t), let scheme = url.scheme, scheme == "http" || scheme == "https" {
                    endpoint = url
                    lines.append(String(format: "[%6.2fs] log-ship → %@", Date().timeIntervalSince(started), t))
                    return
                }
            }
        }
    }

    private func flushShip() async {
        shipTask = nil
        resolveEndpointIfNeeded()
        guard let endpoint, !pendingShip.isEmpty else {
            pendingShip.removeAll()
            return
        }
        let batch = pendingShip
        pendingShip.removeAll()
        let body = batch.joined(separator: "\n") + "\n"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 2.5
        req.httpBody = Data(body.utf8)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // 静默：电脑未开 receiver 时不刷屏
            }
        } catch {
            // 电脑未开 LogReceiver / 不在同一网段时忽略
        }
        if !pendingShip.isEmpty {
            scheduleShip()
        }
    }
}

