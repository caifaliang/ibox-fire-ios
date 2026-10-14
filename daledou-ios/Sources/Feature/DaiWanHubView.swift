import SwiftUI

/// 代玩-记录（daiwan_ui）：对齐 Android `DaiWanHubScreen`。
struct DaiWanHubView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = DaiWanRunner.shared
    @ObservedObject private var logStore = TaskLogStore.shared
    @State private var hubOn = FeatureToggleStore.shared.isEnabled("daiwan_ui")
    @State private var typeOn: [Bool] = DaiWanCatalog.autoDaiWanTypes.indices.map {
        FeatureToggleStore.shared.isEnabled(DaiWanCatalog.typeId($0))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("聚合代玩（跑下方已开子项）", isOn: $hubOn)
                        .onChange(of: hubOn) { v in
                            FeatureToggleStore.shared.setEnabled("daiwan_ui", v)
                        }
                    Button {
                        runner.runHub(cookie: vm.session.cookieHeader)
                    } label: {
                        HStack {
                            Text(runner.running ? "执行中…" : "立即执行代玩")
                            Spacer()
                            if runner.running {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(runner.running)
                }

                Section("子类型（L4 全表）") {
                    ForEach(DaiWanCatalog.autoDaiWanTypes.indices, id: \.self) { i in
                        Toggle(DaiWanCatalog.autoDaiWanTypes[i], isOn: Binding(
                            get: { typeOn.indices.contains(i) ? typeOn[i] : false },
                            set: { v in
                                if typeOn.indices.contains(i) { typeOn[i] = v }
                                FeatureToggleStore.shared.setEnabled(DaiWanCatalog.typeId(i), v)
                            }
                        ))
                    }
                }

                Section("最近日志") {
                    if logStore.snapshot.isEmpty {
                        Text("无").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(logStore.snapshot)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button("清空日志", role: .destructive) { logStore.clear() }
                    if runner.running {
                        Button("停止", role: .destructive) { runner.stop() }
                    }
                }

                Section {
                    Text("已接：报名手机武林、报名群侠。其余子类型执行时记 stub，战斗循环后续切片逐项补。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("代玩-记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
