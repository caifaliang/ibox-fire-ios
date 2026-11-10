import SwiftUI

/// 商业壳宿主：底栏四 Tab + Hub/Workbench + LIVE Dock；矩星不露。
struct ShellHost: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner

    @State private var shellTab: ShellTab = .tech
    @State private var showHub = true
    @State private var platformKey = "ibox"
    @State private var showOfficialH5 = false
    @State private var h5MissingToken = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if vm.vipPreviewBanner {
                    Text("非VIP预览模式：可浏览，开火需开通会员")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.warning)
                        .frame(maxWidth: .infinity)
                        .padding(Space.s)
                        .background(Palette.warningSoft)
                }
                if !vm.busyMsg.isEmpty {
                    Text(vm.busyMsg)
                        .font(Typo.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s)
                        .background(Palette.accentSoft)
                }

                Group {
                    switch shellTab {
                    case .tech:
                        techBody
                    case .running:
                        RunningJobsPage {
                            shellTab = .tech
                            showHub = true
                        }
                    case .officialH5:
                        OfficialH5ParkPage(
                            loggedIn: vm.iboxLoggedIn,
                            onOpen: { openOfficialH5() },
                            onGoTech: {
                                shellTab = .tech
                                showHub = true
                            }
                        )
                    case .me:
                        ProfileScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                FireBottomBar(selected: $shellTab) { tab in
                    handleTab(tab)
                }
            }

            if shellTab == .tech || shellTab == .running, let dock = primaryRunningLabel() {
                LiveJobDock(
                    label: dock,
                    onOpen: {
                        shellTab = .running
                    },
                    onStop: {
                        if let k = runner.runningKinds.sorted().first,
                           let kind = TaskKind(rawValue: k) {
                            vm.stopTask(kind)
                        }
                    }
                )
                .padding(.bottom, 64)
            }

            if shellTab != .officialH5 {
                SiteBrowseFAB {
                    let token = vm.siteUser?.token ?? ""
                    let cache = SiteBrowsePresenter.userCacheJSON(from: vm.siteUser)
                    let ibox = vm.iboxToken
                    SiteBrowsePresenter.present(siteToken: token, userCacheJSON: cache, iboxToken: ibox)
                }
                .padding(.trailing, Space.l)
                .padding(.bottom, 72)
            }
        }
        .appScreenBackground()
        .onAppear {
            platformKey = FeatureCatalog.platformKey(vm.appPlatform == .topstar ? .ibox : vm.appPlatform)
            if vm.appPlatform == .topstar {
                applyPlatform("ibox")
            }
        }
        .fullScreenCover(isPresented: $showOfficialH5) {
            OfficialH5View(
                token: vm.iboxToken,
                refreshToken: "",
                deviceId: IboxClient.makeDeviceId(vm.iboxToken),
                uid: JwtUtil.uid(vm.iboxToken) ?? 0
            )
            .environmentObject(vm)
            .environmentObject(runner)
        }
        .alert("请先登录 iBox", isPresented: $h5MissingToken) {
            Button("去我的") {
                shellTab = .me
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("官方 H5 需要 iBox 登录票，请先在「我的」里登录 iBox。")
        }
    }

    @ViewBuilder
    private var techBody: some View {
        if showHub {
            TechHubPage(
                platform: $platformKey,
                subtitle: hubSubtitle,
                recentMode: vm.techMode == .profile ? nil : vm.techMode.rawValue,
                onPlatformSelect: { applyPlatform($0) },
                onFeatureSelect: { tab in
                    guard let mode = tab.mode else { return }
                    vm.techMode = mode
                    vm.onTechModeChanged(mode)
                    withAnimation(.easeInOut(duration: 0.18)) { showHub = false }
                }
            )
        } else {
            FeatureWorkbench(
                title: vm.techMode.label,
                subtitle: FeatureCatalog.labelOf(vm.techMode.rawValue).isEmpty ? "" : platformKey,
                onBack: { withAnimation(.easeInOut(duration: 0.18)) { showHub = true } }
            ) {
                workbenchContent
            }
        }
    }

    @ViewBuilder
    private var workbenchContent: some View {
        Group {
            if vm.appPlatform == .newbee && !vm.nbLoggedIn { NbLoginScreen() }
            else if vm.appPlatform == .ibpro && !vm.ibLoggedIn { IbLoginScreen() }
            else { ModePane() }
        }
    }

    private var hubSubtitle: String {
        if vm.iboxLoggedIn, let uid = JwtUtil.uid(vm.iboxToken) {
            return "iBox · uid \(uid)"
        }
        return "平台 → 分类 → 功能"
    }

    private func handleTab(_ tab: ShellTab) {
        switch tab {
        case .tech:
            shellTab = .tech
            showHub = true
        case .running:
            shellTab = .running
        case .officialH5:
            shellTab = .officialH5
        case .me:
            shellTab = .me
            vm.techMode = .profile
        }
    }

    private func openOfficialH5() {
        let t = JwtUtil.normalize(vm.iboxToken)
        guard !t.isEmpty, vm.iboxLoggedIn else {
            h5MissingToken = true
            return
        }
        showOfficialH5 = true
    }

    private func applyPlatform(_ key: String) {
        platformKey = key
        switch key {
        case "newbee":
            vm.appPlatform = .newbee
            vm.techMode = .nb_presale
        case "ibpro":
            vm.appPlatform = .ibpro
            vm.techMode = .ib_presale
        default:
            vm.appPlatform = .ibox
            vm.featureCat = .tech
            vm.techMode = .seg_snipe
        }
        vm.onTechModeChanged(vm.techMode)
    }

    private func primaryRunningLabel() -> String? {
        guard let k = runner.runningKinds.sorted().first else { return nil }
        let name = FeatureCatalog.labelOf(k)
        return name.isEmpty ? "LIVE · \(k)" : "LIVE · \(name)"
    }
}

/// 底栏「官方H5」停靠页（Activity 未前台时）
struct OfficialH5ParkPage: View {
    var loggedIn: Bool
    var onOpen: () -> Void
    var onGoTech: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("官方 H5")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Palette.textPrimary)
            Text(loggedIn ? "已登录 iBox，可免登进入官方页" : "需要先登录 iBox")
                .font(Typo.caption)
                .foregroundStyle(Palette.textMuted)
            Text("可先去「科技」开火/捡漏；需要看官方页时再点下方按钮回前台。")
                .font(Typo.caption2)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("打开官方 H5", action: onOpen)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
            Button("去科技", action: onGoTech)
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(20)
    }
}
