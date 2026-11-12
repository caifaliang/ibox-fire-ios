import SwiftUI

/// 对齐网站 Detail.vue 查挂单价格分布：进度 + 四格统计 + 占比条（Lazy 列表，避免主线程卡死）
struct LadderResultView: View {
    var kindLabel: String
    var running: Bool
    var scanned: Int
    var apiTotal: Int
    var pages: Int
    var tiers: [QueryTier]
    var active: Int
    var locked: Int
    var progressMsg: String

    private var progressDenom: Int {
        if apiTotal > 0 { return apiTotal }
        return max(scanned, 1)
    }

    private var pct: Int {
        let d = progressDenom
        return min(100, Int((Double(scanned) / Double(d) * 100).rounded()))
    }

    private var floorPrice: Double? { tiers.first?.price }
    private var ceilPrice: Double? { tiers.last?.price }
    private var avgPrice: Double? {
        let sum = tiers.reduce(0.0) { $0 + $1.price * Double($1.count) }
        let n = tiers.reduce(0) { $0 + $1.count }
        guard n > 0 else { return nil }
        return sum / Double(n)
    }

    private var sampleLabel: String {
        apiTotal > scanned ? "已采样" : "\(kindLabel)总数"
    }

    private var visibleTiers: [QueryTier] { Array(tiers.prefix(80)) }

    private var totalCount: Int {
        max(1, tiers.reduce(0) { $0 + $1.count })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(kindLabel)价格分布")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer()
                if running {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("查询中").font(.system(size: 11).weight(.medium))
                    }
                    .foregroundStyle(Color(red: 0.71, green: 0.40, blue: 0.05))
                }
            }

            if running {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(progressMsg.isEmpty ? "已拉取 \(scanned)/\(progressDenom) 单 · 第 \(max(pages, 1)) 页" : progressMsg)
                            .font(.system(size: 11).weight(.medium))
                            .foregroundStyle(Color(red: 0.57, green: 0.25, blue: 0.05))
                        Spacer()
                        Text("\(pct)%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.02))
                    }
                    ProgressView(value: Double(max(pct, 1)), total: 100)
                        .tint(Color(red: 0.96, green: 0.55, blue: 0.0))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.98, blue: 0.93))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(red: 0.99, green: 0.90, blue: 0.72), lineWidth: 1)
                        )
                )
            }

            if scanned > 0 || !tiers.isEmpty {
                HStack(spacing: 0) {
                    statCell(sampleLabel, "\(scanned)")
                    statCell("价格档", "\(tiers.count)")
                    statCell("地板价", floorPrice.map { fmtPrice($0) } ?? "—", accent: .amber)
                    statCell("最高挂", ceilPrice.map { fmtPrice($0) } ?? "—", accent: .rose)
                }
                .padding(.vertical, 12)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 0) {
                    HStack {
                        Text("价格").frame(width: 56, alignment: .leading)
                        Text("挂单量占比").frame(maxWidth: .infinity)
                        Text("单数").frame(width: 40, alignment: .trailing)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider().opacity(0.4)

                    // Lazy：只画可视行；占比条用 ProgressView，避免每行 GeometryReader
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleTiers) { t in
                                let share = Double(t.count) / Double(totalCount)
                                HStack(spacing: 8) {
                                    Text("¥\(fmtPrice(t.price))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                        .frame(width: 56, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        ProgressView(value: min(max(share, 0), 1))
                                            .tint(Color(red: 0.96, green: 0.55, blue: 0.0))
                                        Text(String(format: "%.0f%%", share * 100))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.textMuted)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(t.count)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Palette.textPrimary)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                Divider().opacity(0.25).padding(.leading, 12)
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(red: 0.95, green: 0.96, blue: 0.97), lineWidth: 1)
                        )
                )

                HStack(spacing: 0) {
                    Spacer()
                    Text(footerText)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                    Spacer()
                }
            }
        }
    }

    private var subtitle: String {
        var s = "各价位\(kindLabel)数量 · 实时游标分页"
        if apiTotal > 0 { s += "（市场约 \(apiTotal) 单）" }
        return s
    }

    private var footerText: String {
        var parts: [String] = []
        if kindLabel == "挂单" {
            parts.append("可售 \(active)")
            parts.append("锁定 \(locked)")
        }
        if let avg = avgPrice {
            parts.append("均价 ¥\(fmtPrice(avg))")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    private enum Accent { case amber, rose, none }

    private func statCell(_ title: String, _ value: String, accent: Accent = .none) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle({
                    switch accent {
                    case .amber: return Color(red: 0.99, green: 0.80, blue: 0.28)
                    case .rose: return Color(red: 0.98, green: 0.44, blue: 0.52)
                    case .none: return Color.white
                    }
                }())
        }
        .frame(maxWidth: .infinity)
    }

    private func fmtPrice(_ p: Double) -> String {
        if abs(p - p.rounded()) < 0.005 { return String(Int(p.rounded())) }
        return String(format: "%.2f", (p * 100).rounded() / 100)
    }
}
