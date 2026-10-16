import SwiftUI

/// 真源：`XianShiQiangGouScreen` — 商品 id / 提前分钟 / 组数。
struct XianShiQiangGouView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = XianShiQiangGouActions.fid
    private let store = FeatureToggleStore.shared

    @State private var goodsId = ""
    @State private var early = "1"
    @State private var zong = "1"
    @State private var dan = "1"
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
                Text("每天 18:00 开抢；可提前 N 分钟进入等待。需 Cookie 含 accessToken。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)

                field("商品 ID", $goodsId)
                field("提前几分钟", $early)
                field("购买总组数", $zong)
                field("单组数量", $dan)

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
            .navigationTitle("限时抢购")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                goodsId = store.getString(fid, "id")
                early = store.getString(fid, "time", default: "1")
                zong = store.getString(fid, "count_zong", default: "1")
                dan = store.getString(fid, "count_dan", default: "1")
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
        store.setString(fid, "id", goodsId)
        store.setString(fid, "time", early)
        store.setString(fid, "count_zong", zong)
        store.setString(fid, "count_dan", dan)
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
        tip = await XianShiQiangGouActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("限时抢购", line) }
        }
    }
}
