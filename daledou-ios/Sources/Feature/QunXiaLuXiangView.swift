import SwiftUI

/// 真源：`QunXiaLuXiangScreen` — 武器/赛区 chips + 可回放列表。
struct QunXiaLuXiangView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var weapon = 0
    @State private var region = 0
    @State private var period = 0
    @State private var slots: [QunXiaActions.Slot] = []
    @State private var tip = ""
    @State private var loading = false
    @State private var autoSave = FeatureToggleStore.shared.getBool("qunxia_luxiang", "cb_start")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chipRow(QunXiaActions.weapons, selected: weapon) { weapon = $0 }
                chipRow(QunXiaActions.regions, selected: region) { region = $0 }

                HStack {
                    Text(loading ? "加载中…" : tip)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.84, green: 0.71, blue: 0.43))
                        .lineLimit(1)
                    Spacer()
                    Button("刷新") { Task { await reload(force: true) } }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.54))
                        .disabled(loading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Toggle("自动保存赛季数据", isOn: $autoSave)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .onChange(of: autoSave) { v in
                        FeatureToggleStore.shared.setBool("qunxia_luxiang", "cb_start", v)
                        FeatureToggleStore.shared.setEnabled("qunxia_luxiang", v)
                    }

                if slots.isEmpty {
                    Text(
                        period <= 0
                            ? "请先在游戏点「查看上届各赛区8强赛况」，再点悬浮「群侠录像」"
                            : "本赛区暂无录像（换武器/赛区，或确认已出8强）"
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.84, green: 0.71, blue: 0.43))
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(slots) { slot in
                        Button {
                            play(slot)
                        } label: {
                            HStack {
                                Text(slot.name.isEmpty ? "对阵" : slot.name)
                                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.84))
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(Color(red: 0.88, green: 0.48, blue: 0.18))
                            }
                        }
                        .listRowBackground(Color(red: 0.43, green: 0.10, blue: 0.14))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.23, green: 0.05, blue: 0.09))
            .navigationTitle(period > 0 ? "第\(period)届笑傲群侠赛况" : "群侠录像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if let seed = QunXiaActions.parseTopIdFromUrl(vm.qunXiaSeedUrl) {
                    weapon = seed.weapon
                    region = seed.region
                }
                await reload(force: true)
            }
            .onChange(of: weapon) { _ in Task { await reload(force: false) } }
            .onChange(of: region) { _ in Task { await reload(force: false) } }
        }
    }

    private func chipRow(_ labels: [String], selected: Int, onSelect: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, name in
                    Button {
                        onSelect(i)
                    } label: {
                        Text(name)
                            .font(.system(size: 12, weight: selected == i ? .semibold : .regular))
                            .foregroundStyle(selected == i ? Color(red: 0.23, green: 0.05, blue: 0.09) : Color(red: 0.84, green: 0.71, blue: 0.43))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected == i ? Color(red: 0.91, green: 0.76, blue: 0.35) : Color(red: 0.43, green: 0.10, blue: 0.14))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func reload(force: Bool) async {
        _ = force
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        let pack = await QunXiaActions.load(
            seedUrl: vm.qunXiaSeedUrl,
            weapon: weapon,
            region: region,
            cookie: cookie
        ) { line in
            Task { @MainActor in TaskLogStore.shared.append("群侠录像", line) }
        }
        period = pack.period
        slots = pack.slots
        tip = pack.tip
    }

    private func play(_ slot: QunXiaActions.Slot) {
        dismiss()
        let url = QunXiaActions.replayPetUrl(replayId: slot.replayId)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            vm.openOfficialAnimation(from: url)
        }
    }
}
