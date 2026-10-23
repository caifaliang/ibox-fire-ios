import SwiftUI
import UIKit
import UserNotifications

@main
struct ibox_fireApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .environmentObject(TaskRunner.shared)
                .preferredColorScheme(.light)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Haptics.prepare()
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            TaskRunner.shared.requestNotificationPermission()
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 保活由 BackgroundKeepAlive（audio）自行续播；此处仅作兜底提示
        Task { @MainActor in
            if BackgroundKeepAlive.shared.isActive {
                BackgroundKeepAlive.shared.begin()
            }
        }
    }

    /// 前台也弹横幅（锁屏/后台走系统通知栏）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
