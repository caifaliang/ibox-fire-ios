import SwiftUI

/// 真源：`ZiDongQiangHuaScreen` — 神装 / 专精 / 奥义 / 神魔 / 铭刻。
struct ZiDongQiangHuaView: View {
    @Environment(\.dismiss) private var dismiss
    private let t = FeatureToggleStore.shared
    private let fid = QiangHuaActions.fid

    @State private var tab = 0
    @State private var szMode = 0
    @State private var szSlot = 0
    @State private var szSkill = 0
    @State private var zjType = 0
    @State private var smId = 1
    @State private var aoyiUrl = ""
    @State private var mkUrl = ""
    @State private var autoBuy = false
    @State private var slots: [QiangHuaActions.SlotInfo] = []
    @State private var loading = false
    @State private var busy = false
    @State private var tip = ""
    @State private var logs: [String] = []

    private let tabs = ["神装", "专精", "奥义", "神魔", "铭刻"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("自动兑材料", isOn: $autoBuy)
                            .font(.system(size: 13))
                            .onChange(of: autoBuy) { v in t.setBool(fid, "auto_materials", v) }

                        switch tab {
                        case 0: shenZhuangPanel
                        case 1: zhuanJingPanel
                        case 2: urlPanel(
                            title: "奥义强化",
                            hint: "填写奥义强化完整 URL（腾讯域名）",
                            text: $aoyiUrl,
                            key: "aoyi_url",
                            label: "奥义"
                        )
                        case 3: shenMoPanel
                        default: urlPanel(
                            title: "铭刻强化",
                            hint: "填写铭刻强化完整 URL",
                            text: $mkUrl,
                            key: "mk_url",
                            label: "铭刻"
                        )
                        }

                        if !tip.isEmpty {
                            Text(tip)
                                .font(.system(size: 12))
                                .foregroundStyle(DlColors.inkSecondary)
                        }

                        if !logs.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最近记录")
                                    .font(.system(size: 13, weight: .medium))
                                ForEach(Array(logs.prefix(10).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 11))
                                        .foregroundStyle(DlColors.inkMuted)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(14)
                }

                Divider()
                HStack {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { i, name in
                        Button {
                            tab = i
                        } label: {
                            Text(name)
                                .font(.system(size: 12, weight: tab == i ? .semibold : .regular))
                                .foregroundStyle(tab == i ? DlColors.accentBlue : DlColors.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(DlColors.surface)
            }
            .background(DlColors.canvas)
            .navigationTitle("自动强化")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(busy || loading)
                }
            }
            .task { loadPrefs(); await reload() }
        }
    }

    // MARK: - Panels

    private var shenZhuangPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                modeChip("神装", 0)
                modeChip("技能", 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { i in
                        let s = slots.indices.contains(i) ? slots[i] : nil
                        Button {
                            szSlot = i
                            t.setInt(fid, "sz_slot", i)
                        } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(QiangHuaActions.slots[i])
                                        .font(.system(size: 13, weight: szSlot == i ? .semibold : .regular))
                                        .foregroundStyle(szSlot == i ? DlColors.accentBlue : DlColors.inkSecondary)
                                    if let s, s.level > 0 {
                                        Text("\(s.level)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(DlColors.ink)
                                            .padding(4)
                                            .background(Color(red: 0.96, green: 0.77, blue: 0.26))
                                            .clipShape(Circle())
                                    }
                                }
                                Rectangle()
                                    .fill(szSlot == i ? DlColors.accentBlue : Color.clear)
                                    .frame(width: 36, height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                }
            }

            let selected = slots.indices.contains(szSlot) ? slots[szSlot] : nil
            VStack(alignment: .leading, spacing: 8) {
                if loading && selected == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let selected {
                    Text(selected.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text("战力 \(selected.fc.ifBlankMe("—")) · Lv\(selected.level)")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkSecondary)
                    if !selected.goodName.isEmpty {
                        Text("\(selected.goodName) 需\(selected.goodNeed) 有\(selected.goodHave)")
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.inkMuted)
                    }
                    if szMode == 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { i in
                                Button("技能\(i + 1)") {
                                    szSkill = i
                                    t.setInt(fid, "sz_skill", i)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(szSkill == i ? .white : DlColors.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(szSkill == i ? DlColors.accentBlue : DlColors.surface)
                                .clipShape(Capsule())
                                .disabled(busy)
                            }
                        }
                    }
                    if selected.maxed && szMode == 0 {
                        Text("已达最高等级")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DlColors.inkMuted)
                    } else {
                        HStack(spacing: 8) {
                            actionBtn("强化1次") {
                                await run("强化1次") {
                                    await QiangHuaActions.enhanceShenZhuang(
                                        slot: szSlot, mode: szMode, skillIdx: szSkill,
                                        once: true, autoBuy: autoBuy, cookie: cookie, onLog: log
                                    )
                                }
                            }
                            actionBtn("强化10次", outline: true) {
                                await run("强化10次") {
                                    await QiangHuaActions.enhanceShenZhuang(
                                        slot: szSlot, mode: szMode, skillIdx: szSkill,
                                        once: false, autoBuy: autoBuy, cookie: cookie, onLog: log
                                    )
                                }
                            }
                        }
                    }
                } else {
                    Text("暂无神装数据，点右上角刷新")
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.inkMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DlColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var zhuanJingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("专精强化")
                .font(.system(size: 14, weight: .semibold))
            ForEach(Array(QiangHuaActions.zjTypes.enumerated()), id: \.offset) { i, name in
                Button {
                    zjType = i
                    t.setInt(fid, "zj_type", i)
                } label: {
                    HStack {
                        Text(name).foregroundStyle(DlColors.ink)
                        Spacer()
                        if zjType == i {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DlColors.accentBlue)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            HStack(spacing: 8) {
                actionBtn("强化1次") {
                    await run("专精1") {
                        await QiangHuaActions.enhanceZhuanJing(
                            typeId: zjType, times: 1, autoBuy: autoBuy, cookie: cookie, onLog: log
                        )
                    }
                }
                actionBtn("强化10次", outline: true) {
                    await run("专精10") {
                        await QiangHuaActions.enhanceZhuanJing(
                            typeId: zjType, times: 10, autoBuy: autoBuy, cookie: cookie, onLog: log
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(DlColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var shenMoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("神魔录")
                .font(.system(size: 14, weight: .semibold))
            ForEach(Array(QiangHuaActions.smNames.enumerated()), id: \.offset) { i, name in
                Button {
                    smId = i + 1
                    t.setInt(fid, "sm_id", i + 1)
                } label: {
                    HStack {
                        Text(name).foregroundStyle(DlColors.ink)
                        Spacer()
                        if smId == i + 1 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DlColors.accentBlue)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            HStack(spacing: 8) {
                actionBtn("查询", outline: true) {
                    await run("神魔查询") {
                        await QiangHuaActions.queryShenMo(id: smId, cookie: cookie, onLog: log)
                    }
                }
                actionBtn("升级1次") {
                    await run("神魔升级") {
                        await QiangHuaActions.upgradeShenMo(
                            id: smId, autoBuy: autoBuy, cookie: cookie, onLog: log
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(DlColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func urlPanel(
        title: String,
        hint: String,
        text: Binding<String>,
        key: String,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(DlColors.inkMuted)
            TextField("\(label) URL", text: text)
                .font(.system(size: 13))
                .padding(10)
                .background(DlColors.canvas)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DlColors.border, lineWidth: 1))
                .onChange(of: text.wrappedValue) { v in
                    t.setString(fid, key, v)
                }
            actionBtn("执行强化") {
                await run(label) {
                    await QiangHuaActions.enhanceByUrl(
                        url: text.wrappedValue, label: label, cookie: cookie, onLog: log
                    )
                }
            }
        }
        .padding(12)
        .background(DlColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bits

    private func modeChip(_ title: String, _ mode: Int) -> some View {
        Button {
            szMode = mode
            t.setInt(fid, "sz_mode", mode)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(szMode == mode ? DlColors.ink : DlColors.inkSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(szMode == mode ? Color(red: 1, green: 0.95, blue: 0.77) : DlColors.surface)
                .overlay(
                    Capsule().stroke(
                        szMode == mode ? Color(red: 0.94, green: 0.84, blue: 0.55) : DlColors.border,
                        lineWidth: 1
                    )
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func actionBtn(
        _ title: String,
        outline: Bool = false,
        _ action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(outline ? DlColors.accentBlue : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(outline ? DlColors.surface : (busy ? DlColors.inkMuted : DlColors.accentBlue))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(outline ? DlColors.accentBlue : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var cookie: String { SessionStore.shared.cookieHeader }

    private func loadPrefs() {
        szMode = t.getInt(fid, "sz_mode").clamped(to: 0...1)
        szSlot = t.getInt(fid, "sz_slot").clamped(to: 0...5)
        szSkill = t.getInt(fid, "sz_skill").clamped(to: 0...2)
        zjType = t.getInt(fid, "zj_type").clamped(to: 0...3)
        smId = max(1, min(4, t.getInt(fid, "sm_id", default: 1)))
        aoyiUrl = t.getString(fid, "aoyi_url")
        mkUrl = t.getString(fid, "mk_url")
        autoBuy = t.getBool(fid, "auto_materials")
    }

    private func reload() async {
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        loading = true
        defer { loading = false }
        slots = await QiangHuaActions.loadSlots(cookie: cookie)
    }

    private func log(_ line: String) {
        Task { @MainActor in
            TaskLogStore.shared.append("自动强化", line)
        }
    }

    private func run(_ label: String, _ block: () async -> String) async {
        guard !busy else { return }
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        busy = true
        tip = label
        defer { busy = false }
        let msg = await block()
        tip = msg
        logs.insert(msg, at: 0)
        if logs.count > 10 { logs = Array(logs.prefix(10)) }
        if tab == 0 { await reload() }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
