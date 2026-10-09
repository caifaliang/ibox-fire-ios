import SwiftUI
import UIKit

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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
}
