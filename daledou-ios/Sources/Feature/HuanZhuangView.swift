import SwiftUI

/// 换装：装扮方案 1–5 + 本地配置（侠士 / 头像可编辑并应用）。
struct HuanZhuangView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tip = ""
    @State private var busy = false
    @State private var loading = false
    @State private var tick = 0
    @State private var withXingPan = FeatureToggleStore.shared.getBool("huoyue", "cb_yjhz_xp")
    @State private var configs: [LoadoutConfig] = []
    @State private var active = 0
    @State private var knights: [LoadoutOpt] = []
    @State private var avatars: [LoadoutOpt] = []

    private let t = FeatureToggleStore.shared

    private var selectedPlan: Int {
        for i in 1...5 where t.getBool("huoyue", "rb_yjhz_\(i)") { return i }
        return 1
    }

    var body: some View {
        let _ = tick
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("装扮方案仍走一键换装。本页可保存多套配置，并设置侠士 / 头像后点应用。专精、奥义、佣兵、附魔开关已预留，编辑器下一片接入。")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkMuted)

                    Text("装扮方案")
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { i in
                            Button("方案\(i)") {
                                for j in 1...5 {
                                    t.setBool("huoyue", "rb_yjhz_\(j)", j == i)
                                }
                                tick &+= 1
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selectedPlan == i ? .white : DlColors.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedPlan == i ? DlColors.accentBlue : DlColors.surface)
                            .clipShape(Capsule())
                        }
                    }

                    Toggle("同时执行星盘换装（若已配置）", isOn: $withXingPan)
                        .font(.system(size: 13))
                        .onChange(of: withXingPan) { v in
                            t.setBool("huoyue", "cb_yjhz_xp", v)
                        }

                    configBar
                    if configs.indices.contains(active) {
                        configEditor
                    }

                    Button {
                        Task { await apply() }
                    } label: {
                        Text(busy ? "换装中…" : "应用方案 \(selectedPlan)")
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
                    }
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("换装")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loading ? "…" : "刷新") { Task { await reload(prefill: true) } }
                        .disabled(loading || busy)
                }
            }
            .onAppear {
                let snap = LoadoutStore.load()
                configs = snap.configs
                active = snap.active
                Task { await reload(prefill: true) }
            }
        }
    }

    private var configBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(configs.enumerated()), id: \.element.id) { i, c in
                        Button(c.name.isEmpty ? "配置\(i + 1)" : c.name) {
                            active = i
                            persist()
                        }
                        .font(.system(size: 14, weight: i == active ? .semibold : .regular))
                        .foregroundStyle(i == active ? DlColors.accentBlue : DlColors.inkSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                outline("新增", enabled: configs.count < 8) {
                    configs.append(.empty(name: "配置\(configs.count + 1)"))
                    active = configs.count - 1
                    persist()
                }
                outline("删除", enabled: configs.count > 1) {
                    configs.remove(at: active)
                    active = min(active, configs.count - 1)
                    persist()
                }
            }
        }
    }

    @ViewBuilder
    private var configEditor: some View {
        let cfg = configs[active]
        VStack(alignment: .leading, spacing: 10) {
            TextField("配置名", text: binding(\.name))
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(DlColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DlColors.border, lineWidth: 1))

            Text("打开开关才会在应用时生效")
                .font(.system(size: 11))
                .foregroundStyle(DlColors.inkMuted)

            ForEach(LoadoutConfig.sections, id: \.self) { key in
                Toggle(isOn: enabledBinding(key)) {
                    HStack {
                        Text(key)
                        if !LoadoutConfig.wiredSections.contains(key) {
                            Text("待接入")
                                .font(.system(size: 10))
                                .foregroundStyle(DlColors.inkMuted)
                        }
                    }
                }
                .font(.system(size: 13))
                .disabled(!LoadoutConfig.wiredSections.contains(key))
            }

            pickRow(title: "侠士·位置1", token: cfg.knight["0"] ?? "", opts: knights, allowSkip: "不设置侠士") { token in
                configs[active].knight["0"] = token
                persist()
            }
            pickRow(title: "侠士·位置2", token: cfg.knight["1"] ?? "", opts: knights, allowSkip: "不设置侠士") { token in
                configs[active].knight["1"] = token
                persist()
            }
            pickRow(title: "头像", token: cfg.avatar, opts: avatars, allowSkip: nil) { token in
                configs[active].avatar = token
                persist()
            }
        }
    }

    private func pickRow(
        title: String,
        token: String,
        opts: [LoadoutOpt],
        allowSkip: String?,
        onPick: @escaping (String) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(DlColors.ink)
            Spacer()
            Menu {
                if let allowSkip {
                    Button(allowSkip) { onPick("0|\(allowSkip)") }
                }
                ForEach(opts) { o in
                    Button(o.detail.isEmpty ? o.name : "\(o.name) · \(o.detail)") {
                        onPick(LoadoutActions.token(o.id, o.name))
                    }
                }
            } label: {
                Text(token.isEmpty ? "点选" : LoadoutActions.tokenName(token))
                    .font(.system(size: 13))
                    .foregroundStyle(DlColors.accentBlue)
                    .lineLimit(1)
            }
        }
    }

    private func outline(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(enabled ? DlColors.accentBlue : DlColors.inkMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(enabled ? DlColors.accentBlue : DlColors.border, lineWidth: 1))
            .disabled(!enabled)
            .buttonStyle(.plain)
    }

    private func binding(_ keyPath: WritableKeyPath<LoadoutConfig, String>) -> Binding<String> {
        Binding(
            get: { configs.indices.contains(active) ? configs[active][keyPath: keyPath] : "" },
            set: { v in
                guard configs.indices.contains(active) else { return }
                configs[active][keyPath: keyPath] = v
                persist()
            }
        )
    }

    private func enabledBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { configs.indices.contains(active) ? (configs[active].enabled[key] ?? true) : true },
            set: { v in
                guard configs.indices.contains(active) else { return }
                configs[active].enabled[key] = v
                persist()
            }
        )
    }

    private func persist() {
        LoadoutStore.save(.init(configs: configs, active: active))
    }

    private func reload(prefill: Bool) async {
        loading = true
        defer { loading = false }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录后再刷新侠士 / 头像"
            return
        }
        let ks = await LoadoutActions.fetchKnights(cookie: cookie)
        let av = await LoadoutActions.fetchAvatars(cookie: cookie)
        knights = ks
        avatars = av.opts
        if prefill {
            for i in configs.indices {
                for k in ks {
                    guard let pos = Int(k.extra), pos == 0 || pos == 1 else { continue }
                    if (configs[i].knight["\(pos)"] ?? "").isEmpty {
                        configs[i].knight["\(pos)"] = LoadoutActions.token(k.id, k.name)
                    }
                }
                if configs[i].avatar.isEmpty, let cur = av.current {
                    configs[i].avatar = LoadoutActions.token(cur.id, cur.name)
                }
            }
            persist()
        }
        tip = "侠士 \(ks.count) · 头像 \(av.opts.count)"
    }

    private func apply() async {
        busy = true
        defer { busy = false }
        var parts: [String] = []
        parts.append(await MoreExtraActions.farmYiJianHuanZhuang { line in
            Task { @MainActor in TaskLogStore.shared.append("换装", line) }
        })
        let cookie = SessionStore.shared.cookieHeader
        if configs.indices.contains(active), LoginURLs.hasGameSession(cookie) {
            let cfg = configs[active]
            let extra = await LoadoutActions.applyWired(cfg: cfg, cookie: cookie) { line in
                TaskLogStore.shared.append("换装", line)
            }
            if !extra.isEmpty { parts.append(extra) }
        }
        tip = parts.filter { !$0.isEmpty }.joined(separator: "；")
    }
}
