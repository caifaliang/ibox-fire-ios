import SwiftUI

/// 领奖报名设置 + 一键领奖（M14）。
struct LingJiangView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = LingJiangRunner.shared
    @ObservedObject private var logStore = TaskLogStore.shared
    @State private var query = ""
    @State private var refresh = 0

    private var store: LingJiangStore { LingJiangStore.shared }

    private var rows: [(cb: String, title: String, protocolKey: String)] {
        _ = refresh
        let all = LingJiangCatalog.checkboxRows()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.cb.localizedCaseInsensitiveContains(q)
                || $0.protocolKey.localizedCaseInsensitiveContains(q)
        }
    }

    private var checkedCount: Int {
        _ = refresh
        return LingJiangCatalog.checkboxRows().filter {
            store.isChecked($0.cb, default: LingJiangStore.defaultCheckboxes.contains($0.cb))
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("协议 \(LingJiangCatalog.items().count) 项 · 已勾 \(checkedCount)")
                        .font(.subheadline.weight(.medium))
                    TextField("搜索领奖项", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        runner.start(cookie: vm.session.cookieHeader)
                    } label: {
                        HStack {
                            Text(runner.running ? "执行中…" : "一键领奖")
                            Spacer()
                            if runner.running { ProgressView() }
                        }
                    }
                    .disabled(runner.running)
                    if runner.running {
                        Button("停止", role: .destructive) { runner.stop() }
                    }
                    Button("仅勾默认日礼 6 项") {
                        for row in LingJiangCatalog.checkboxRows() {
                            store.setChecked(row.cb, LingJiangStore.defaultCheckboxes.contains(row.cb))
                        }
                        refresh += 1
                    }
                }

                Section("勾选项") {
                    if LingJiangCatalog.items().isEmpty {
                        Text("协议表未加载").foregroundStyle(.secondary)
                    }
                    ForEach(rows, id: \.cb) { row in
                        Toggle(isOn: binding(row.cb)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(.subheadline)
                                Text(row.cb).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if rows.isEmpty {
                        Text("没有匹配项").foregroundStyle(.secondary)
                    }
                }

                Section("最近日志") {
                    Text(logStore.snapshot.isEmpty ? "无" : logStore.snapshot)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    Button("清空日志", role: .destructive) { logStore.clear() }
                }

                Section {
                    Text("已接：keymap 静态 URL / 随机 / 格式化；飞升·巅峰·结拜·盟主报名。需 QQ 列表的邀请类本切片跳过。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("自动领奖报名设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func binding(_ cb: String) -> Binding<Bool> {
        Binding(
            get: {
                _ = refresh
                return store.isChecked(cb, default: LingJiangStore.defaultCheckboxes.contains(cb))
            },
            set: { v in
                store.setChecked(cb, v)
                refresh += 1
            }
        )
    }
}
