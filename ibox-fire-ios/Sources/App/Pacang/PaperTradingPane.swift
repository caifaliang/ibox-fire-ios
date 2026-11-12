import SwiftUI

private let creamCard = Color(red: 1, green: 0.988, blue: 0.969) // #FFFCF7
private let creamLine = Color(red: 0.906, green: 0.878, blue: 0.831) // #E7E0D4
private let gold = Color(red: 0.769, green: 0.647, blue: 0.455) // #C4A574
private let sellFee = 0.045

/// 模拟仓整页：站点 /api/paper/* + 本机行情选品。
struct PaperTradingPane: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var loading = true
    @State private var busy = false
    @State private var tip = ""
    @State private var wallet: PaperWalletSnapshot?
    @State private var board: [PaperBoardRow] = []
    @State private var trades: [PaperTradeRow] = []
    @State private var catalog: [IboxMarketItem] = []
    @State private var buyKw = ""
    @State private var buyQty = "1"
    @State private var selected: IboxMarketItem?
    @State private var nameDraft = ""
    @State private var confirm: ConfirmTrade?
    @State private var searchTask: Task<Void, Never>?

    private var siteToken: String { vm.siteUser?.token ?? "" }

    var body: some View {
        Group {
            if siteToken.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("模拟仓绑定网站账号").font(.system(size: 16, weight: .semibold))
                    Text("请先到「我的」登录站点会员，再回来开仓。")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)
                    Spacer()
                }
                .padding(16)
            } else if loading && wallet == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !tip.isEmpty {
                            Text(tip).font(.system(size: 12)).foregroundStyle(Palette.accent)
                        }
                        if wallet?.opened != true {
                            openCard
                        } else {
                            equityCard
                            positionsSection
                            buySection
                            boardSection
                            tradesSection
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .task(id: siteToken) { await refreshAll() }
        .sheet(item: $confirm) { c in
            confirmSheet(c)
        }
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PAPER DESK").font(.system(size: 11, weight: .semibold)).foregroundStyle(gold)
            Text("开启模拟仓").font(.system(size: 18, weight: .bold))
            Text("本金 ¥100,000 · 永不重置 · 按地板价成交 · 卖出手续费 4.5%")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textMuted)
            TextField("昵称", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await openWallet() }
            } label: {
                Text(busy ? "开启中…" : "开启模拟仓")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(creamCard)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(busy)
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(creamCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(creamLine, lineWidth: 1))
    }

    private var equityCard: some View {
        let sm = wallet?.summary
        return VStack(alignment: .leading, spacing: 8) {
            Text(wallet?.displayName.isEmpty == false ? wallet!.displayName : "交易员")
                .font(.system(size: 12))
                .foregroundStyle(gold)
            Text("本金 ¥100,000 · 不可重置")
                .font(.system(size: 11))
                .foregroundStyle(Color.gray)
            HStack(alignment: .bottom, spacing: 8) {
                Text(fmtMoney(sm?.equity)).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                Text(fmtPct(sm?.pnlRate)).font(.system(size: 14, weight: .semibold)).foregroundStyle(pnlColor(sm?.pnlRate))
            }
            HStack(spacing: 8) {
                statChip("现金", fmtMoney(sm?.cash))
                statChip("持仓市值", fmtMoney(sm?.marketValue))
                statChip("总盈亏", fmtMoney(sm?.pnl))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brand)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("持仓").font(.system(size: 13, weight: .semibold))
            let positions = wallet?.positions ?? []
            if positions.isEmpty {
                Text("暂无持仓，从下方买入开始")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(positions) { p in
                    PositionCard(p: p) { qty in
                        let price = p.floorPrice
                        let gross = round2(price * Double(qty))
                        let fee = round2(gross * sellFee)
                        confirm = ConfirmTrade(
                            side: "sell", gid: p.gid, name: p.name, cover: p.cover,
                            qty: qty, price: price, gross: gross, fee: fee, net: round2(gross - fee)
                        )
                    }
                }
            }
        }
    }

    private var buySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("买入 · 按地板价").font(.system(size: 13, weight: .semibold))
            TextField("搜索藏品名称", text: $buyKw)
                .textFieldStyle(.roundedBorder)
                .onChange(of: buyKw) { _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        await loadCatalog()
                    }
                }
            ForEach(catalog.prefix(30)) { row in
                let on = selected?.id == row.id
                Button {
                    selected = row
                } label: {
                    HStack {
                        Text(row.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? creamCard : Palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(row.floorPrice > 0 ? "¥\(fmtPrice(row.floorPrice))" : "询价")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? creamCard : Palette.textPrimary)
                    }
                    .padding(10)
                    .background(on ? Palette.brand : creamCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                TextField("数量", text: $buyQty)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                Button {
                    guard let it = selected else { return }
                    let qty = max(1, Int(buyQty) ?? 1)
                    let price = it.floorPrice
                    let amount = round2(price * Double(qty))
                    confirm = ConfirmTrade(
                        side: "buy", gid: it.id, name: it.name, cover: it.coverPicUrl,
                        qty: qty, price: price, gross: amount, fee: 0, net: amount
                    )
                } label: {
                    Text(selected.map { "买入 \($0.name.prefix(8))" } ?? "选择藏品后买入")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(creamCard)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(selected == nil || busy)
                .buttonStyle(.plain)
            }
        }
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("收益率榜").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                if board.isEmpty {
                    Text("暂无上榜数据")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textMuted)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(board.prefix(20)) { row in
                        HStack {
                            Text("#\(row.rank)  \(row.displayName)")
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Text(fmtPct(row.pnlRate))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(pnlColor(row.pnlRate))
                            Text(fmtMoney(row.equity))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textMuted)
                                .padding(.leading, 8)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(creamCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史战绩 · 流水").font(.system(size: 13, weight: .semibold))
            ForEach(trades.prefix(20)) { t in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(t.side == "buy" ? "买" : "卖") · \(t.name)")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text("\(t.createdAt) · \(t.qty)件 × ¥\(fmtPrice(t.price))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer()
                    Text(fmtMoney(t.amount)).font(.system(size: 12, weight: .semibold))
                }
                .padding(10)
                .background(creamCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func confirmSheet(_ c: ConfirmTrade) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(c.side == "buy" ? "确认买入" : "确认卖出")
                .font(.system(size: 18, weight: .bold))
            Text("是否以 \(fmtMoney(c.price)) \(c.side == "buy" ? "买入" : "卖出") \(c.qty) 件 \(c.name)？")
                .font(.system(size: 14))
            if c.side == "buy" {
                Text("预估花费 \(fmtMoney(c.gross)) · 买入免手续费")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textMuted)
            } else {
                Text("成交额 \(fmtMoney(c.gross))").font(.system(size: 12))
                Text("手续费 4.5% -\(fmtMoney(c.fee))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.957, green: 0.247, blue: 0.369))
                Text("预计到账 \(fmtMoney(c.net))")
                    .font(.system(size: 13, weight: .semibold))
            }
            HStack {
                Button("取消") { confirm = nil }
                    .buttonStyle(.bordered)
                Button(busy ? "提交中…" : "确认") {
                    Task { await submit(c) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
                .disabled(busy)
            }
            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium])
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.gray)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func floorsHintJSON() -> String {
        var map: [String: Double] = [:]
        for it in catalog where it.id > 0 && it.floorPrice > 0 {
            map["\(it.id)"] = it.floorPrice
        }
        for p in wallet?.positions ?? [] where p.gid > 0 && p.floorPrice > 0 {
            if map["\(p.gid)"] == nil { map["\(p.gid)"] = p.floorPrice }
        }
        guard !map.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: map),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    private func refreshAll() async {
        guard !siteToken.isEmpty else {
            loading = false
            tip = "请先在「我的」登录网站账号"
            return
        }
        loading = true
        defer { loading = false }
        let hint = floorsHintJSON()
        do {
            let w = try await vm.api.paperWallet(platformToken: siteToken, floorsHint: hint)
            wallet = w
            nameDraft = w.displayName
            board = try await vm.api.paperLeaderboard(platformToken: siteToken, floorsHint: hint)
            if w.opened {
                trades = try await vm.api.paperTrades(platformToken: siteToken)
            }
            await loadCatalog()
        } catch {
            tip = error.localizedDescription
        }
    }

    private func loadCatalog() async {
        let token = vm.iboxToken
        guard !token.isEmpty else { return }
        do {
            catalog = try await vm.api.fetchIboxMarket(
                token: token,
                name: buyKw.trimmingCharacters(in: .whitespaces),
                expandCollections: 2
            ).items
        } catch {
            // 选品失败不挡主仓
        }
    }

    private func openWallet() async {
        busy = true
        defer { busy = false }
        do {
            try await vm.api.paperOpen(platformToken: siteToken, displayName: nameDraft.trimmingCharacters(in: .whitespaces))
            tip = "模拟仓已开启"
            await refreshAll()
        } catch {
            tip = error.localizedDescription
        }
    }

    private func submit(_ c: ConfirmTrade) async {
        busy = true
        defer { busy = false }
        do {
            if c.side == "buy" {
                _ = try await vm.api.paperBuy(
                    platformToken: siteToken, gid: c.gid, qty: c.qty,
                    name: c.name, cover: c.cover, floorPrice: c.price
                )
                tip = "买入成功"
            } else {
                _ = try await vm.api.paperSell(
                    platformToken: siteToken, gid: c.gid, qty: c.qty,
                    name: c.name, cover: c.cover, floorPrice: c.price
                )
                tip = "卖出成功"
            }
            confirm = nil
            await refreshAll()
        } catch {
            tip = error.localizedDescription
        }
    }
}

private struct ConfirmTrade: Identifiable {
    var id: String { "\(side)-\(gid)-\(qty)-\(price)" }
    var side: String
    var gid: Int64
    var name: String
    var cover: String
    var qty: Int
    var price: Double
    var gross: Double
    var fee: Double
    var net: Double
}

private struct PositionCard: View {
    let p: PaperPosition
    var onSell: (Int) -> Void
    @State private var qtyText: String

    init(p: PaperPosition, onSell: @escaping (Int) -> Void) {
        self.p = p
        self.onSell = onSell
        _qtyText = State(initialValue: "\(p.qty)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(p.qty) 件 · 成本 \(fmtMoney(p.avgCost))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmtMoney(p.floorPrice)).font(.system(size: 13, weight: .semibold))
                    Text(fmtMoney(p.pnl)).font(.system(size: 11)).foregroundStyle(pnlColor(p.pnl))
                }
            }
            HStack(spacing: 8) {
                TextField("数量", text: $qtyText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                Button {
                    let q = min(p.qty, max(1, Int(qtyText) ?? p.qty))
                    onSell(q)
                } label: {
                    Text("按地板价卖出")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(creamCard)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(creamCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(creamLine, lineWidth: 1))
    }
}

private func fmtMoney(_ n: Double?) -> String {
    guard let v = n else { return "—" }
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.locale = Locale(identifier: "zh_CN")
    return "¥" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
}

private func fmtPct(_ r: Double?) -> String {
    guard let r else { return "—" }
    let v = r * 100
    let sign = v >= 0 ? "+" : ""
    return sign + String(format: "%.2f%%", v)
}

private func fmtPrice(_ p: Double) -> String {
    p.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(p))" : String(format: "%.2f", p)
}

private func pnlColor(_ n: Double?) -> Color {
    let v = n ?? 0
    return v >= 0 ? Color(red: 0.957, green: 0.247, blue: 0.369) : Color(red: 0.02, green: 0.588, blue: 0.412)
}

private func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }
