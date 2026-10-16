import SwiftUI

struct RootView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // 顶：工具条 + 状态条（对齐 APK embed 壳）
                ShellToolStrip()
                    .environmentObject(vm)
                ShellStatusBar()
                    .environmentObject(vm)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [DlColors.brand, DlColors.accentBlue, DlColors.brand],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)

                if !vm.statusText.isEmpty {
                    oneKeyStatusBanner
                }

                // 中：首页 WebView 保活；其它 Tab 盖在上层
                ZStack {
                    gameArea
                        .opacity(vm.shellTab == 0 ? 1 : 0)
                        .allowsHitTesting(vm.shellTab == 0)
                        .zIndex(vm.shellTab == 0 ? 1 : 0)

                    if vm.shellTab != 0 {
                        Group {
                            switch vm.shellTab {
                            case 1:
                                LogTabView()
                                    .environmentObject(vm)
                            case 2:
                                JiLuTabView()
                                    .environmentObject(vm)
                            default:
                                MineHubView()
                                    .environmentObject(vm)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DlColors.canvas)
                        .zIndex(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                UnifiedBottomDock()
                    .environmentObject(vm)
            }
            .background(DlColors.canvas)

            // 首页悬浮钮 → 代玩-记录（对齐 APK DraggableNoteFab）
            if vm.shellTab == 0 && !vm.suspendGameWebForReplay {
                Button {
                    vm.showDaiWanRecord = true
                } label: {
                    Text("代玩")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(DlColors.brand.opacity(0.92))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
                }
                .padding(.trailing, 16)
                .padding(.bottom, vm.showViewFightFab ? 140 : 72)
                .accessibilityLabel("代玩记录")
            }

            if vm.showViewFightFab && vm.shellTab == 0 {
                Button {
                    vm.openOfficialAnimation()
                } label: {
                    HStack(spacing: 6) {
                        if vm.viewFightLoading {
                            ProgressView().tint(.white)
                        }
                        Text(vm.viewFightLoading ? "加载中" : "官方动画")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(DlColors.accentBlue.opacity(0.92))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                .disabled(vm.viewFightLoading)
                .padding(.trailing, 16)
                .padding(.bottom, 72)
                .accessibilityLabel("官方动画")
            }
        }
        .onAppear { vm.bootstrap() }
        .sheet(isPresented: $vm.showShellMenu) {
            MainMenuView()
                .environmentObject(vm)
        }
        .sheet(isPresented: $vm.showAbout) {
            AboutView()
        }
        .sheet(isPresented: $vm.showHuoYue) {
            HuoYueView()
        }
        .sheet(isPresented: $vm.showLingJiang) {
            LingJiangView()
        }
        .sheet(isPresented: $vm.showDaiWan) {
            DaiWanView()
        }
        .sheet(isPresented: $vm.showMoreSettings) {
            MoreSettingsView()
        }
        .sheet(isPresented: $vm.showChaQu) {
            ChaQuView()
        }
        .sheet(isPresented: $vm.showPiLiang) {
            PiLiangDouYouView()
        }
        .sheet(isPresented: $vm.showBeiBao) {
            BeiBaoView()
        }
        .sheet(isPresented: $vm.showHuanZhuang) {
            HuanZhuangView()
        }
        .sheet(isPresented: $vm.showZiDongQiangHua) {
            ZiDongQiangHuaView()
        }
        .sheet(isPresented: $vm.showDaiWanRecord) {
            DaiWanRecordView()
                .environmentObject(vm)
        }
        .sheet(isPresented: $vm.showListenFeature) {
            ListenHostView(featureId: vm.listenFeatureId)
        }
        .sheet(isPresented: $vm.showCookieSheet) {
            CookiePasteSheet()
                .environmentObject(vm)
        }
        .confirmationDialog(
            "请选择登录的网址",
            isPresented: $vm.showScanTargetPicker,
            titleVisibility: .visible
        ) {
            Button("大乐斗") { vm.openScanLedouLogin() }
            Button("道聚城") { vm.openScanDaojuLogin() }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $vm.showReplay, onDismiss: {
            vm.onReplayDismissed()
        }) {
            ReplaySheet(act: vm.replayAct, replayId: vm.replayId)
        }
    }

    @ViewBuilder
    private var gameArea: some View {
        if vm.suspendGameWebForReplay {
            ZStack {
                Color.black
                Text(vm.statusText.isEmpty ? "返回游戏中…" : vm.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GameWebView(vm: vm, clearEpoch: vm.clearWebEpoch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var oneKeyStatusBanner: some View {
        let kind = vm.oneKeyBannerKind
        let bg: Color = {
            switch kind {
            case .warn: return Color.orange.opacity(0.22)
            case .progress: return Color.blue.opacity(0.12)
            case .success: return Color.green.opacity(0.18)
            case .danger: return Color.red.opacity(0.16)
            case .info, .none: return Color(.systemGray6)
            }
        }()
        let fg: Color = {
            switch kind {
            case .warn: return Color.orange.opacity(0.95)
            case .danger: return Color.red.opacity(0.9)
            case .success: return Color.green.opacity(0.95)
            default: return Color.secondary
            }
        }()
        return HStack(alignment: .top, spacing: 8) {
            if kind == .progress {
                ProgressView().controlSize(.small)
            } else if kind == .warn {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(fg)
            }
            Text(vm.statusText)
                .font(kind == .warn ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(kind == .warn || kind == .danger ? fg : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, kind == .warn ? 8 : 4)
        .background(bg)
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
