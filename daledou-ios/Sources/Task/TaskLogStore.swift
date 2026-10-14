import Foundation
import Combine

/// 对齐 Android `TaskLogStore`：最近日志行，供代玩界面展示。
@MainActor
final class TaskLogStore: ObservableObject {
    static let shared = TaskLogStore()

    @Published private(set) var lines: [String] = []
    @Published private(set) var snapshot: String = ""

    private let maxLines = 200

    private init() {}

    func append(_ tag: String, _ message: String) {
        let ts = Self.timeFormatter.string(from: Date())
        let line = "[\(ts)] [\(tag)] \(message)"
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        snapshot = lines.suffix(8).joined(separator: "\n")
    }

    func clear() {
        lines = []
        snapshot = ""
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
