import SwiftUI

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
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        vm.onAppBecameActive()
                    }
                }
        }
    }
}
