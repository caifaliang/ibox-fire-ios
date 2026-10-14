import Foundation
import UIKit
import UserNotifications

/// 同意后用户仍停在 QQ：用本地通知提醒立刻回 App，避免反复点同意把票点废。
enum OneKeyReturnNotifier {
    private static let agreeNotifId = "daledou.onekey.agree.return"
    private static var didNotifyAgree = false

    static func resetSession() {
        didNotifyAgree = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [agreeNotifId])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [agreeNotifId])
    }

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                AppViewModel.logOneKey("notify", "auth_ok=\(ok)")
            }
        }
    }

    /// poll=67（确认中）或 poll=0（已成功）时调用；仅后台发一次。
    static func notifyAgreeThenReturnIfNeeded(reason: String) {
        guard !didNotifyAgree else { return }
        didNotifyAgree = true
        AppViewModel.logOneKey("notify", "agree_signal reason=\(reason)")

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            guard allowed else {
                AppViewModel.logOneKey("notify", "skip_no_permission")
                return
            }
            // 仅在非前台时打扰（用户还在 QQ）
            DispatchQueue.main.async {
                let state = UIApplication.shared.applicationState
                guard state != .active else {
                    AppViewModel.logOneKey("notify", "skip_foreground")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "授权已确认"
                content.body = "请立即返回大乐斗（点左上角 ◀ 或点本通知）。勿再点同意，以免二维码过期。"
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                let req = UNNotificationRequest(
                    identifier: agreeNotifId,
                    content: content,
                    trigger: nil
                )
                center.add(req) { err in
                    if let err {
                        AppViewModel.logOneKey("notify", "add_fail \(err.localizedDescription)")
                    } else {
                        AppViewModel.logOneKey("notify", "posted")
                    }
                }
            }
        }
    }
}
