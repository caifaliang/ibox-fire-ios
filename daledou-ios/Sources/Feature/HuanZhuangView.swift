import SwiftUI

/// 换装 MVP：装扮方案 1–5 一键应用（对齐 phonepk outfit op=1）。
struct HuanZhuangView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tip = ""
    @State private var busy = false
    @State private var tick = 0
    @State private var withXingPan = FeatureToggleStore.shared.getBool("huoyue", "cb_yjhz_xp")

    private let t = FeatureToggleStore.shared

    private var selectedPlan: Int {
        for i in 1...5 where t.getBool("huoyue", "rb_yjhz_\(i)") { return i }
        return 1
    }

    var body: some View {
        let _ = tick
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("选择装扮方案后点应用。神将/佣兵/专精编辑器尚未接入。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)

                Text("方案")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { i in
                        Button("方案\(i)") {
                            for j in 1...5 {
                                t.setBool("huoyue", "rb_yjhz_\(j)", j == i)
                            }
                            tick &+= 1
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedPlan == i ? .white : DlColors.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedPlan == i ? DlColors.accentBlue : DlColors.surface)
                        .clipShape(Capsule())
                    }
                }

                Toggle("同时执行星盘换装（若已配置）", isOn: $withXingPan)
                    .font(.system(size: 13))
                    .onChange(of: withXingPan) { v in
                        t.setBool("huoyue", "cb_yjhz_xp", v)
                    }

                Button {
                    Task { await apply() }
                } label: {
                    Text(busy ? "换装中…" : "应用方案 \(selectedPlan)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(busy ? DlColors.inkMuted : DlColors.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(busy)
                .buttonStyle(.plain)

                if !tip.isEmpty {
                    Text(tip)
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkSecondary)
                }
                Spacer()
            }
            .padding(16)
            .background(DlColors.canvas)
            .navigationTitle("换装")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func apply() async {
        busy = true
        defer { busy = false }
        tip = await MoreExtraActions.farmYiJianHuanZhuang { line in
            Task { @MainActor in TaskLogStore.shared.append("换装", line) }
        }
    }
}
