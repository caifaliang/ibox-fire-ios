import SwiftUI

/// 真源：`LongHuangScreen` — 位次/神器筛选 + 付费/补药选项。
struct LongHuangView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = LongHuangActions.fid
    private let store = FeatureToggleStore.shared

    private let checks: [(String, String, Bool)] = [
        ("cb_fu_fei", "使用付费次数", false),
        ("cb_not_shi_bai", "不打战败", false),
        ("cb_da_tie", "打铁", false),
        ("cb_close", "次数用完关闭", true),
        ("cb_li", "力(赠)", false),
        ("cb_min", "敏(赠)", false),
        ("cb_su", "速(赠)", false),
        ("cb_da_wan_mian_fei", "21:30后打完免费次数", false),
    ]

    @State private var flags: [String: Bool] = [:]
    @State private var weiCi = "1"
    @State private var shenMax = ""
    @State private var chuanMax = ""
    @State private var kangMax = ""
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
                    Text("每月 4–25 日 8:00–22:00；martial 列表 + dragonphoenix/pk。")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkMuted)

                    Text("筛选")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DlColors.inkMuted)

                    labeledField("目标位次(必填>0)", text: $weiCi)
                    labeledField("神器上限(0不限)", text: $shenMax)
                    labeledField("穿透上限(0不限)", text: $chuanMax)
                    labeledField("抗性上限(0不限)", text: $kangMax)

                    Text("选项")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DlColors.inkMuted)
                        .padding(.top, 4)

                    ForEach(checks, id: \.0) { key, label, _ in
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
            .navigationTitle("龙凰论武")
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

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(DlColors.inkMuted)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _ in persist() }
        }
    }

    private func load() {
        var m: [String: Bool] = [:]
        for (k, _, def) in checks {
            m[k] = store.getBool(fid, k, default: def)
        }
        flags = m
        weiCi = store.getString(fid, "ed_wei_ci", default: "1")
        shenMax = store.getString(fid, "ed_shen_max")
        chuanMax = store.getString(fid, "ed_chuan_max")
        kangMax = store.getString(fid, "ed_kang_max")
    }

    private func persist() {
        for (k, v) in flags { store.setBool(fid, k, v) }
        store.setString(fid, "ed_wei_ci", weiCi)
        store.setString(fid, "ed_shen_max", shenMax)
        store.setString(fid, "ed_chuan_max", chuanMax)
        store.setString(fid, "ed_kang_max", kangMax)
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
        tip = await LongHuangActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("龙凰论武", line) }
        }
    }
}
