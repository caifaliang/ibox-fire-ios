import SwiftUI

/// 真源：`VipRedeemScreen` — 状态 / 购买 / DLDOU- 兑换。
struct VipRedeemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = VipStore.shared
    @ObservedObject private var session = SessionStore.shared

    @State private var code = ""
    @State private var statusText = "查询中…"
    @State private var msg = "购买后到链动小铺订单查看 DLDOU- 卡密，在此兑换。"
    @State private var busy = false
    @State private var copiedTip = ""

    private var deviceId: String { VipConfig.deviceId }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(statusText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DlColors.ink)

                    Text("购买套餐（链动小铺）")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DlColors.inkMuted)

                    HStack(spacing: 8) {
                        shopButton("日卡 ¥0.5", VipConfig.shopDay)
                        shopButton("周卡 ¥3", VipConfig.shopWeek)
                    }
                    HStack(spacing: 8) {
                        shopButton("月卡 ¥8.8", VipConfig.shopMonth)
                        shopButton("年卡 ¥68", VipConfig.shopYear)
                    }

                    Text("激活卡密（DLDOU-）")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DlColors.inkMuted)
                        .padding(.top, 8)

                    TextField("DLDOU-XXXXXXXXXXXX", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Button {
                        Task { await redeem() }
                    } label: {
                        Text(busy ? "兑换中…" : "兑换")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(busy ? DlColors.inkMuted : DlColors.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(busy)
                    .buttonStyle(.plain)

                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.inkSecondary)

                    Text("本机设备号（点按复制）")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.top, 12)
                    Text(deviceId.isEmpty ? "（未获取）" : deviceId)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DlColors.inkMuted)
                        .onTapGesture { copyDevice() }

                    if !copiedTip.isEmpty {
                        Text(copiedTip)
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.accentBlue)
                    }
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("大乐斗会员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                applyLocalStatus()
                Task { await refreshStatus() }
            }
        }
    }

    private func shopButton(_ title: String, _ url: String) -> some View {
        Button {
            if let u = URL(string: url) {
                UIApplication.shared.open(u)
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DlColors.accentBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DlColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DlColors.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func applyLocalStatus() {
        let s = VipService.localStatus()
        statusText = formatStatus(s, suffix: "（本地）")
    }

    private func refreshStatus() async {
        let s = await VipService.queryStatus(uin: session.qq)
        statusText = formatStatus(s)
    }

    private func formatStatus(_ s: VipStatus, suffix: String = "") -> String {
        if s.active, let ms = s.expireAtMs, ms > 0 {
            let prefix = s.trial ? "免费体验至" : "VIP 有效至"
            return "\(prefix) \(formatExpire(ms))\(suffix)"
        }
        return "未开通 VIP\(suffix)"
    }

    private func formatExpire(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func redeem() async {
        busy = true
        defer { busy = false }
        let r = await VipService.redeem(cardCode: code)
        msg = r.message
        if r.ok {
            code = ""
            await refreshStatus()
        }
    }

    private func copyDevice() {
        guard !deviceId.isEmpty else {
            copiedTip = "设备号未就绪"
            return
        }
        UIPasteboard.general.string = deviceId
        copiedTip = "已复制设备号"
    }
}
