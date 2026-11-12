import SwiftUI

/// 对齐 APK OfficialH5Tools.TradeRecordsPane
struct TradeRecordsPane: View {
    @EnvironmentObject var vm: AppViewModel
    /// nil = 占满剩余高度（爬仓详情）；有值则固定上限（科技浮层）
    var listMaxHeight: CGFloat? = 360

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("实时成交")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        vm.loadTradeRecords(reset: true)
                    } label: {
                        Text(vm.tradeLoading ? "刷新中…" : "刷新")
                            .font(.system(size: 12).weight(.medium))
                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.12, green: 0.16, blue: 0.23), in: Capsule())
                    }
                    .disabled(vm.tradeLoading)
                    .buttonStyle(.plain)
                }
                HStack {
                    tradeStat("24h成交", vm.tradeQty24h.isEmpty ? "—" : "\(vm.tradeQty24h)笔")
                    tradeStat("24h成交额", vm.tradeAmount24h.isEmpty ? "—" : vm.tradeAmount24h)
                    tradeStat("最新价", vm.tradeLastPrice.isEmpty ? "—" : vm.tradeLastPrice, accent: true)
                }
                if !vm.tradeUpdatedAt.isEmpty {
                    Text("更新于 \(vm.tradeUpdatedAt)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.39, green: 0.45, blue: 0.55))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(14)
            .background(Color(red: 0.06, green: 0.09, blue: 0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 0) {
                HStack {
                    Text("时间").frame(width: 72, alignment: .leading)
                    Text("编号").frame(maxWidth: .infinity)
                    Text("价格").frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 0.97, green: 0.98, blue: 0.99))

                if vm.tradeLoading && vm.tradeRecords.isEmpty {
                    Text("正在加载成交…")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else if !vm.tradeErr.isEmpty && vm.tradeRecords.isEmpty {
                    VStack(spacing: 10) {
                        Text(vm.tradeErr).font(.caption).foregroundStyle(Color(red: 0.96, green: 0.25, blue: 0.37))
                        Button("重试") { vm.loadTradeRecords(reset: true) }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.96, green: 0.62, blue: 0.04), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else if vm.tradeRecords.isEmpty {
                    Text(vm.tradeGid <= 0 ? "请先打开某个藏品" : "暂无成交记录")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.tradeRecords) { row in
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.time.isEmpty ? "—" : row.time)
                                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                                            .foregroundStyle(Color(red: 0.06, green: 0.09, blue: 0.16))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                        if !row.date.isEmpty {
                                            Text(row.date)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(width: 78, alignment: .leading)
                                    Text(row.tokenId.isEmpty ? "\(row.qty) 笔" : "#\(row.tokenId)")
                                        .font(.subheadline)
                                        .foregroundStyle(Color(red: 0.20, green: 0.25, blue: 0.33))
                                        .frame(maxWidth: .infinity)
                                    Text(row.price.isEmpty ? "—" : row.price)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.02))
                                        .frame(width: 72, alignment: .trailing)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                Divider().opacity(0.35)
                            }
                            if vm.tradeHasMore {
                                Button {
                                    vm.loadTradeRecords(reset: false)
                                } label: {
                                    Text(vm.tradeLoadingMore ? "加载更早成交…" : "加载更早成交")
                                        .font(.caption)
                                        .foregroundStyle(Color(red: 0.71, green: 0.33, blue: 0.04))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color(red: 1.0, green: 0.98, blue: 0.92))
                                }
                                .disabled(vm.tradeLoadingMore)
                                .buttonStyle(.plain)
                            } else if vm.tradeRecords.count >= 20 {
                                Text("没有更多了")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.textMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                    .frame(maxHeight: listMaxHeight)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(red: 0.95, green: 0.96, blue: 0.97), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            if vm.tradeGid > 0 && vm.tradeRecords.isEmpty && !vm.tradeLoading && vm.tradeErr.isEmpty {
                vm.loadTradeRecords(reset: true)
            }
        }
    }

    private func tradeStat(_ title: String, _ value: String, accent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent ? Color(red: 0.99, green: 0.80, blue: 0.28) : .white)
        }
        .frame(maxWidth: .infinity)
    }
}
