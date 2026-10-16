import SwiftUI

/// 真源：`CheckboxSettingsScreen(renwu)` — 任务设置 + 立即执行/后台轮询。
struct RenWuView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let store = RenWuStore.shared
    private let fid = RenWuActions.fid

    @State private var query = ""
    @State private var tip = ""
    @State private var busy = false
    @State private var tick = 0

    private var listening: Bool {
        runner.isActive(fid) || FeatureToggleStore.shared.isEnabled(fid)
    }

    private var visible: [SettingSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return RenWuSettingDefs.sections.compactMap { sec in
            if q.isEmpty { return sec }
            let items = sec.items.filter {
                $0.label.lowercased().contains(q) || $0.key.lowercased().contains(q)
            }
            guard !items.isEmpty else { return nil }
            return SettingSection(title: sec.title, items: items)
        }
    }

    var body: some View {
        let _ = tick
        NavigationStack {
            VStack(spacing: 0) {
                Text("勾选后可后台轮询：日常强化(兵法/神装/专精) + 一键完成 / 帮派 / 门派 / 游记 / 押镖。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                TextField("搜索设置项", text: $query)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(DlColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DlColors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Toggle("加入后台轮询", isOn: Binding(
                    get: { listening },
                    set: { on in
                        if on { runner.start(fid) } else { runner.stop(fid) }
                        tick &+= 1
                    }
                ))
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visible) { section in
                            sectionBlock(section)
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
                        .padding(.horizontal, 4)

                        if !tip.isEmpty {
                            Text(tip)
                                .font(.system(size: 12))
                                .foregroundStyle(DlColors.inkSecondary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)
                }
            }
            .background(DlColors.canvas)
            .navigationTitle("任务设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBlock(_ section: SettingSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DlColors.ink)
                .padding(.horizontal, 4)

            let texts = section.items.filter { $0.kind == .text }
            let checks = section.items.filter { $0.kind == .check }

            ForEach(texts) { item in
                TextField(item.label, text: textBinding(item.key))
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(DlColors.canvas)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 4)
            }

            ForEach(chunk(checks, size: 3), id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row) { item in
                        checkCell(item, peers: checks)
                    }
                    if row.count < 3 {
                        ForEach(0..<(3 - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(DlColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DlColors.border.opacity(0.8), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func checkCell(_ item: SettingItem, peers: [SettingItem]) -> some View {
        let on = store.on(item.key)
        return Button {
            toggle(item, peers: peers, to: !on)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(on ? DlColors.accentBlue : DlColors.inkMuted)
                Text(item.label)
                    .font(.system(size: 11))
                    .foregroundStyle(DlColors.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ item: SettingItem, peers: [SettingItem], to value: Bool) {
        if let group = item.radioGroup, value {
            for p in peers where p.radioGroup == group {
                store.set(p.key, p.key == item.key)
            }
        } else {
            store.set(item.key, value)
        }
        tick &+= 1
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { store.text(key) },
            set: { store.setText(key, $0); tick &+= 1 }
        )
    }

    private func chunk<T>(_ arr: [T], size: Int) -> [[T]] {
        stride(from: 0, to: arr.count, by: size).map {
            Array(arr[$0..<min($0 + size, arr.count)])
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
        tip = await RenWuActions.farm(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("任务", line) }
        }
    }
}
