import SwiftUI

@main
struct DaLedouApp: App {
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    vm.handleOpenURL(url)
                }
        }
    }
}
