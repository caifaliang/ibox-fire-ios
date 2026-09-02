import UIKit

/// iOS 无 Android 前台服务：用 beginBackgroundTask 链式续期，切后台后争取约 2–3 分钟继续跑本地引擎。
@MainActor
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private var taskId: UIBackgroundTaskIdentifier = .invalid
    private var renewTask: Task<Void, Never>?

    func begin() {
        end()
        guard UIApplication.shared.applicationState != .background else { renewOnce() }
        renewTask = Task { @MainActor in
            while !Task.isCancelled {
                renewOnce()
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                    taskId = .invalid
                }
            }
        }
    }

    func end() {
        renewTask?.cancel()
        renewTask = nil
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
            taskId = .invalid
        }
    }

    private func renewOnce() {
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
        taskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.end()
        }
    }
}
