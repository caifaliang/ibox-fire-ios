import SwiftUI

/// 对齐 APK `MineHubScreen` + `ShellCatalog.mine`。
struct MineHubView: View {
    @EnvironmentObject var vm: AppViewModel

    private var grouped: [(String, [ShellCatalog.HubEntry])] {
        var order: [String] = []
        var map: [String: [ShellCatalog.HubEntry]] = [:]
        for e in ShellCatalog.mine {
            if map[e.section] == nil {
                order.append(e.section)
                map[e.section] = []
            }
            map[e.section, default: []].append(e)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

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

                ForEach(grouped, id: \.0) { section, list in
                    Text(section)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DlColors.inkSecondary)
                        .padding(.top, 8)
                    ForEach(list) { entry in
                        let wired = FeatureCatalog.item(id: entry.featureId)?.iosWired == true
                        Button {
                            vm.openFeature(id: entry.featureId)
                        } label: {
                            HStack {
                                Text(entry.label)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(wired ? DlColors.ink : DlColors.inkMuted)
                                Spacer()
                                if !wired {
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
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(DlColors.canvas)
    }
}
