import SwiftUI

/// 真源：`DouDouMallScreen` — 道具名 / 赠送 QQ / 刷新与购买次数。
struct DouDouMallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = DouDouMallActions.fid
    private let store = FeatureToggleStore.shared

    @State private var name = ""
    @State private var songQq = ""
    @State private var shuaXin = "10"
    @State private var number = "1"
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
                Text("按「、」匹配货架商品；加入购物车后结算并赠送红包。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)

                field("道具名称（顿号分隔）", $name)
                field("红包赠送 QQ", $songQq)
                field("最大刷新次数", $shuaXin)
                field("最大购买次数", $number)

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
                        .lineLimit(8)
                }
                Spacer()
            }
            .padding(16)
            .background(DlColors.canvas)
            .navigationTitle("斗豆红包商城")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                name = store.getString(fid, "name")
                songQq = store.getString(fid, "song_qq")
                shuaXin = store.getString(fid, "shua_xin", default: "10")
                number = store.getString(fid, "number", default: "1")
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: text.wrappedValue) { _ in persist() }
        }
    }

    private func persist() {
        store.setString(fid, "name", name)
        store.setString(fid, "song_qq", songQq)
        store.setString(fid, "shua_xin", shuaXin)
        store.setString(fid, "number", number)
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
        tip = await DouDouMallActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("斗豆商城", line) }
        }
    }
}
