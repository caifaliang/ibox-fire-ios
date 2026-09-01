import Foundation
import UserNotifications
import UIKit

enum TaskKind: String {
    case query, buy, sell, batch, announce, synth, presale, nbPresale, nbSnipe, sweep
}

@MainActor
final class TaskRunner: ObservableObject {
    static let shared = TaskRunner()

    @Published var runningKinds: Set<String> = []
    private var stops: [String: () -> Void] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func setIdleTimerDisabled(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }

    func isRunning(_ kind: TaskKind) -> Bool { runningKinds.contains(kind.rawValue) }

    func stop(_ kind: TaskKind) {
        stops[kind.rawValue]?()
        tasks[kind.rawValue]?.cancel()
        runningKinds.remove(kind.rawValue)
        stops.removeValue(forKey: kind.rawValue)
        tasks.removeValue(forKey: kind.rawValue)
        if runningKinds.isEmpty { setIdleTimerDisabled(false) }
        notify(title: "已停止", body: kind.rawValue)
    }

    func stopAll() {
        for k in Array(runningKinds) {
            if let kind = TaskKind(rawValue: k) { stop(kind) }
        }
    }

    func start(kind: TaskKind, stop: @escaping () -> Void, work: @escaping () async -> Void) {
        stopAllMatching(kind)
        runningKinds.insert(kind.rawValue)
        stops[kind.rawValue] = stop
        setIdleTimerDisabled(true)
        notify(title: "任务运行中", body: "请保持 App 在前台：\(kind.rawValue)")
        tasks[kind.rawValue] = Task {
            await work()
            await MainActor.run {
                self.runningKinds.remove(kind.rawValue)
                self.stops.removeValue(forKey: kind.rawValue)
                self.tasks.removeValue(forKey: kind.rawValue)
                if self.runningKinds.isEmpty { self.setIdleTimerDisabled(false) }
                self.notify(title: "任务结束", body: kind.rawValue)
            }
        }
    }

    private func stopAllMatching(_ kind: TaskKind) {
        if runningKinds.contains(kind.rawValue) { stop(kind) }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
