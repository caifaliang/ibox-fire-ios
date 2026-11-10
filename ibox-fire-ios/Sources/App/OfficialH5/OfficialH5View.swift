import SwiftUI
import WebKit

/// 官方 H5 全屏：注入 + 禁 SW + API 桥 + 顶栏芯片浮层
struct OfficialH5View: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let token: String
    var refreshToken: String = ""
    var deviceId: String = ""
    var uid: Int64 = 0

    @State private var html: String = ""
    @State private var status = "加载中…"
    @State private var progress: Double = 0
    @State private var pageTitle = ""
    @State private var pageURL = ""
    @State private var activeTool: String?
    @State private var loadError: String?

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
                    dismiss()
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
                Text(status)
                    .font(Typo.caption2)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
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

            if progress > 0, progress < 1 {
                ProgressView(value: progress)
                    .tint(Palette.brand)
            }

            ZStack {
                if let loadError {
                    VStack(spacing: 12) {
                        Text(loadError)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.danger)
                            .multilineTextAlignment(.center)
                        Button("重试") { Task { await boot() } }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.horizontal, 40)
                    }
                    .padding(24)
                } else if html.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(status)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textMuted)
                    }
                } else {
                    OfficialH5WebView(
                        html: html,
                        baseURL: URL(string: SharedPrefsPack.h5Boot)!,
                        onTitle: { pageTitle = $0 },
                        onURL: { pageURL = $0 },
                        onProgress: { progress = $0 }
                    )
                }

                if let tool = activeTool {
                    OfficialH5ToolOverlay(tool: tool) {
                        activeTool = nil
                    }
                    .environmentObject(vm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.bg)
        .task { await boot() }
    }

    private func openTool(_ key: String) {
        if activeTool == key {
            activeTool = nil
            return
        }
        // 尽量带入 GID（从 URL 解析）
        if let gid = parseGroupId(pageURL), gid > 0 {
            switch key {
            case "buy": vm.buyGid = gid
            case "sell": vm.sellGid = gid
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
        // .../digital-collection-groups/123 或 hash 内 groupId=
        if let r = url.range(of: #"digital-collection-groups/(\d+)"#, options: .regularExpression) {
            let s = String(url[r]).components(separatedBy: "/").last ?? ""
            return Int64(s)
        }
        if let r = url.range(of: #"groupId[=:](\d+)"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = url[r].filter(\.isNumber)
            return Int64(digits)
        }
        return nil
    }

    @MainActor
    private func boot() async {
        loadError = nil
        status = "拉取官方页…"
        let t = JwtUtil.normalize(token)
        guard !t.isEmpty else {
            loadError = "缺少 iBox Token"
            return
        }
        let expSec = JwtUtil.exp(t) ?? 0
        let expMs = expSec > 0 ? expSec * 1000 : 0
        let pack = SharedPrefsPack.build(
            accessToken: t,
            refreshToken: refreshToken,
            deviceId: deviceId.isEmpty ? IboxClient.makeDeviceId(t) : deviceId,
            uid: uid > 0 ? uid : (JwtUtil.uid(t) ?? 0),
            expMs: expMs
        )
        warmCookies(pack)
        do {
            let raw = try await fetchBootHTML()
            let inject = H5ApiBridge.bootScript() + pack.toBootHeadScript()
            var patched: String
            if let range = raw.range(of: "</head>", options: .caseInsensitive) {
                patched = raw.replacingCharacters(in: range, with: inject + "</head>")
            } else {
                patched = inject + raw
            }
            patched = patched.replacingOccurrences(
                of: #"serviceWorkerSettings\s*:\s*\{[^}]*\}"#,
                with: "serviceWorkerSettings: undefined",
                options: .regularExpression
            )
            html = patched
            status = "已注入 · 进入中"
        } catch {
            loadError = error.localizedDescription
            status = "失败"
        }
    }

    private func warmCookies(_ pack: SharedPrefsPack) {
        let store = HTTPCookieStorage.shared
        let tok = pack.cookieToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pack.cookieToken
        let hosts = [
            "https://h5.ibox.art/",
            "https://sail-api.ibox.art/",
            "https://personal-center.ibox.art/",
        ]
        for host in hosts {
            guard let url = URL(string: host) else { continue }
            if let c = HTTPCookie(properties: [
                .domain: ".ibox.art",
                .path: "/",
                .name: "token",
                .value: tok,
                .secure: "TRUE",
            ]) {
                store.setCookie(c)
                WKCookieSync.setCookie(c, for: url)
            }
            if !pack.cookieExpiredAt.isEmpty,
               let c2 = HTTPCookie(properties: [
                   .domain: ".ibox.art",
                   .path: "/",
                   .name: "expiredAt",
                   .value: pack.cookieExpiredAt,
                   .secure: "TRUE",
               ]) {
                store.setCookie(c2)
                WKCookieSync.setCookie(c2, for: url)
            }
        }
    }

    private func fetchBootHTML() async throws -> String {
        var req = URLRequest(url: URL(string: SharedPrefsPack.h5Boot)!)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw NSError(domain: "h5", code: -2, userInfo: [NSLocalizedDescriptionKey: "拉取 H5 失败"])
        }
        return String(data: data, encoding: .utf8) ?? ""
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
                    case "buy": ModePane() // 依赖 techMode
                    case "sell": ModePane()
                    case "query_consignment": ModePane()
                    case "records":
                        Text("成交记录请在查挂单/捡漏中查看藏品后使用网站侧记录；完整 TradeRecords 对齐后续补齐。")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textMuted)
                            .padding()
                    default: ModePane()
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

/// WKWebView cookie 同步辅助
enum WKCookieSync {
    static func setCookie(_ cookie: HTTPCookie, for url: URL) {
        WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
    }
}
