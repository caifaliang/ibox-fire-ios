import SwiftUI

struct BookmarkView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = BookmarkStore.shared
    @State private var tip = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("每行一条腾讯 CGI 完整 URL（phonepk/petpk）。打开后在游戏壳内加载。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("URL 列表") {
                    TextEditor(text: $store.urlsText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 180)
                }
                if !store.lines.isEmpty {
                    Section("快速打开") {
                        ForEach(store.lines, id: \.self) { line in
                            Button(line) { open(line) }
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
                if !tip.isEmpty {
                    Section { Text(tip).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("打开首行") {
                        if let first = store.lines.first {
                            open(first)
                        } else {
                            tip = "请先填写 URL"
                        }
                    }
                }
            }
        }
    }

    private func open(_ raw: String) {
        guard let url = URL(string: raw), LedouCGI.isAllowedHost(url.host) else {
            tip = "域名非法或非腾讯"
            return
        }
        vm.openExternalGameURL(url)
        tip = "已在游戏壳打开"
        dismiss()
    }
}
