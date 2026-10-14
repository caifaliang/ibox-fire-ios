import SwiftUI

/// 活跃代玩设置 + 一键执行（M13）。
struct HuoYueView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = HuoYueRunner.shared
    @ObservedObject private var logStore = TaskLogStore.shared
    @State private var query = ""
    @State private var refresh = 0

    private var store: HuoYueStore { HuoYueStore.shared }

    private var estimated: Int {
        _ = refresh
        return LivenessCatalog.estimatePoints { store.on($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("预估活跃分（已勾且已接线）：\(estimated)")
                        .font(.subheadline.weight(.medium))
                    TextField("搜索", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        runner.start(cookie: vm.session.cookieHeader)
                    } label: {
                        HStack {
                            Text(runner.running ? "执行中…" : "一键活跃")
                            Spacer()
                            if runner.running { ProgressView() }
                        }
                    }
                    .disabled(runner.running)
                    if runner.running {
                        Button("停止", role: .destructive) { runner.stop() }
                    }
                }

                Section("官方活跃 20 条") {
                    ForEach(filteredEntries) { e in
                        if e.displayOnly {
                            HStack {
                                Text(e.title)
                                Spacer()
                                Text("仅展示").font(.caption2).foregroundStyle(.secondary)
                            }
                        } else if let key = e.storeKey {
                            Toggle(isOn: binding(key)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(e.index). \(e.title)")
                                    Text("+\(e.points) 分").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("大厅 / 前置 / 其它") {
                    ForEach(filteredExtras, id: \.key) { t in
                        Toggle(t.label, isOn: binding(t.key))
                    }
                }

                Section("最近日志") {
                    Text(logStore.snapshot.isEmpty ? "无" : logStore.snapshot)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    Button("清空日志", role: .destructive) { logStore.clear() }
                }

                Section {
                    Text("已接：同门/武林/分享/镶嵌、大厅小游戏、押镖、任务页、活跃礼包。乐斗目标池战斗下一切片。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("活跃代玩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var filteredEntries: [LivenessCatalogEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return LivenessCatalog.entries }
        return LivenessCatalog.entries.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || ($0.storeKey?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var filteredExtras: [(key: String, label: String, defaultOn: Bool)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return LivenessCatalog.extraToggles }
        return LivenessCatalog.extraToggles.filter {
            $0.label.localizedCaseInsensitiveContains(q) || $0.key.localizedCaseInsensitiveContains(q)
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: {
                _ = refresh
                return store.on(key)
            },
            set: { v in
                store.set(key, v)
                refresh += 1
            }
        )
    }
}
