import SwiftUI

/// 真源：`BangPaiWaKuangScreen` — 吃药/佣兵/祭坛/商会勾选项。
struct BangPaiWaKuangView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = BangPaiWaKuangActions.fid
    private let store = FeatureToggleStore.shared

    private let checks: [(String, String)] = [
        ("cb_da_tie", "百炼钢打铁"),
        ("cb_dlw_z", "大力丸(赠)"),
        ("cb_xjz_z", "迅捷珠(赠)"),
        ("cb_fzx_z", "风之息(赠)"),
        ("cb_dlw", "大力丸"),
        ("cb_xjz", "迅捷珠"),
        ("cb_fzx", "风之息"),
        ("cb_yong_bing", "自动换挖矿佣兵"),
        ("cb_yong_bing_ct", "自动换常态佣兵"),
        ("cb_ji_tan", "祭坛"),
        ("cb_shang_hui", "商会礼包"),
    ]

    @State private var flags: [String: Bool] = [:]
    @State private var ybWk1 = ""
    @State private var ybWk2 = ""
    @State private var ybCt1 = ""
    @State private var ybCt2 = ""
    @State private var tip = ""
    @State private var busy = false
    @State private var tick = 0

    private var listening: Bool {
        runner.isActive(fid) || store.isEnabled(fid)
    }

    var body: some View {
        let _ = tick
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("本号一轮：吃药→打铁→换佣兵→开矿/打怪/领奖→常态佣兵→祭坛→商会。")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkMuted)

                    ForEach(checks, id: \.0) { key, label in
                        Toggle(label, isOn: Binding(
                            get: { flags[key] ?? false },
                            set: { flags[key] = $0; persist() }
                        ))
                        .font(.system(size: 13))
                    }

                    Text("挖矿佣兵名")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 6)
                    field("挖矿佣兵1", $ybWk1)
                    field("挖矿佣兵2", $ybWk2)
                    Text("常态佣兵名")
                        .font(.system(size: 13, weight: .semibold))
                    field("常态佣兵1", $ybCt1)
                    field("常态佣兵2", $ybCt2)

                    Toggle("加入后台轮询", isOn: Binding(
                        get: { listening },
                        set: { on in
                            persist()
                            if on { runner.start(fid) } else { runner.stop(fid) }
                            tick &+= 1
                        }
                    ))
                    .font(.system(size: 14, weight: .medium))

                    Button {
                        Task { await runOnce() }
                    } label: {
                        Text(busy ? "执行中…" : "立即执行一次")
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
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("帮派挖矿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { load() }
            .onDisappear { persist() }
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.system(size: 14))
            .padding(10)
            .background(DlColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: text.wrappedValue) { _ in persist() }
    }

    private func load() {
        var m: [String: Bool] = [:]
        for (k, _) in checks { m[k] = store.getBool(fid, k) }
        flags = m
        ybWk1 = store.getString(fid, "yb_wk_1")
        ybWk2 = store.getString(fid, "yb_wk_2")
        ybCt1 = store.getString(fid, "yb_ct_1")
        ybCt2 = store.getString(fid, "yb_ct_2")
    }

    private func persist() {
        for (k, v) in flags { store.setBool(fid, k, v) }
        store.setString(fid, "yb_wk_1", ybWk1)
        store.setString(fid, "yb_wk_2", ybWk2)
        store.setString(fid, "yb_ct_1", ybCt1)
        store.setString(fid, "yb_ct_2", ybCt2)
    }

    private func runOnce() async {
        busy = true
        defer { busy = false }
        persist()
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        tip = await BangPaiWaKuangActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("帮派挖矿", line) }
        }
    }
}
