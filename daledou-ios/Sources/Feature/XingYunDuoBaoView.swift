import SwiftUI

/// 真源：`XydbScreen` — 道具名 + 每种购买次数。
struct XingYunDuoBaoView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = XingYunDuoBaoActions.fid
    private let store = FeatureToggleStore.shared

    @State private var auto = true
    @State private var names = ""
    @State private var count = "1"
    @State private var tip = ""
    @State private var busy = false
    @State private var tick = 0

    private var listening: Bool {
        runner.isActive(fid) || store.isEnabled(fid)
    }

    var body: some View {
        let _ = tick
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("按名称匹配 christmaslottery 列表并购买。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)

                Toggle("自动夺宝", isOn: $auto)
                    .font(.system(size: 14))
                    .onChange(of: auto) { v in store.setBool(fid, "auto", v) }

                field("道具名（逗号分隔）", $names)
                field("每种购买次数", $count)

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
                Spacer()
            }
            .padding(16)
            .background(DlColors.canvas)
            .navigationTitle("幸运夺宝")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                auto = store.getBool(fid, "auto", default: true)
                names = store.getString(fid, "ed_names")
                count = store.getString(fid, "ed_count", default: "1")
            }
            .onDisappear { persist() }
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DlColors.inkSecondary)
            TextField(title, text: text)
                .font(.system(size: 14))
                .padding(10)
                .background(DlColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                .onChange(of: text.wrappedValue) { _ in persist() }
        }
    }

    private func persist() {
        store.setBool(fid, "auto", auto)
        store.setString(fid, "ed_names", names)
        store.setString(fid, "ed_count", count)
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
        tip = await XingYunDuoBaoActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("幸运夺宝", line) }
        }
    }
}
