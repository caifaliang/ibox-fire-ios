import SwiftUI

/// 代玩设置（daiwan）：本切片用 L4 子类型开关；完整 SettingPageDefs 细项后续补。
struct DaiWanSettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = DaiWanRunner.shared
    @ObservedObject private var logStore = TaskLogStore.shared
    @State private var listening = FeatureToggleStore.shared.isEnabled("daiwan")
    @State private var query = ""
    @State private var typeOn: [Bool] = DaiWanCatalog.autoDaiWanTypes.indices.map {
        FeatureToggleStore.shared.isEnabled(DaiWanCatalog.typeId($0))
    }

    private var filteredIndices: [Int] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return DaiWanCatalog.autoDaiWanTypes.indices.filter { i in
            q.isEmpty || DaiWanCatalog.autoDaiWanTypes[i].localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("勾选子类型后点「立即执行」。细粒度历练/会武选项（Android SettingPageDefs）后续切片接入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("加入后台轮询标记", isOn: $listening)
                        .onChange(of: listening) { v in
                            FeatureToggleStore.shared.setEnabled("daiwan", v)
                        }
                    TextField("搜索设置项", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        // 与 hub 相同：按 L4 已开子项跑
                        FeatureToggleStore.shared.setEnabled("daiwan_ui", true)
                        runner.runHub(cookie: vm.session.cookieHeader)
                    } label: {
                        HStack {
                            Text(runner.running ? "执行中…" : "立即执行一次")
                            Spacer()
                            if runner.running { ProgressView() }
                        }
                    }
                    .disabled(runner.running)
                }

                Section("代玩子类型") {
                    ForEach(filteredIndices, id: \.self) { i in
                        Toggle(DaiWanCatalog.autoDaiWanTypes[i], isOn: Binding(
                            get: { typeOn.indices.contains(i) ? typeOn[i] : false },
                            set: { v in
                                if typeOn.indices.contains(i) { typeOn[i] = v }
                                FeatureToggleStore.shared.setEnabled(DaiWanCatalog.typeId(i), v)
                            }
                        ))
                    }
                    if filteredIndices.isEmpty {
                        Text("没有匹配的设置项").foregroundStyle(.secondary)
                    }
                }

                Section("最近日志") {
                    Text(logStore.snapshot.isEmpty ? "无" : logStore.snapshot)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("代玩设置(下滑更多)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
