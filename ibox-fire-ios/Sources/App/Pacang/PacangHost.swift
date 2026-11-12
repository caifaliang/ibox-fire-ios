import SwiftUI

/// 爬仓整页：市场 | 持仓市值；市场下 活动市场 | 模拟仓；点藏品进详情。
struct PacangHost: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var primary = "market" // market | holdings
    @State private var marketSub = "activity" // activity | paper
    @State private var detail: IboxMarketItem?

    var body: some View {
        VStack(spacing: 10) {
            if let detail {
                PacangDetailPane(item: detail, onBack: { self.detail = nil })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                segment(
                    options: [("market", "市场"), ("holdings", "持仓市值")],
                    selected: $primary
                )
                if primary == "market" {
                    segment(
                        options: [("activity", "活动市场"), ("paper", "模拟仓")],
                        selected: $marketSub,
                        compact: true
                    )
                }
                Group {
                    if primary == "holdings" {
                        // 勿外包 ScrollView：HoldingsPane 自带列表，嵌套会卡顿/手势抢滚动
                        HoldingsPane()
                            .padding(.horizontal, 4)
                    } else if marketSub == "paper" {
                        PaperTradingPane()
                    } else {
                        ActivityMarketPane { row in
                            detail = row
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(Color(red: 0.969, green: 0.957, blue: 0.933)) // #F7F4EE
    }

    private func segment(options: [(String, String)], selected: Binding<String>, compact: Bool = false) -> some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { key, label in
                let on = selected.wrappedValue == key
                Button {
                    selected.wrappedValue = key
                } label: {
                    Text(label)
                        .font(.system(size: compact ? 13 : 14, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Color(red: 0.969, green: 0.957, blue: 0.933) : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 8 : 10)
                        .background(on ? Palette.brand : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(red: 1, green: 0.988, blue: 0.969)) // #FFFCF7
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
