import Foundation
import SwiftUI

/// 官方动画播放页调试日志（可复制发给开发）
@MainActor
final class ReplayDebugLog: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published var showPanel = true

    private let maxLines = 400
    private let started = Date()
    /// 同类刷屏：key → (首次时间戳行索引无关, 计数)
    private var dedupeCounts: [String: Int] = [:]

    var joinedText: String { lines.joined(separator: "\n") }

    func clear() {
        lines.removeAll()
        dedupeCounts.removeAll()
    }

    private static func dedupeKey(_ message: String) -> String? {
        if message.contains("loadingSWC") { return "loadingSWC" }
        if message.contains("POST treated") && message.contains("loadingSWC") { return "loadingSWC" }
        if message.hasPrefix("SEND ") && message.contains("loadingSWC") { return "loadingSWC" }
        if message.contains("REMOTE gres/loadingSWC") { return "loadingSWC" }
        return nil
    }

    func append(_ message: String) {
        if let key = Self.dedupeKey(message) {
            let n = (dedupeCounts[key] ?? 0) + 1
            dedupeCounts[key] = n
            if n > 1 {
                if n % 10 == 0 {
                    let t = Date().timeIntervalSince(started)
                    lines.append(String(format: "[%6.2fs] … %@ ×%d", t, key, n))
                    if lines.count > maxLines {
                        lines.removeFirst(lines.count - maxLines)
                    }
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
        if lines.count % 5 == 0 || message.contains("FAIL") || message.contains("err") {
            flushToDisk()
        }
    }

    func flushToDisk() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ruffle_replay_debug.log")
        try? joinedText.write(to: url, atomically: true, encoding: .utf8)
    }
}
