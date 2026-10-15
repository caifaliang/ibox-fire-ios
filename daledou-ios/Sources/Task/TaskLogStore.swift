import Foundation
import Combine

struct TaskLogEntry: Identifiable, Equatable {
    let id: UUID
    let timeLabel: String
    let tag: String
    let message: String
    let raw: String
}

/// 对齐 Android TaskLogStore：供「日志」Tab 展示。
@MainActor
final class TaskLogStore: ObservableObject {
    static let shared = TaskLogStore()

    @Published private(set) var entries: [TaskLogEntry] = []
    @Published private(set) var running = false
    @Published private(set) var activeName: String?

    private let maxEntries = 300
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {}

    func append(_ tag: String, _ message: String) {
        let ts = timeFormatter.string(from: Date())
        let raw = "[\(ts)] [\(tag)] \(message)"
        let e = TaskLogEntry(id: UUID(), timeLabel: ts, tag: tag, message: message, raw: raw)
        entries.insert(e, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    func clear() {
        entries = []
    }

    func setRunning(_ on: Bool, name: String? = nil) {
        running = on
        activeName = on ? name : nil
    }
}
