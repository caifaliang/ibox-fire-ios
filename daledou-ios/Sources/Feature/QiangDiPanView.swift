import SwiftUI

/// 真源：`QiangDiPanScreen` — 等级/城管勾选 + 领奖/扫描。
struct QiangDiPanView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = "qiangdipan"
    private let store = FeatureToggleStore.shared

    private let checks: [(String, String, Bool)] = [
        ("cb_dp_1", "一级", true),
        ("cb_dp_2", "二级", true),
        ("cb_dp_3", "三级", true),
        ("cb_dp_4", "四级", true),
        ("cb_zhan_bai", "不打战败", false),
        ("cb_zd_fq", "领奖后放弃地盘", false),
        ("cb_boss", "只打城管", false),
    ]

    @State private var flags: [String: Bool] = [:]
    @State private var jingyan = ""
    @State private var zhanli = ""
    @State private var tip = "乱斗任务：暂无"
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
                    Text(tip)
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.inkSecondary)
                        .frame(maxWidth: .infinity)

                    Text("设置（对齐 recommendmanor 攻占）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DlColors.inkMuted)

                    ForEach(checks, id: \.0) { key, label, _ in
                        Toggle(label, isOn: Binding(
                            get: { flags[key] ?? false },
                            set: { flags[key] = $0; persist() }
                        ))
                        .font(.system(size: 13))
                    }

                    TextField("经验高于", text: $jingyan)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: jingyan) { _ in persist() }
                    TextField("战力低于", text: $zhanli)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: zhanli) { _ in persist() }

                    Toggle("加入后台轮询", isOn: Binding(
                        get: { listening },
                        set: { on in
                            persist()
                            if on { runner.start(fid) } else { runner.stop(fid) }
                            tick &+= 1
                        }
                    ))
                    .font(.system(size: 14, weight: .medium))

                    HStack(spacing: 10) {
                        Button {
                            Task { await claimReward() }
                        } label: {
                            Text("每日奖励")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(DlColors.accentBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(busy)
                        .buttonStyle(.plain)

                        Button {
                            Task { await runScan() }
                        } label: {
                            Text(busy ? "扫描中…" : "开始扫描")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(busy ? DlColors.inkMuted : DlColors.accentBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(busy)
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("抢地盘")
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
        for (k, _, def) in checks {
            m[k] = store.getBool(fid, k, default: def)
        }
        flags = m
        jingyan = store.getString(fid, "jingyan")
        zhanli = store.getString(fid, "zhanli")
    }

    private func persist() {
        for (k, v) in flags { store.setBool(fid, k, v) }
        store.setString(fid, "jingyan", jingyan)
        store.setString(fid, "zhanli", zhanli)
    }

    private func claimReward() async {
        busy = true
        defer { busy = false }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        let (_, body) = await LedouCGI.getPetPk(
            cmd: "get", extra: ["type": "1"], cookie: cookie
        )
        let msg = CombatLog.fromBody(body).ifBlankMe(String(body.prefix(120)))
        tip = msg
        TaskLogStore.shared.append("抢地盘", msg)
    }

    private func runScan() async {
        busy = true
        defer { busy = false }
        persist()
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        tip = await HuoYueCombat.farmQiangDiPan(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("抢地盘", line) }
        }
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
