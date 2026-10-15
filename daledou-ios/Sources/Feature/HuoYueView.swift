import SwiftUI

/// 真源：`OpenKdAndSettingsScreens` + `SettingPageDefs.huoYue`
struct HuoYueView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = HuoYueRunner.shared
    @State private var query = ""
    @State private var bucket = "全部"
    @State private var tick = 0

    private let store = HuoYueStore.shared

    private var visible: [SettingSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return HuoYueSettingDefs.sections.compactMap { sec in
            guard HuoYueSettingDefs.matchesBucket(sec, bucket) else { return nil }
            if q.isEmpty { return sec }
            let items = sec.items.filter {
                $0.label.lowercased().contains(q) || $0.key.lowercased().contains(q)
            }
            guard !items.isEmpty else { return nil }
            return SettingSection(title: sec.title, items: items)
        }
    }

    private var estimate: Int {
        _ = tick
        return LivenessCatalog.estimatePoints { store.on($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("勾选的功能，有些需要自己点击设置按钮去设置一下；不设置可能导致一键代玩失败。单选项同组互斥。")
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                HStack(spacing: 10) {
                    Button("全选") { applyVisible(true) }
                    Button("取消全选") { applyVisible(false) }
                    Spacer()
                    Text("估分 \(estimate)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DlColors.accentBlue)
                }
                .font(.system(size: 13))
                .foregroundStyle(DlColors.inkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                TextField("搜索设置项", text: $query)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(DlColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DlColors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(HuoYueSettingDefs.bucketNames, id: \.self) { name in
                            let on = bucket == name
                            Text(name)
                                .font(.system(size: 12, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Color.white : DlColors.inkMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(on ? DlColors.accentBlue : Color(red: 0.91, green: 0.925, blue: 0.95))
                                .clipShape(Capsule())
                                .onTapGesture { bucket = name }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if visible.isEmpty {
                            Text("没有匹配的设置项")
                                .font(.system(size: 13))
                                .foregroundStyle(DlColors.inkMuted)
                                .padding(16)
                        } else {
                            ForEach(visible) { section in
                                sectionBlock(section)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)
                }
            }
            .background(DlColors.canvas)
            .navigationTitle("活跃代玩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if runner.running {
                        runner.stop()
                    } else {
                        let cookie = SessionStore.shared.cookieHeader
                        runner.start(cookie: cookie)
                        dismiss()
                    }
                } label: {
                    Text(runner.running ? "停止一键活跃" : "立即跑一键活跃")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(runner.running ? Color.orange : DlColors.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DlColors.canvas.opacity(0.96))
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
                .padding(.top, 4)

            let texts = section.items.filter { $0.kind == .text }
            let checks = section.items.filter { $0.kind == .check }

            ForEach(texts) { item in
                TextField(item.label, text: textBinding(item.key))
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(DlColors.surface)
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
            .padding(.vertical, 4)
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

    private func applyVisible(_ on: Bool) {
        for sec in visible {
            for item in sec.items where item.kind == .check {
                if on, item.radioGroup != nil { continue }
                store.set(item.key, on)
            }
        }
        tick &+= 1
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { FeatureToggleStore.shared.getString(HuoYueStore.feature, key) },
            set: { FeatureToggleStore.shared.setString(HuoYueStore.feature, key, $0); tick &+= 1 }
        )
    }

    private func chunk<T>(_ arr: [T], size: Int) -> [[T]] {
        stride(from: 0, to: arr.count, by: size).map {
            Array(arr[$0..<min($0 + size, arr.count)])
        }
    }
}
