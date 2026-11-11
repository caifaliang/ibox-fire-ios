import SwiftUI

/// 官方 H5 全屏壳：保活 WebView +「科技」回主壳（不销毁缓存）
struct OfficialH5View: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var session = OfficialH5Session.shared

    var onBackToTech: () -> Void

    let token: String
    var refreshToken: String = ""
    var deviceId: String = ""
    var uid: Int64 = 0

    @State private var activeTool: String?

    private let tools: [(String, String)] = [
        ("query_consignment", "查挂单"),
        ("buy", "捡漏"),
        ("sell", "卖求购"),
        ("records", "成交记录"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    if activeTool != nil { activeTool = nil } else { onBackToTech() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Text("官方 H5")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    Haptics.tap()
                    onBackToTech()
                } label: {
                    Text("科技")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.brandSubtle, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.surface)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tools, id: \.0) { key, label in
                        let sel = activeTool == key
                        Button {
                            Haptics.tap()
                            openTool(key)
                        } label: {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(sel ? Palette.onBrand : Palette.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(sel ? Palette.brand : Palette.surfaceMuted)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Palette.bg)

            Text(session.status)
                .font(Typo.caption2)
                .foregroundStyle(Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            if session.progress > 0, session.progress < 0.99 {
                ProgressView(value: session.progress)
                    .tint(Palette.brand)
            }

            ZStack {
                OfficialH5WebView(session: session)
                    .background(Color.black)

                if session.webView == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(session.status)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textMuted)
                        if let err = session.lastError {
                            Text(err).font(Typo.caption2).foregroundStyle(Palette.danger)
                            Button("重试") { start() }
                                .buttonStyle(PrimaryButtonStyle())
                                .padding(.horizontal, 40)
                        }
                    }
                }

                if let tool = activeTool {
                    OfficialH5ToolOverlay(tool: tool) {
                        activeTool = nil
                    }
                    .environmentObject(vm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.bg)
        .onAppear { start() }
    }

    private func start() {
        session.ensureStarted(
            token: token,
            refreshToken: refreshToken,
            deviceId: deviceId,
            uid: uid
        )
    }

    private func openTool(_ key: String) {
        if activeTool == key {
            activeTool = nil
            return
        }
        if let gid = parseGroupId(session.pageURL), gid > 0 {
            switch key {
            case "buy":
                vm.buyGid = gid
                if vm.buyCname.isEmpty { vm.buyCname = "GID \(gid)" }
            case "sell":
                vm.sellGid = gid
                if vm.sellCname.isEmpty { vm.sellCname = "GID \(gid)" }
            case "query_consignment":
                vm.queryGid = gid
                vm.queryKind = "consignment"
            default: break
            }
        }
        if let mode = TechMode(rawValue: key) {
            vm.techMode = mode
            vm.onTechModeChanged(mode)
        }
        activeTool = key
    }

    private func parseGroupId(_ url: String) -> Int64? {
        if let r = url.range(of: #"digital-collection-groups/(\d+)"#, options: .regularExpression) {
            let s = String(url[r]).components(separatedBy: "/").last ?? ""
            return Int64(s)
        }
        if let r = url.range(of: #"/market/collectible/(\d+)"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = url[r].filter(\.isNumber)
            return Int64(digits)
        }
        return nil
    }
}

struct OfficialH5ToolOverlay: View {
    @EnvironmentObject var vm: AppViewModel
    let tool: String
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Button("关闭", action: onClose)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .padding(14)
                Divider()
                Group {
                    switch tool {
                    case "records":
                        Text("成交记录浮层后续对齐 APK TradeRecords；可先用查挂单/捡漏。")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textMuted)
                            .padding()
                    default:
                        ModePane()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 16, y: -2)
        }
        .background(Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: onClose))
    }

    private var title: String {
        switch tool {
        case "buy": return "捡漏"
        case "sell": return "卖求购"
        case "records": return "成交记录"
        default: return "查挂单"
        }
    }
}
