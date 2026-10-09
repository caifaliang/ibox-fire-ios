import SwiftUI

struct RootView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            if vm.showViewFightFab {
                Button {
                    vm.openOfficialAnimation()
                } label: {
                    HStack(spacing: 6) {
                        if vm.viewFightLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(vm.viewFightLoading ? "加载中" : "官方动画")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.92))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                .disabled(vm.viewFightLoading)
                .padding(.trailing, 16)
                .padding(.bottom, 28)
                .accessibilityLabel("官方动画")
            }
        }
        .onAppear { vm.bootstrap() }
        .confirmationDialog("菜单", isPresented: $vm.showMenu, titleVisibility: .visible) {
            Button("扫码登陆（推荐）") { vm.openScanLogin() }
            Button("Cookie 登陆") { vm.openCookieLoginSheet() }
            Button("进入游戏首页") { vm.openGameHome() }
            Button("刷新") { vm.reload() }
            Button("退出登录", role: .destructive) { vm.logout() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $vm.showCookieSheet) {
            CookiePasteSheet()
                .environmentObject(vm)
        }
        .fullScreenCover(isPresented: $vm.showReplay, onDismiss: {
            vm.onReplayDismissed()
        }) {
            ReplaySheet(act: vm.replayAct, replayId: vm.replayId)
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

struct CookiePasteSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("从安卓已登录客户端或抓包复制 Cookie，粘贴下方。至少包含 skey=…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $vm.cookieDraft)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !vm.cookieError.isEmpty {
                    Text(vm.cookieError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Cookie 登陆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("写入并进入") { vm.applyPastedCookie() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
