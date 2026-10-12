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
        // 闪退抓不到剪贴板时靠 Documents 落盘；关键节点每行都刷
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
        // 非 atomically：闪退时尽量保住已写内容
        try? joinedText.write(to: url, atomically: false, encoding: .utf8)
        // 双写一份带时间戳，避免被下次开机覆盖前用户找不到
        let stamp = docs.appendingPathComponent("ruffle_replay_last.txt")
        try? joinedText.write(to: stamp, atomically: false, encoding: .utf8)
    }
}
