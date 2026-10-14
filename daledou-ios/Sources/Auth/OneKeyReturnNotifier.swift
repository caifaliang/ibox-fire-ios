import Foundation
import UIKit
import UserNotifications

/// 同意后用户仍停在 QQ：本地通知催立刻回 App。
/// 注意：进程常在切 QQ 后数秒被 jetsam，后台 poll 来不及 → 必须在打开 QQ 时**预约**提醒。
enum OneKeyReturnNotifier {
    private static let agreeNotifId = "daledou.onekey.agree.return"
    private static let remindIds = ["daledou.onekey.remind.5s", "daledou.onekey.remind.18s"]
    private static var didNotifyAgree = false

    static func resetSession() {
        didNotifyAgree = false
        let ids = [agreeNotifId] + remindIds
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            AppViewModel.logOneKey("notify", "perm=\(settings.authorizationStatus.rawValue)")
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, err in
                AppViewModel.logOneKey(
                    "notify",
                    "auth_ok=\(ok) err=\(err?.localizedDescription ?? "-")"
                )
            }
        }
    }

    /// 刚打开 QQ：预约两次提醒（不依赖本进程还活着）。回 App / 结束一键时 reset 取消。
    static func scheduleReturnRemindersAfterOpenQQ() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            guard allowed else {
                AppViewModel.logOneKey("notify", "remind_skip_no_permission perm=\(settings.authorizationStatus.rawValue)")
                return
            }
            // 清旧预约再挂
            center.removePendingNotificationRequests(withIdentifiers: remindIds)
            let bodies: [(String, TimeInterval, String)] = [
                (remindIds[0], 5, "若已点「同意」，请马上点左上角 ◀ 回大乐斗。勿反复点同意。"),
                (remindIds[1], 18, "还在 QQ？点一次同意后请立即返回大乐斗，否则二维码会过期。"),
            ]
            for (id, sec, body) in bodies {
                let content = UNMutableNotificationContent()
                content.title = "请返回大乐斗"
                content.body = body
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: sec, repeats: false)
                let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(req) { err in
                    if let err {
                        AppViewModel.logOneKey("notify", "remind_fail \(id) \(err.localizedDescription)")
                    } else {
                        AppViewModel.logOneKey("notify", "remind_scheduled \(id) +\(Int(sec))s")
                    }
                }
            }
        }
    }

    /// poll=67 / poll=0：进程尚在时立刻再催一次（与预约互补）。
    static func notifyAgreeThenReturnIfNeeded(reason: String) {
        guard !didNotifyAgree else { return }
        didNotifyAgree = true
        AppViewModel.logOneKey("notify", "agree_signal reason=\(reason)")

        let center = UNUserNotificationCenter.current()
        // 已有预约提醒即可；再发一条「已确认」
        center.removePendingNotificationRequests(withIdentifiers: remindIds)

        center.getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            guard allowed else {
                AppViewModel.logOneKey("notify", "skip_no_permission")
                return
            }
            DispatchQueue.main.async {
                let state = UIApplication.shared.applicationState
                // inactive 也发（切 QQ 动画中）；仅 active 跳过
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
