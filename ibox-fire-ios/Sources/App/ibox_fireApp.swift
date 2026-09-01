import SwiftUI

@main
struct ibox_fireApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .preferredColorScheme(.light)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        TaskRunner.shared.requestNotificationPermission()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // iOS 无 FGS：杀后台即停；保持前台更可靠
    }
}
