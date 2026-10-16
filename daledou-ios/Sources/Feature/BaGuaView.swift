import SwiftUI

/// 真源：`BgmzScreen` — 自动攻略 + 四层卦象。
struct BaGuaView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = BaGuaActions.fid
    private let store = FeatureToggleStore.shared

    @State private var auto = true
    @State private var tips = ""
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
                Text("自动攻略时按层走卦象（如：离、坤、兑、乾）；第 5 层领奖。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)

                Toggle("自动攻略", isOn: $auto)
                    .font(.system(size: 14))
                    .onChange(of: auto) { v in store.setBool(fid, "auto", v) }

                Text("今日攻略")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DlColors.inkSecondary)
                TextField("离、坤、兑、乾", text: $tips)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(DlColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                    .onChange(of: tips) { v in store.setString(fid, "ed_tips", v) }

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
            .navigationTitle("八卦迷阵")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                auto = store.getBool(fid, "auto", default: true)
                tips = store.getString(fid, "ed_tips")
            }
            .onDisappear { persist() }
        }
    }

    private func persist() {
        store.setBool(fid, "auto", auto)
        store.setString(fid, "ed_tips", tips)
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
        tip = await BaGuaActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("八卦迷阵", line) }
        }
    }
}
