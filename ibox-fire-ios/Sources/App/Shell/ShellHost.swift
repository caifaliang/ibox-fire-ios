import SwiftUI

/// 商业壳宿主：底栏四 Tab + Hub/Workbench + LIVE Dock；矩星不露。
/// 官方 H5 用 ZStack 叠层保活（对齐 APK Activity），回科技不销毁 WebView。
struct ShellHost: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    @ObservedObject private var h5Session = OfficialH5Session.shared

    @State private var shellTab: ShellTab = .tech
    @State private var showHub = true
    @State private var platformKey = "ibox"
    @State private var h5Visible = false
    @State private var h5MissingToken = false

    var body: some View {
        ZStack {
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
                            hasCache: h5Session.hasCache,
                            status: h5Session.status,
                            onOpen: { openOfficialH5() },
                            onGoTech: {
                                shellTab = .tech
                                showHub = true
                            },
                            onClearCache: {
                                h5Session.tearDown()
                            }
                        )
                    case .me:
                        ProfileScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !h5Visible {
                    FireBottomBar(selected: $shellTab) { tab in
                        handleTab(tab)
                    }
                }
            }

            if !h5Visible, shellTab == .tech || shellTab == .running, let dock = primaryRunningLabel() {
                VStack {
                    Spacer()
                    LiveJobDock(
                        label: dock,
                        onOpen: { shellTab = .running },
                        onStop: {
                            if let k = runner.runningKinds.sorted().first,
                               let kind = TaskKind(rawValue: k) {
                                vm.stopTask(kind)
                            }
                        }
                    )
                    .padding(.bottom, 64)
                }
            }

            if !h5Visible, shellTab != .officialH5 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
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
            }

            if h5Visible {
                OfficialH5View(
                    onBackToTech: {
                        h5Visible = false
                        shellTab = .tech
                        showHub = true
                    },
                    token: vm.iboxToken,
                    refreshToken: "",
                    deviceId: IboxClient.makeDeviceId(vm.iboxToken),
                    uid: JwtUtil.uid(vm.iboxToken) ?? 0
                )
                .environmentObject(vm)
                .environmentObject(runner)
                .transition(.move(edge: .trailing))
                .zIndex(10)
            }
        }
        .appScreenBackground()
        .onAppear {
            platformKey = FeatureCatalog.platformKey(vm.appPlatform == .topstar ? .ibox : vm.appPlatform)
            if vm.appPlatform == .topstar {
                applyPlatform("ibox")
            }
        }
        .alert("请先登录 iBox", isPresented: $h5MissingToken) {
            Button("去我的") { shellTab = .me }
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
            // 有缓存则直接回前台
            if h5Session.hasCache, vm.iboxLoggedIn {
                h5Visible = true
            }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            h5Visible = true
        }
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

/// 底栏「官方H5」驻留页：有缓存时对齐 APK Park
struct OfficialH5ParkPage: View {
    var loggedIn: Bool
    var hasCache: Bool
    var status: String
    var onOpen: () -> Void
    var onGoTech: () -> Void
    var onClearCache: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("官方H5")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Palette.textPrimary)
            Text(
                hasCache
                    ? "页面在后台保活 · 切换「科技」不会销毁缓存 · 再次进入不重复注入"
                    : (loggedIn ? "已登录 iBox，可免登进入官方页" : "需要先登录 iBox")
            )
            .font(Typo.caption)
            .foregroundStyle(Palette.textMuted)

            VStack(alignment: .leading, spacing: 10) {
                Text(hasCache ? "H5 会话已保留" : "尚未打开官方页")
                    .font(.system(size: 16, weight: .bold))
                if hasCache {
                    Text(status)
                        .font(Typo.caption2)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                Text("可先去「科技」开火/捡漏；需要看官方页时再点下方按钮回前台。")
                    .font(Typo.caption2)
                    .foregroundStyle(Palette.textSecondary)
                Button(hasCache ? "回到官方H5" : "打开官方 H5", action: onOpen)
                    .buttonStyle(PrimaryButtonStyle())
                if hasCache {
                    Button("清除 H5 缓存", action: onClearCache)
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button("去科技", action: onGoTech)
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer()
        }
        .padding(20)
    }
}
