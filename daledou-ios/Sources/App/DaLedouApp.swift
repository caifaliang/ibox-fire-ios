import SwiftUI
import UIKit

@main
struct DaLedouApp: App {
    @StateObject private var vm = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    vm.handleOpenURL(url)
                }
                .onAppear {
                    vm.installForegroundObservers()
                }
                // scenePhase + UIKit 双通道，避免回壳漏掉 onAppBecameActive
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        vm.onAppBecameActive()
                    }
                }
        }
    }
}
