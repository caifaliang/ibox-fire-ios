import SwiftUI
import UIKit

/// 顶栏工具条：URL chip + 截图/刷新/查询（对齐 ShellToolStrip）
struct ShellToolStrip: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showURLEditor = false
    @State private var urlDraft = ""

    var body: some View {
        HStack(spacing: 8) {
            Button {
                urlDraft = vm.currentURLString
                showURLEditor = true
            } label: {
                Text(vm.currentURLString.isEmpty ? "点此输入/粘贴链接" : vm.currentURLString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DlColors.inkSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DlColors.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DlColors.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            toolIcon(system: "camera.viewfinder", tint: DlColors.inkSecondary) {
                vm.statusText = "截长图：下一刀按 APK 接入"
            }
            toolIcon(system: "arrow.clockwise", tint: DlColors.inkSecondary) {
                vm.reload()
            }
            toolIcon(system: "magnifyingglass", tint: DlColors.accentBlue) {
                vm.statusText = "查询：下一刀按 APK 接入"
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(DlColors.surface)
        .alert("打开链接", isPresented: $showURLEditor) {
            TextField("phonepk / https", text: $urlDraft)
            Button("复制当前") {
                UIPasteboard.general.string = vm.currentURLString
                vm.statusText = "已复制链接"
            }
            Button("打开") {
                if !vm.openShellURL(urlDraft) {
                    vm.statusText = "链接无效或非腾讯游戏域"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("粘贴 phonepk / 完整 https 链接")
        }
    }

    private func toolIcon(system: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}

/// 状态条：显示名 + 后台开关 UI（对齐 ShellStatusBar）
struct ShellStatusBar: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.shellDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DlColors.ink)
                    .lineLimit(1)
                Text(vm.shellVipLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DlColors.accentBlue)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text(vm.backgroundEnabled ? "已启用后台" : "已关闭后台")
                    .font(.system(size: 11))
                    .foregroundStyle(vm.backgroundEnabled ? DlColors.accentBlue : DlColors.inkMuted)
                Toggle("", isOn: $vm.backgroundEnabled)
                    .labelsHidden()
                    .tint(DlColors.accentBlue)
                    .scaleEffect(0.85)
                Text("\(vm.backgroundIntervalSec)s")
                    .font(.system(size: 11))
                    .foregroundStyle(DlColors.inkMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(DlColors.surface)
    }
}

/// 统一底栏：后退|前进|首页|菜单|日志|记录|我的
struct UnifiedBottomDock: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            dockItem(
                system: "chevron.backward",
                label: "后退",
                enabled: vm.canGoBack,
                selected: false,
                highlight: false
            ) { vm.shellGoBack() }
            dockItem(
                system: "chevron.forward",
                label: "前进",
                enabled: vm.canGoForward,
                selected: false,
                highlight: false
            ) { vm.shellGoForward() }
            dockItem(
                system: "house.fill",
                label: "首页",
                enabled: true,
                selected: vm.shellTab == 0,
                highlight: false
            ) { vm.shellTab = 0 }
            dockItem(
                system: "line.3.horizontal",
                label: "菜单",
                enabled: true,
                selected: false,
                highlight: true
            ) { vm.showShellMenu = true }
            dockItem(
                system: "doc.text.fill",
                label: "日志",
                enabled: true,
                selected: vm.shellTab == 1,
                highlight: false
            ) { vm.shellTab = 1 }
            dockItem(
                system: "book.fill",
                label: "记录",
                enabled: true,
                selected: vm.shellTab == 2,
                highlight: false
            ) { vm.shellTab = 2 }
            dockItem(
                system: "person.fill",
                label: "我的",
                enabled: true,
                selected: vm.shellTab == 3,
                highlight: false
            ) { vm.shellTab = 3 }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .background(DlColors.surface)
    }

    private func dockItem(
        system: String,
        label: String,
        enabled: Bool,
        selected: Bool,
        highlight: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = {
            if !enabled { return DlColors.inkMuted.opacity(0.35) }
            if highlight { return DlColors.brand }
            if selected { return DlColors.accentBlue }
            return DlColors.inkMuted
        }()
        return Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: system)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: selected || highlight ? .bold : .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Tab 占位页（日志 / 记录）
struct ShellPlaceholderTab: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DlColors.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(DlColors.inkMuted)
            Spacer()
            Text("业务内容按 APK 下一刀接入；本切片只落实壳框架。")
                .font(.footnote)
                .foregroundStyle(DlColors.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DlColors.canvas)
    }
}

/// 「我的」Hub 骨架（对齐 MineHubScreen 外观，入口仅登录可用）
struct MineHubPlaceholder: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("我的")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DlColors.ink)
                Text("账号 · 工具 · 关于")
                    .font(.system(size: 13))
                    .foregroundStyle(DlColors.inkMuted)
                    .padding(.bottom, 4)

                section("账号") {
                    hubRow("一键登陆", ready: true) { vm.openOneKeyLogin(); vm.shellTab = 0 }
                    hubRow("扫码登陆", ready: true) { vm.openScanLogin(); vm.shellTab = 0 }
                    hubRow("退出登陆", ready: true) { vm.logout() }
                }
                section("工具") {
                    hubRow("代玩记录", ready: false) {}
                    hubRow("书签", ready: false) {}
                    hubRow("背包查询", ready: false) {}
                }
                section("关于") {
                    hubRow("关于大乐斗", ready: false) {}
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(DlColors.canvas)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DlColors.inkSecondary)
                .padding(.top, 8)
            content()
        }
    }

    private func hubRow(_ label: String, ready: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ready ? DlColors.ink : DlColors.inkMuted)
                Spacer()
                if !ready {
                    Text("待接")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DlColors.inkMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(DlColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DlColors.border.opacity(0.8), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
    }
}

/// 菜单 sheet：本切片只接登录；其余灰显
struct ShellMenuSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("已接") {
                    Button("一键登陆") { dismiss(); vm.openOneKeyLogin(); vm.shellTab = 0 }
                    Button("扫码登陆") { dismiss(); vm.openScanLogin(); vm.shellTab = 0 }
                    Button("退出登陆", role: .destructive) { dismiss(); vm.logout() }
                }
                Section("按 APK 待接") {
                    Text("活跃代玩 / 领奖报名 / 代玩设置 / 后台任务…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("菜单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
