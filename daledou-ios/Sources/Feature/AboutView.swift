import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("应用", value: "大乐斗")
                    LabeledContent("版本", value: "\(version) (\(build))")
                    LabeledContent("真源", value: "DaLedou_App_Dev")
                }
                Section {
                    Text("iOS 侧载自用。一键登录 / 扫码 / 官方动画已接；功能菜单按 APK 逐步完整接入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("关于大乐斗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
