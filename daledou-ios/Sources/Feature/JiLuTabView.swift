import SwiftUI

/// 真源：`JiLuScreen` — 底栏「记录」：武林/侠士月历 + 历史/商会快照。
struct JiLuTabView: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var store = JiLuRankStore.shared

    private let tabs = ["武林", "侠士记录", "历史记录", "商会记录"]
    @State private var tab = 0
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var tip = ""
    @State private var syncing = false
    @State private var pickDay: JiLuDay?

    private var cookie: String { SessionStore.shared.cookieHeader }
    private var qq: String {
        LoginURLs.extractQq(cookie) ?? store.accountUin
    }

    var body: some View {
        let _ = store.revision
        VStack(spacing: 0) {
            header
            tabBar
            Group {
                switch tab {
                case 0: rankPane(kind: .wuLin)
                case 1: rankPane(kind: .qunXia)
                case 2: historyPane
                default: shangHuiPane
                }
            }
        }
        .background(DlColors.canvas)
        .task(id: tab) { await autoSync() }
        .onAppear {
            store.bindAccount(uin: qq, nameHint: vm.qqLabel)
        }
        .confirmationDialog(
            "设置名次",
            isPresented: Binding(
                get: { pickDay != nil },
                set: { if !$0 { pickDay = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let day = pickDay {
                ForEach(JiLuRanks.all, id: \.self) { rank in
                    Button(rank) {
                        let kind: JiLuKind = tab == 0 ? .wuLin : .qunXia
                        store.setDayRank(kind: kind, year: year, month: month, day: day.index, rank: rank)
                        pickDay = nil
                    }
                }
                Button("取消", role: .cancel) { pickDay = nil }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(store.userName.isEmpty ? "记录" : store.userName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DlColors.ink)
            Spacer()
            if !tip.isEmpty {
                Text(tip)
                    .font(.system(size: 11))
                    .foregroundStyle(DlColors.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DlColors.surface)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button {
                        tab = i
                    } label: {
                        Text(tabs[i])
                            .font(.system(size: 13, weight: tab == i ? .semibold : .medium))
                            .foregroundStyle(tab == i ? DlColors.accentBlue : DlColors.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(DlColors.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DlColors.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func rankPane(kind: JiLuKind) -> some View {
        let monthData = store.loadMonth(kind: kind, year: year, month: month)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                monthNav
                syncRow
                weekdayHeader
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(monthData.list.enumerated()), id: \.offset) { _, cell in
                        dayCell(cell)
                    }
                }
                countsBlock(monthData)
                boxesBlock(kind: kind, monthData: monthData)
            }
            .padding(12)
        }
    }

    private var monthNav: some View {
        HStack {
            Button("上个月") {
                if month <= 1 { year -= 1; month = 12 } else { month -= 1 }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DlColors.accentBlue)
            Spacer()
            Text("\(year)年\(month)月")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DlColors.ink)
            Spacer()
            Button("下个月") {
                if month >= 12 { year += 1; month = 1 } else { month += 1 }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DlColors.accentBlue)
        }
    }

    private var syncRow: some View {
        Button {
            Task { await manualSync() }
        } label: {
            Text(syncing ? "同步中…" : "同步今日")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(syncing ? DlColors.inkMuted : DlColors.accentBlue)
                .clipShape(Capsule())
        }
        .disabled(syncing)
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                Text(w)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DlColors.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ cell: JiLuDay) -> some View {
        Group {
            if cell.index <= 0 {
                Color.clear.frame(height: 44)
            } else {
                Button {
                    pickDay = cell
                } label: {
                    VStack(spacing: 2) {
                        Text("\(cell.index)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DlColors.ink)
                        Text(cell.type.isEmpty ? " " : cell.type)
                            .font(.system(size: 9))
                            .foregroundStyle(DlColors.accentBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DlColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border.opacity(0.7), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func countsBlock(_ monthData: JiLuMonth) -> some View {
        let items = JiLuRanks.counted.compactMap { k -> (String, Int)? in
            let n = monthData.counts[k] ?? 0
            return n > 0 ? (k, n) : nil
        }
        return Group {
            if !items.isEmpty {
                Text("本月名次")
                    .font(.system(size: 13, weight: .semibold))
                Text(items.map { "\($0.0)×\($0.1)" }.joined(separator: "  "))
                    .font(.system(size: 12))
                    .foregroundStyle(DlColors.inkSecondary)
            }
        }
    }

    private func boxesBlock(kind: JiLuKind, monthData: JiLuMonth) -> some View {
        let labels: [(Int, String)] = {
            switch kind {
            case .wuLin: return JiLuBoxes.wuLinLabels.enumerated().map { ($0.offset, $0.element) }
            case .qunXia: return JiLuBoxes.qunXiaLabels
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text("材料估算")
                .font(.system(size: 13, weight: .semibold))
            ForEach(labels, id: \.0) { idx, label in
                let n = idx < monthData.boxes.count ? monthData.boxes[idx] : 0
                HStack {
                    Text(label).font(.system(size: 12)).foregroundStyle(DlColors.inkSecondary)
                    Spacer()
                    Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundStyle(DlColors.ink)
                }
            }
        }
        .padding(10)
        .background(DlColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var historyPane: some View {
        let map = store.loadLiShiMonth(year: year, month: month)
        let rows = map.values.sorted { $0.day > $1.day }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                monthNav
                syncRow
                if rows.isEmpty {
                    Text("暂无历史快照，点「同步今日」拉取 visit/viewattr")
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.inkMuted)
                        .padding(.top, 20)
                } else {
                    ForEach(rows, id: \.day) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(month)月\(row.day)日 · \(row.name)")
                                .font(.system(size: 13, weight: .semibold))
                            Text("帮派 \(row.bangPai.ifBlank("—")) · 等级 \(row.dengJi.ifBlank("—")) · 战力 \(row.zhanLi.ifBlank("—"))")
                                .font(.system(size: 12))
                                .foregroundStyle(DlColors.inkSecondary)
                            Text("经验 \(row.exp.ifBlank("—"))")
                                .font(.system(size: 12))
                                .foregroundStyle(DlColors.inkMuted)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DlColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(12)
        }
    }

    private var shangHuiPane: some View {
        let map = store.loadShangHuiMonth(year: year, month: month)
        let rows = map.values.sorted { $0.day > $1.day }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                monthNav
                syncRow
                if rows.isEmpty {
                    Text("暂无商会礼包记录，点「同步今日」拉取 fac_corp")
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.inkMuted)
                        .padding(.top, 20)
                } else {
                    ForEach(rows, id: \.day) { row in
                        HStack {
                            Text("\(month)月\(row.day)日")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("全帮礼包 \(row.totalGiftNum)")
                                .font(.system(size: 13))
                                .foregroundStyle(DlColors.accentBlue)
                        }
                        .padding(10)
                        .background(DlColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(12)
        }
    }

    private func autoSync() async {
        await manualSync(silent: tip.isEmpty)
    }

    private func manualSync(silent: Bool = false) async {
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        if syncing { return }
        syncing = true
        defer { syncing = false }
        store.bindAccount(uin: qq, nameHint: vm.qqLabel)
        switch tab {
        case 0, 1:
            let kind: JiLuKind = tab == 0 ? .wuLin : .qunXia
            let r = tab == 0
                ? await JiLuFetchers.syncWuLin(cookie: cookie)
                : await JiLuFetchers.syncQunXia(cookie: cookie)
            if r.ok, !r.rank.isEmpty, r.day > 0 {
                store.setDayRank(kind: kind, year: r.year, month: r.month, day: r.day, rank: r.rank)
                year = r.year
                month = r.month
            }
            if !silent || !r.ok { tip = r.tip }
        case 2:
            let r = await JiLuFetchers.fetchTodayHistory(cookie: cookie, uin: qq)
            if r.ok, let day = r.day {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
                let now = Date()
                year = cal.component(.year, from: now)
                month = cal.component(.month, from: now)
                store.saveLiShiDay(year: year, month: month, day: day)
            }
            if !silent || !r.ok { tip = r.tip }
        default:
            let r = await JiLuFetchers.fetchShangHuiGift(cookie: cookie)
            if r.ok, let gift = r.giftNum {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
                let now = Date()
                year = cal.component(.year, from: now)
                month = cal.component(.month, from: now)
                let day = cal.component(.day, from: now)
                store.saveShangHuiDay(
                    year: year, month: month,
                    day: ShangHuiDay(day: day, totalGiftNum: gift, updateTime: Date().timeIntervalSince1970)
                )
            }
            if !silent || !r.ok { tip = r.tip }
        }
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
