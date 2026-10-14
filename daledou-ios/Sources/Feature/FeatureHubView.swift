import SwiftUI

/// M7：功能中心 — 对齐 Android 三区目录；未移植项进占位。
struct FeatureHubView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var placeholderItem: FeatureItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.session.isLoggedIn
                                  ? "QQ \(vm.qqLabel.isEmpty ? "…" : vm.qqLabel)"
                                  : "未登陆")
                                .font(.headline)
                            Text("功能中心 · 按模块接入中")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    hubQuickButton("进入游戏首页") {
                        dismiss()
                        vm.openGameHome()
                    }
                    hubQuickButton("刷新页面") {
                        dismiss()
                        vm.reload()
                    }
                    hubQuickButton("粘贴 Cookie（高级）") {
                        dismiss()
                        vm.openCookieLoginSheet()
                    }
                } header: {
                    Text("快捷")
                }

                ForEach(FeatureMenuSection.allCases) { section in
                    Section {
                        ForEach(FeatureCatalog.items(in: section)) { item in
                            Button {
                                handleTap(item)
                            } label: {
                                featureRow(item)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.rawValue)
                            if let sub = section.subtitle {
                                Text(sub)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("功能中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $placeholderItem) { item in
                FeaturePlaceholderView(item: item)
            }
        }
    }

    private func hubQuickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func featureRow(_ item: FeatureItem) -> some View {
        HStack(spacing: 10) {
            Text(item.label)
                .font(item.emphasize ? .body.weight(.semibold) : .body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            statusChip(item.portStatus)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusChip(_ status: FeaturePortStatus) -> some View {
        switch status {
        case .ready:
            Text("可用")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        case .partial:
            Text("部分")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.14))
                .clipShape(Capsule())
        case .upcoming:
            Text("即将")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
    }

    private func handleTap(_ item: FeatureItem) {
        switch vm.openFeature(id: item.id) {
        case .handled:
            // 账号切换另开 sheet：先关中心会抢 presentation，稍后再关
            // 另开 sheet 的功能：稍后再关中心，避免 presentation 冲突
            let sheetIds: Set<String> = [
                "account_switch", "shuqian", "beibao", "chaqu",
            ]
            if sheetIds.contains(item.id) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    dismiss()
                }
            } else {
                dismiss()
            }
        case .needsPlaceholder:
            placeholderItem = item
        }
    }
}

struct FeaturePlaceholderView: View {
    let item: FeatureItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.pageTitle)
                    .font(.title2.weight(.semibold))
                Text("此功能尚未接入 iOS。")
                    .foregroundStyle(.secondary)
                Text("Android 功能 id：`\(item.id)`")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                Text("将按 docs/porting/MODULES.md 逐项移植；当前版本可先用游戏壳 + 一键/扫码登录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .navigationTitle("即将接入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
