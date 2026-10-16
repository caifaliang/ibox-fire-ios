import SwiftUI

/// 真源：`SettingPageDefs.paoMaDeng` + 后台轮询。
struct PaoMaDengView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = PaoMaDengActions.fid
    private let store = FeatureToggleStore.shared

    private let sections: [(String, [(String, String)])] = [
        ("客栈事件", [
            ("cb_kz_xxzs", "自动寻衅滋事"),
            ("cb_kz_tjdj", "拒绝特价道具"),
            ("cb_kz_jhdj", "自动交换道具"),
            ("cb_kz_fq_jhdj", "放弃不满足条件的黑市商人"),
        ]),
        ("每日乱斗任务", [
            ("cb_ld_lq", "任务完成后自动领奖"),
            ("cb_ld_qdp", "自动做抢地盘任务"),
        ]),
        ("每日日常任务", [
            ("cb_rc_lq", "任务完成后自动领奖"),
        ]),
        ("黄历-斗神塔双倍", [
            ("cb_hl_dst", "斗神塔双倍掉落时拉满次数"),
        ]),
        ("黄历-主动乐斗经验双倍", [
            ("cb_hl_pldy", "经验双倍时批量斗友打满"),
            ("cb_hl_pldy_not_x", "经验双倍时批量斗友(不用药剂)"),
        ]),
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("定时检查黄历/乱斗/客栈等；勾选后可后台轮询。")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkMuted)

                    ForEach(sections, id: \.0) { title, items in
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DlColors.inkMuted)
                        ForEach(items, id: \.0) { key, label in
                            Toggle(label, isOn: Binding(
                                get: { flags[key] ?? false },
                                set: { flags[key] = $0; persist() }
                            ))
                            .font(.system(size: 13))
                        }
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
            .navigationTitle("跑马灯设置")
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
        for (_, items) in sections {
            for (k, _) in items { m[k] = store.getBool(fid, k) }
        }
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
        tip = await PaoMaDengActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("跑马灯", line) }
        }
    }
}
