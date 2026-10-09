import SwiftUI

struct RootView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !vm.statusText.isEmpty {
                Text(vm.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
            }
            GameWebView(vm: vm, clearEpoch: vm.clearWebEpoch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { vm.bootstrap() }
        .confirmationDialog("菜单", isPresented: $vm.showMenu, titleVisibility: .visible) {
            Button("一键登陆") { vm.openOneClickLogin() }
            Button("扫码登陆") { vm.openScanLogin() }
            Button("进入游戏首页") { vm.openGameHome() }
            Button("刷新") { vm.reload() }
            Button("退出登录", role: .destructive) { vm.logout() }
            Button("取消", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.titleHint).font(.headline)
                if vm.session.isLoggedIn {
                    Text("QQ \(vm.qqLabel.isEmpty ? "…" : vm.qqLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                vm.showMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .padding(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
