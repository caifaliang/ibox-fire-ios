import SwiftUI

/// 真源：`QueryScreen` — 顶栏「查询」信息页（对齐 XinXiActivity 排版）。
struct QueryView: View {
    @Environment(\.dismiss) private var dismiss
    var initialUin: String = ""
    var autoQuery: Bool = false

    @State private var qqInput = ""
    @State private var loading = false
    @State private var profile: QueryProfile?
    @State private var error: String?
    @State private var tip = ""
    @State private var settings = QuerySettingsStore.shared.load()
    @State private var showSettings = false
    @State private var showCompare = false
    @State private var cmpLeft = ""
    @State private var cmpRight = ""
    @State private var cmpA: QueryProfile?
    @State private var cmpB: QueryProfile?
    @State private var cmpLoading = false

    private let blueHeader = Color(red: 0.08, green: 0.40, blue: 0.75)
    private let redAccent = Color(red: 0.78, green: 0.16, blue: 0.16)
    private let linkBlue = Color(red: 0.10, green: 0.46, blue: 0.82)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("请输入QQ号", text: Binding(
                        get: { qqInput },
                        set: { qqInput = $0.filter(\.isNumber) }
                    ))
                    .font(.system(size: 14))
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(DlColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    FlowActions(
                        loading: loading,
                        onAddFriend: { Task { await addFriend() } },
                        onAddWuLin: { addWuLin() },
                        onQuery: { Task { await doQuery() } },
                        onCompare: {
                            cmpLeft = SessionStore.shared.qq.filter(\.isNumber)
                            cmpRight = qqInput
                            showCompare = true
                        }
                    )

                    if !tip.isEmpty {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.inkSecondary)
                    }
                    if let error, !error.isEmpty {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(redAccent)
                    }

                    if loading {
                        ProgressView("查询中…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if let p = profile, p.cookieOk {
                        XinXiResultView(p: p, settings: settings)
                    }
                }
                .padding(12)
            }
            .background(DlColors.canvas)
            .navigationTitle("信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                QuerySettingsSheet(settings: $settings) {
                    QuerySettingsStore.shared.save(settings)
                }
            }
            .sheet(isPresented: $showCompare) {
                compareSheet
            }
            .onAppear {
                if qqInput.isEmpty {
                    let seed = initialUin.trimmingCharacters(in: .whitespacesAndNewlines)
                    qqInput = seed.isEmpty
                        ? SessionStore.shared.qq.filter(\.isNumber)
                        : seed.filter(\.isNumber)
                }
            }
            .task {
                if autoQuery, !qqInput.isEmpty {
                    await doQuery()
                }
            }
        }
    }

    private var compareSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("QQ 1", text: Binding(
                        get: { cmpLeft },
                        set: { cmpLeft = $0.filter(\.isNumber) }
                    ))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    TextField("QQ 2", text: Binding(
                        get: { cmpRight },
                        set: { cmpRight = $0.filter(\.isNumber) }
                    ))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await runCompare() }
                    } label: {
                        Text(cmpLoading ? "对比中…" : "开始对比")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(DlColors.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(cmpLoading)

                    if let a = cmpA, a.cookieOk, let b = cmpB, b.cookieOk {
                        CompareRow("昵称", a.header.nickname, b.header.nickname)
                        CompareRow("QQ", a.uin, b.uin)
                        CompareRow("等级", "\(a.header.level)", "\(b.header.level)")
                        CompareRow(
                            "战力",
                            QueryRepository.formatCombat(a.header.combat),
                            QueryRepository.formatCombat(b.header.combat)
                        )
                        let keys = Array(Set(
                            (a.powerLeft + a.powerRight + b.powerLeft + b.powerRight).map(\.0)
                        )).sorted()
                        let mapA = Dictionary(uniqueKeysWithValues: a.powerLeft + a.powerRight)
                        let mapB = Dictionary(uniqueKeysWithValues: b.powerLeft + b.powerRight)
                        ForEach(keys, id: \.self) { k in
                            CompareRow(k, mapA[k] ?? "", mapB[k] ?? "")
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("数据对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showCompare = false }
                }
            }
        }
    }

    private func doQuery() async {
        let uin = qqInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uin.isEmpty else {
            error = "请输入 QQ"
            return
        }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            error = "尚未登录"
            return
        }
        loading = true
        error = nil
        tip = ""
        defer { loading = false }
        let selfUin = SessionStore.shared.qq.filter(\.isNumber)
        let p = await QueryRepository.query(uin: uin, selfUin: selfUin, cookie: cookie)
        profile = p
        if !p.cookieOk {
            error = p.rawError
        }
    }

    private func addFriend() async {
        let uin = qqInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uin.isEmpty else {
            tip = "请输入 QQ"
            return
        }
        let cookie = SessionStore.shared.cookieHeader
        tip = await QueryRepository.addFriend(uin: uin, cookie: cookie)
    }

    private func addWuLin() {
        guard let p = profile, p.cookieOk else {
            tip = "请先查询再加入武林库"
            return
        }
        let uin = qqInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uin.isEmpty else {
            tip = "请输入 QQ"
            return
        }
        ChaQuStore.shared.upsertMerge(
            uin: uin,
            name: p.header.nickname,
            level: p.header.level,
            value: Int(p.header.combat / 10.0)
        )
        tip = "添加到武林库成功"
    }

    private func runCompare() async {
        let a = cmpLeft.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = cmpRight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else {
            tip = "请输入两个 QQ"
            return
        }
        let cookie = SessionStore.shared.cookieHeader
        let selfUin = SessionStore.shared.qq.filter(\.isNumber)
        cmpLoading = true
        defer { cmpLoading = false }
        async let ra = QueryRepository.query(uin: a, selfUin: selfUin, cookie: cookie)
        async let rb = QueryRepository.query(uin: b, selfUin: selfUin, cookie: cookie)
        cmpA = await ra
        cmpB = await rb
    }
}

// MARK: - Actions row

private struct FlowActions: View {
    let loading: Bool
    let onAddFriend: () -> Void
    let onAddWuLin: () -> Void
    let onQuery: () -> Void
    let onCompare: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            mini("加好友", onAddFriend)
            mini("加武林", onAddWuLin)
            Button(action: onQuery) {
                Group {
                    if loading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text("查询").font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(DlColors.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(loading)
            mini("对比", onCompare)
            Spacer(minLength: 0)
        }
    }

    private func mini(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.10, green: 0.46, blue: 0.82))
                .padding(.horizontal, 8)
                .frame(height: 34)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Result

private struct XinXiResultView: View {
    let p: QueryProfile
    let settings: QueryDisplaySettings
    private let blueHeader = Color(red: 0.08, green: 0.40, blue: 0.75)
    private let redAccent = Color(red: 0.78, green: 0.16, blue: 0.16)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            dashTitle("基本信息")
            Text(baseInfoText)
                .font(.system(size: 13))
                .foregroundStyle(DlColors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !p.mercTough.isEmpty {
                Text(p.mercTough)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(blueHeader)
            }
            if !p.xinxiBase.isEmpty {
                Text(p.xinxiBase)
                    .font(.system(size: 13))
                    .foregroundStyle(DlColors.ink)
            }

            if !p.weapons.isEmpty || !p.weaponSummary.isEmpty {
                weaponSummaryLine(p.weaponSummary)
            }

            if settings.showHuiZhang, !p.badges.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Array(p.badges.enumerated()), id: \.offset) { _, b in
                        VStack(spacing: 4) {
                            AsyncImage(url: URL(string: b.iconUrl)) { img in
                                img.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 36, height: 36)
                            Text("\(b.name) Lv\(b.level)")
                                .font(.system(size: 10))
                                .foregroundStyle(b.highlight ? redAccent : DlColors.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }

            ForEach(Array(p.weapons.enumerated()), id: \.offset) { _, w in
                weaponRow(w)
            }

            if settings.showJiNeng, !p.skillsHtmlLines.isEmpty {
                dashTitle("技能")
                Text(p.skillsHtmlLines.map(\.text).joined())
                    .font(.system(size: 13))
            }

            bodyPlain(p.mercOnField)
            if settings.showYongBingAll { bodyPlain(p.mercAll) }
            if settings.showYongBingTianFu { dashBody(p.mercTalent) }
            if settings.showYongBingZhuZhen { dashBody(p.mercFormation) }
            if settings.showJingMai { dashBody(p.jingMai) }
            if settings.showZhuanJing { dashBody(p.zhuanJing) }

            if !p.shenJiang.isEmpty {
                Text(p.shenJiang)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(blueHeader)
            }
            if !p.aoYi.isEmpty {
                Text(p.aoYi)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(blueHeader)
            }
            if settings.showTeShuJiNeng {
                dashBody(p.luanDou)
                bodyPlain(p.shenMo)
                let ding = p.shenMoDing
                bodyPlain(
                    (!ding.isEmpty && !ding.hasPrefix("神魔鼎")) ? "神魔鼎：\(ding)" : ding
                )
            }
            if settings.showShenZhuang { dashBody(p.shenZhuang) }

            if !p.powerLeft.isEmpty || !p.powerRight.isEmpty {
                dashTitle("战斗力明细")
                if !p.powerRank.isEmpty {
                    Text(p.powerRank).font(.system(size: 13))
                }
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(p.powerLeft.enumerated()), id: \.offset) { _, pair in
                            Text("\(pair.0)：\(pair.1)").font(.system(size: 12))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(p.powerRight.enumerated()), id: \.offset) { _, pair in
                            Text("\(pair.0)：\(pair.1)").font(.system(size: 12))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            dashBody(p.attrsText)
        }
    }

    private var baseInfoText: String {
        var s = ""
        s += "昵称：\(p.header.nickname)(\(p.uin))\n"
        s += "等级：\(p.header.level)\n"
        s += "战力：\(QueryRepository.formatCombat(p.header.combat))\n"
        if !p.baseAttrBlock.isEmpty {
            s += p.baseAttrBlock.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }
        if !p.header.menpai.isEmpty { s += "门派：\(p.header.menpai)\n" }
        if !p.header.arenaRank.isEmpty { s += "竞技分段：\(p.header.arenaRank)\n" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dashTitle(_ title: String) -> some View {
        Text("-----------\(title)-------------")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(blueHeader)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    @ViewBuilder
    private func bodyPlain(_ text: String) -> some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DlColors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func dashBody(_ text: String) -> some View {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            if body.hasPrefix("-----------") {
                let title = body
                    .components(separatedBy: "\n").first?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                    ?? ""
                let rest = body
                    .components(separatedBy: "\n")
                    .dropFirst()
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { dashTitle(title) }
                if !rest.isEmpty {
                    Text(rest)
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.ink)
                }
            } else {
                bodyPlain(body)
            }
        }
    }

    private func weaponSummaryLine(_ summary: String) -> some View {
        // 神器/淬火/仙化 数字标红
        let parts = summary.components(separatedBy: "，")
        return HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if i > 0 { Text("，").font(.system(size: 13)) }
                if let r = part.range(of: #"：(\d+)"#, options: .regularExpression) {
                    let prefix = String(part[..<r.lowerBound]) + "："
                    let num = String(part[r]).dropFirst()
                    Text(prefix).font(.system(size: 13))
                    Text(num).font(.system(size: 13, weight: .semibold)).foregroundStyle(redAccent)
                } else {
                    Text(part).font(.system(size: 13))
                }
            }
        }
    }

    private func weaponRow(_ w: WeaponItem) -> some View {
        let tint = Color(
            red: Double((w.color >> 16) & 0xFF) / 255,
            green: Double((w.color >> 8) & 0xFF) / 255,
            blue: Double(w.color & 0xFF) / 255
        )
        return HStack(alignment: .top, spacing: 8) {
            AsyncImage(url: URL(string: w.iconUrl)) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.gray.opacity(0.15)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.namePlain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                HStack(spacing: 4) {
                    if !w.qhXh.isEmpty { Text(w.qhXh).font(.system(size: 11)) }
                    if !w.damage.isEmpty { Text(w.damage).font(.system(size: 11)) }
                    if !w.hunzhu.isEmpty { Text(w.hunzhu).font(.system(size: 11)) }
                    if !w.mingke.isEmpty { Text(w.mingke).font(.system(size: 11)) }
                }
                .foregroundStyle(DlColors.inkSecondary)
                if settings.showWuQiFuShi, !w.fushi.isEmpty {
                    Text(w.fushi)
                        .font(.system(size: 11))
                        .foregroundStyle(DlColors.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings / Compare

private struct QuerySettingsSheet: View {
    @Binding var settings: QueryDisplaySettings
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("全部佣兵", isOn: bind(\.showYongBingAll))
                Toggle("师徒情比", isOn: bind(\.showStqb))
                Toggle("技能", isOn: bind(\.showJiNeng))
                Toggle("专精", isOn: bind(\.showZhuanJing))
                Toggle("武器符石", isOn: bind(\.showWuQiFuShi))
                Toggle("徽章", isOn: bind(\.showHuiZhang))
                Toggle("神装", isOn: bind(\.showShenZhuang))
                Toggle("特殊技能", isOn: bind(\.showTeShuJiNeng))
                Toggle("佣兵天赋", isOn: bind(\.showYongBingTianFu))
                Toggle("佣兵助阵", isOn: bind(\.showYongBingZhuZhen))
                Toggle("经脉", isOn: bind(\.showJingMai))
            }
            .navigationTitle("查询设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func bind(_ keyPath: WritableKeyPath<QueryDisplaySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                onChange()
            }
        )
    }
}

private struct CompareRow: View {
    let title: String
    let left: String
    let right: String

    init(_ title: String, _ left: String, _ right: String) {
        self.title = title
        self.left = left
        self.right = right
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 72, alignment: .leading)
            Text(left)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(right)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(left != right ? Color.red : DlColors.ink)
        }
        .padding(.vertical, 2)
    }
}
