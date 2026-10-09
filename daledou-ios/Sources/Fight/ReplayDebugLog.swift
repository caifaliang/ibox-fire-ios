import Foundation
import SwiftUI

/// 官方动画播放页调试日志（可复制发给开发）
@MainActor
final class ReplayDebugLog: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published var showPanel = true

    private let maxLines = 400
    private let started = Date()

    var joinedText: String { lines.joined(separator: "\n") }

    func clear() { lines.removeAll() }

    func append(_ message: String) {
        let t = Date().timeIntervalSince(started)
        let line = String(format: "[%6.2fs] %@", t, message)
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        // 同步写 Documents，方便万一闪退也能捞
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
