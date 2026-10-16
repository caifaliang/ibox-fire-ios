import SwiftUI

/// 真源：`WuLinChiYaoScreen` — 补药勾选项 + 后台轮询。
struct WuLinChiYaoView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = WuLinChiYaoActions.fid
    private let store = FeatureToggleStore.shared

    private let checks: [(String, String)] = [
        ("cb_dlw_z", "大力丸(赠)"),
        ("cb_xjz_z", "迅捷珠(赠)"),
        ("cb_fzx_z", "风之息(赠)"),
        ("cb_dlw", "大力丸"),
        ("cb_xjz", "迅捷珠"),
        ("cb_fzx", "风之息"),
        ("cb_hxs", "活血散"),
        ("cb_jsys", "减伤药水"),
        ("cb_thj", "土豪金"),
        ("cb_jcy", "金疮药"),
        ("cb_djcy", "大金疮药"),
        ("cb_bsjj", "宝石金戒"),
        ("cb_fcyj", "翡翠银戒"),
        ("cb_yhzz", "永恒紫钻"),
        ("cb_da_tie", "百炼钢打铁"),
        ("cb_not_0", "冠军后不执行监听"),
    ]

    @State private var flags: [String: Bool] = [:]
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
                    Text("totalinfo 显示剩 0 次（或缺 buff）时再 use。")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkMuted)

                    ForEach(checks, id: \.0) { key, label in
                        Toggle(label, isOn: Binding(
                            get: { flags[key] ?? false },
                            set: { flags[key] = $0; persist() }
                        ))
                        .font(.system(size: 13))
                    }

                    Toggle("加入后台轮询", isOn: Binding(
                        get: { listening },
                        set: { on in
                            persist()
                            if on { runner.start(fid) } else { runner.stop(fid) }
                            tick &+= 1
                        }
                    ))
                    .font(.system(size: 14, weight: .medium))
                    .padding(.top, 4)

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
            .navigationTitle("武林吃药")
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

    private func load() {
        var m: [String: Bool] = [:]
        for (k, _) in checks { m[k] = store.getBool(fid, k) }
        flags = m
    }

    private func persist() {
        for (k, v) in flags { store.setBool(fid, k, v) }
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
        tip = await WuLinChiYaoActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("武林吃药", line) }
        }
    }
}
