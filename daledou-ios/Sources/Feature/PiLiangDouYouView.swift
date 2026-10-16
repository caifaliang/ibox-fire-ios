import SwiftUI

/// 批量斗友设置（featureId = piliang_douyou）。
struct PiLiangDouYouView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tip = ""
    @State private var busy = false
    @State private var tick = 0

    private let t = FeatureToggleStore.shared
    private let fid = "piliang_douyou"
    private let modes: [(String, String)] = [
        ("hy", "好友"), ("stqb", "师徒情拜"), ("by", "帮友"), ("msr", "陌生人"),
    ]

    var body: some View {
        let _ = tick
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("分类（空=读活跃代玩勾选，默认好友）")
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        ForEach(modes, id: \.0) { key, label in
                            Button(label) {
                                t.setString(fid, "mode", key)
                                tick &+= 1
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(t.getString(fid, "mode") == key ? .white : DlColors.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(t.getString(fid, "mode") == key ? DlColors.accentBlue : DlColors.surface)
                            .clipShape(Capsule())
                        }
                    }

                    Text("加载上限：\(PldyRoster.loadLimit())")
                        .font(.system(size: 13))
                    HStack(spacing: 6) {
                        ForEach(Array(PldyRoster.loadCounts.enumerated()), id: \.offset) { idx, n in
                            Button("\(n)") {
                                t.setInt(fid, "setting_pldy_type", idx)
                                tick &+= 1
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(t.getInt(fid, "setting_pldy_type") == idx ? .white : DlColors.accentBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(t.getInt(fid, "setting_pldy_type") == idx ? DlColors.accentBlue : DlColors.surface)
                            .clipShape(Capsule())
                        }
                    }

                    textField("最低等级", key: "min_dj", def: "1")
                    textField("最高等级", key: "max_dj", def: "300")
                    textField("战力上限", key: "max_zl", def: "5000")

                    toggle("只打神器", "cb_sq")
                    toggle("贡献满停止", "cb_gmt")
                    toggle("跳过惜败", "cb_sb")
                    toggle("自动分享", "cb_fx")
                    toggle("自动体力", "cb_tl_zd")
                    toggle("自动领贡献", "cb_gx_zd")
                    toggle("按等级排序", "cb_djpx")

                    Button {
                        Task { await runNow() }
                    } label: {
                        Text(busy ? "执行中…" : "立即执行")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(busy ? DlColors.inkMuted : DlColors.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(busy)
                    .buttonStyle(.plain)

                    if !tip.isEmpty {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.inkMuted)
                    }
                }
                .padding(14)
            }
            .background(DlColors.canvas)
            .navigationTitle("批量斗友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                if t.getString(fid, "min_dj").isEmpty { t.setString(fid, "min_dj", "1") }
                if t.getString(fid, "max_dj").isEmpty { t.setString(fid, "max_dj", "300") }
                if t.getString(fid, "max_zl").isEmpty { t.setString(fid, "max_zl", "5000") }
            }
        }
    }

    private func toggle(_ label: String, _ key: String) -> some View {
        Button {
            t.setBool(fid, key, !t.getBool(fid, key))
            tick &+= 1
        } label: {
            HStack {
                Image(systemName: t.getBool(fid, key) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(t.getBool(fid, key) ? DlColors.accentBlue : DlColors.inkMuted)
                Text(label).font(.system(size: 13)).foregroundStyle(DlColors.ink)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func textField(_ label: String, key: String, def: String) -> some View {
        TextField("\(label)(默认\(def))", text: Binding(
            get: { t.getString(fid, key) },
            set: { t.setString(fid, key, $0); tick &+= 1 }
        ))
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(DlColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func runNow() async {
        busy = true
        defer { busy = false }
        tip = await PiLiangDouYouActions.farm { line in
            Task { @MainActor in TaskLogStore.shared.append("批量斗友", line) }
        }
    }
}
