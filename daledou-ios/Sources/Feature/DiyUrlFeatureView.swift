import SwiftUI

/// 真源：`DiyUrlFeatureScreen` — 定时代玩 / 定时任务 URL 列表。
struct DiyUrlFeatureView: View {
    let featureId: String
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    @State private var urls: String = ""
    @State private var tip = ""
    @State private var busy = false
    @State private var tick = 0

    private let store = FeatureToggleStore.shared

    private var title: String {
        featureId == "diy_auto_daiwan" ? "定时自定义代玩" : "定时自定义任务"
    }

    private var listening: Bool {
        runner.isActive(featureId) || store.isEnabled(featureId)
    }

    var body: some View {
        let _ = tick
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("每行一条腾讯 CGI 完整 URL（phonepk/petpk）。非腾讯域将被拦截。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)

                Toggle("加入后台轮询", isOn: Binding(
                    get: { listening },
                    set: { on in
                        if on { runner.start(featureId) } else { runner.stop(featureId) }
                        tick &+= 1
                    }
                ))
                .font(.system(size: 14, weight: .medium))

                TextEditor(text: $urls)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(DlColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DlColors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onChange(of: urls) { v in
                        store.setString(featureId, "urls", v)
                    }

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
                        .lineLimit(6)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(DlColors.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if let onClose { onClose() } else { dismiss() }
                    }
                }
            }
            .onAppear {
                urls = store.getString(featureId, "urls")
            }
        }
    }

    private func runOnce() async {
        busy = true
        defer { busy = false }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        store.setString(featureId, "urls", urls)
        tip = await DiyUrlActions.run(featureId: featureId, cookie: cookie) { line in
            Task { @MainActor in
                TaskLogStore.shared.append(title, line)
            }
        }
    }
}
