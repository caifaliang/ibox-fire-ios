import SwiftUI

/// 对齐网页 Detail / Android PacangDetailPane：成交 | 查挂单 | 查求购 | 寄售
struct PacangDetailPane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    let item: IboxMarketItem
    var onBack: () -> Void

    @State private var tab = "records"
    @State private var consign: [IboxConsignRow] = []
    @State private var consignLoading = false
    @State private var consignErr = ""
    @State private var consignTick = 0

    private let cream = Color(red: 1, green: 0.988, blue: 0.969)
    private let creamLine = Color(red: 0.906, green: 0.878, blue: 0.831)
    private let gold = Color(red: 0.769, green: 0.647, blue: 0.455)
    private let subBg = Color(red: 0.945, green: 0.929, blue: 0.894)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onBack) {
                    Text("← 返回")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("藏品详情")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gold)
            }

            HStack(spacing: 12) {
                AsyncImage(url: URL(string: iboxThumb(item.coverPicUrl, size: 128))) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    creamLine
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text("GID \(item.id)").font(.system(size: 11)).foregroundStyle(Palette.textMuted)
                    Text(item.floorPrice > 0 ? "地板 ¥\(fmtPrice(item.floorPrice))" : "地板 —")
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(cream)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    detailTab("成交记录", key: "records")
                    detailTab("查挂单", key: "ladder")
                    detailTab("查求购", key: "purchase")
                    detailTab("寄售", key: "consignment")
                }
                .padding(4)
            }
            .background(subBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Group {
                switch tab {
                case "records":
                    TradeRecordsPane(listMaxHeight: nil)
                case "ladder", "purchase":
                    ladderBody(isPurchase: tab == "purchase")
                default:
                    consignBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            vm.prepareTradeRecords(groupId: item.id, groupName: item.name)
        }
        .task(id: "\(item.id)-\(tab)-\(consignTick)") {
            await onTabChange()
        }
    }

    private func detailTab(_ label: String, key: String) -> some View {
        Button {
            tab = key
        } label: {
            Text(label)
                .font(.system(size: 13, weight: tab == key ? .semibold : .medium))
                .foregroundStyle(tab == key ? Palette.textPrimary : Palette.textMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(tab == key ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func ladderBody(isPurchase: Bool) -> some View {
        let title = isPurchase ? "求购" : "挂单"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title)整理" + (vm.queryProgressMsg.isEmpty ? "" : " · \(vm.queryProgressMsg)"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Button(runner.isRunning(.query) ? "扫描中…" : "重新扫描") {
                    vm.startQueryInPlace(
                        kind: isPurchase ? "purchase" : "consignment",
                        groupId: item.id,
                        groupName: item.name,
                        depth: 500
                    )
                }
                .font(.system(size: 12))
                .disabled(runner.isRunning(.query))
            }
            LadderResultView(
                kindLabel: title,
                running: runner.isRunning(.query),
                scanned: vm.queryScanned,
                apiTotal: vm.queryApiTotal,
                pages: vm.queryPages,
                tiers: vm.queryTiers,
                active: vm.queryActive,
                locked: vm.queryLocked,
                progressMsg: vm.queryProgressMsg
            )
        }
    }

    @ViewBuilder
    private var consignBody: some View {
        if consignLoading && consign.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !consignErr.isEmpty && consign.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(consignErr).foregroundStyle(.red).font(.system(size: 13))
                Button("重试") { consignTick += 1 }
            }
        } else if consign.isEmpty {
            Text("暂无寄售").foregroundStyle(Palette.textMuted).font(.system(size: 13))
        } else {
            List(consign) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("¥\(fmtPrice(row.price))").font(.system(size: 14, weight: .semibold))
                        if !row.tokenId.isEmpty {
                            Text("#\(row.tokenId)").font(.system(size: 11)).foregroundStyle(Palette.textMuted)
                        }
                    }
                    Spacer()
                    if !row.sellerName.isEmpty {
                        Text(row.sellerName).font(.system(size: 11)).foregroundStyle(Palette.textMuted)
                    }
                }
                .listRowBackground(cream)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func onTabChange() async {
        switch tab {
        case "consignment":
            guard !vm.iboxToken.isEmpty else { return }
            consignLoading = true
            consignErr = ""
            defer { consignLoading = false }
            do {
                consign = try await vm.api.fetchIboxConsign(token: vm.iboxToken, groupId: item.id)
            } catch {
                consignErr = error.localizedDescription
            }
        case "ladder":
            if !runner.isRunning(.query),
               vm.queryGid != item.id || vm.queryKind != "consignment" || vm.queryTiers.isEmpty {
                vm.startQueryInPlace(kind: "consignment", groupId: item.id, groupName: item.name, depth: 500)
            }
        case "purchase":
            if !runner.isRunning(.query),
               vm.queryGid != item.id || vm.queryKind != "purchase" || vm.queryTiers.isEmpty {
                vm.startQueryInPlace(kind: "purchase", groupId: item.id, groupName: item.name, depth: 500)
            }
        default:
            vm.prepareTradeRecords(groupId: item.id, groupName: item.name)
        }
    }
}

private func fmtPrice(_ p: Double) -> String {
    p.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(p))" : String(format: "%.2f", p)
}
