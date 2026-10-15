import SwiftUI

/// 对齐 APK `MainMenuScreen`：QQ 条 + 三栏分区网格。
struct MainMenuView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    headerCard
                    ForEach(MenuSection.allCases) { section in
                        sectionBlock(section)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .padding(.bottom, 16)
            }
            .background(DlColors.canvas)
            .navigationTitle("菜单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.shellDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DlColors.ink)
                    .lineLimit(1)
                Text(vm.backgroundEnabled ? "后台 · \(vm.backgroundIntervalSec)s" : "后台关")
                    .font(.system(size: 11))
                    .foregroundStyle(DlColors.inkSecondary)
            }
            Spacer()
            Toggle("", isOn: $vm.backgroundEnabled)
                .labelsHidden()
                .tint(DlColors.brand)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DlColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DlColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionBlock(_ section: MenuSection) -> some View {
        let items = FeatureCatalog.items(in: section)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DlColors.brand)
                    .frame(width: 2, height: 12)
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DlColors.ink)
                if let sub = section.subtitle {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(DlColors.inkMuted)
                        .lineLimit(1)
                }
            }
            let rows = chunk(items, size: 3)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { item in
                        featureTile(item)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count < 3 {
                        ForEach(0..<(3 - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func featureTile(_ item: FeatureItem) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                vm.openFeature(id: item.id)
            }
        } label: {
            Text(item.label)
                .font(.system(size: item.wide ? 11 : 12, weight: item.emphasize ? .semibold : .medium))
                .foregroundStyle(item.iosWired ? DlColors.ink : DlColors.ink.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(item.wide ? 3 : 2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: item.wide ? 52 : 44)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(DlColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            item.emphasize ? DlColors.brand.opacity(0.35) : DlColors.border,
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func chunk<T>(_ arr: [T], size: Int) -> [[T]] {
        stride(from: 0, to: arr.count, by: size).map {
            Array(arr[$0..<min($0 + size, arr.count)])
        }
    }
}
