import SwiftUI
import WebKit
import UIKit

struct ReplayWebView: UIViewRepresentable {
    let act: String
    let replayId: String
    @ObservedObject var log: ReplayDebugLog
    @Binding var statusLine: String

    func makeCoordinator() -> Coordinator {
        Coordinator(act: act, replayId: replayId, log: log, statusLine: $statusLine)
    }

    func makeUIView(context: Context) -> WKWebView {
        let preferMm = ActionPackPrefetch.preferMm(from: act)
        ActionPackPrefetch.sessionPreferMm = preferMm
        log.append("boot replayId=\(replayId) actLen=\(act.count) preferMm=\(preferMm)")
        let packRel = preferMm ? ActionPackPrefetch.mmRel : ActionPackPrefetch.ggRel
        let packFile = ActionPackPrefetch.localURL(for: packRel)
        if FileManager.default.fileExists(atPath: packFile.path) {
            let stripped = SwfPrefixStrip.stripFileIfNeeded(packFile)
            log.append("packFile strip=\(stripped) needs=\(SwfPrefixStrip.needsStrip(fileURL: packFile))")
        }
        log.append("diskReady=\(ActionPackPrefetch.isDiskReady(preferMm: preferMm))")

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // 保留 scheme 作兜底；主路径改走本机 HTTP（Ruffle Loader 只认 http/https）
        let handler = RuffleSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: RuffleSchemeHandler.scheme)
        context.coordinator.handler = handler
        handler.onActionPackEvent = { [weak coordinator = context.coordinator] kind in
            coordinator?.onPackEvent(kind)
        }
        handler.onResourceLog = { [weak coordinator = context.coordinator] msg in
            coordinator?.logLine(msg)
        }

        let uc = config.userContentController
        uc.add(context.coordinator, name: "ruffleStatus")
        uc.add(context.coordinator, name: "ruffleEvent")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        wv.isOpaque = true
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            wv.isInspectable = true
        }

        guard handler.rootExists else {
            let msg = "资源缺失: \(handler.rootPath)"
            statusLine = msg
            log.append(msg)
            wv.loadHTMLString(
                "<html><body style='background:#111;color:#f66;font:16px sans-serif;padding:24px'>"
                    + "ruffle_fight 未打进包<br/>\(handler.rootPath)</body></html>",
                baseURL: nil
            )
            return wv
        }
        log.append("bundleOK root=\(handler.rootPath)")

        let server = RuffleLocalServer.shared
        server.onLog = { [weak coordinator = context.coordinator] msg in
            coordinator?.logLine(msg)
        }
        let forceVanilla = RuffleMemPolicy.shouldUseVanilla
        context.coordinator.useVanilla = forceVanilla
        let pageURL: URL
        do {
            let base = try server.start(root: URL(fileURLWithPath: handler.rootPath))
            pageURL = Self.fightPageURL(
                base: base.absoluteString,
                preferMm: preferMm,
                vanilla: forceVanilla
            )
            log.append("HTTP \(base.absoluteString) wasm=\(forceVanilla ? "vanilla(safe)" : "auto(simd)")")
        } catch {
            log.append("HTTP start FAIL \(error.localizedDescription) → scheme fallback")
            pageURL = Self.fightPageURL(
                base: "\(RuffleSchemeHandler.scheme)://local/",
                preferMm: preferMm,
                vanilla: forceVanilla
            )
        }
        statusLine = forceVanilla ? "兼容模式加载…" : "加载播放器…"
        log.append("load \(pageURL.absoluteString)")
        context.coordinator.pageURL = pageURL
        wv.load(URLRequest(url: pageURL))
        return wv
    }

    private static func fightPageURL(base: String, preferMm: Bool, vanilla: Bool) -> URL {
        var s = base
        if !s.hasSuffix("/") { s += "/" }
        var q = "renderer=canvas&preferMm=\(preferMm ? 1 : 0)&replay=1"
        if vanilla { q += "&wasm=vanilla" }
        return URL(string: "\(s)ruffle_fight/index.html?\(q)")!
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.webView = uiView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ruffleStatus")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ruffleEvent")
        coordinator.handler?.onActionPackEvent = nil
        coordinator.handler?.onResourceLog = nil
        coordinator.log.flushToDisk()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let act: String
        let replayId: String
        let log: ReplayDebugLog
        var handler: RuffleSchemeHandler?
        weak var webView: WKWebView?
        var pageURL: URL?
        var useVanilla = false
        private var injectGeneration = 0
        private var recoveringFromOOM = false
        private var statusLine: Binding<String>

        init(act: String, replayId: String, log: ReplayDebugLog, statusLine: Binding<String>) {
            self.act = act
            self.replayId = replayId
            self.log = log
            self.statusLine = statusLine
        }

        func logLine(_ msg: String) {
            log.append(msg)
            // 关键重要行顶栏
            if msg.contains("action_gg") || msg.contains("action_mm")
                || msg.contains("FAIL") || msg.contains("ERR")
                || msg.hasPrefix("vel ") || msg.contains("inject") {
                statusLine.wrappedValue = msg
            }
        }

        func onPackEvent(_ kind: String) {
            if kind == "delivered" {
                let msg = "PACK delivered (gg/mm 已交给 Flash，开始解析)"
                statusLine.wrappedValue = msg
                log.append(msg)
            } else if kind == "parsed" {
                let msg = "PACK parsed (收到 gg2/mm2 请求)"
                statusLine.wrappedValue = msg
                log.append(msg)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "ruffleStatus", let s = message.body as? String {
                statusLine.wrappedValue = s
                log.append("status \(s)")
                return
            }
            if message.name == "ruffleEvent", let dict = message.body as? [String: Any] {
                let type = dict["type"] as? String ?? ""
                let payload = dict["payload"]
                log.append("event \(type) \(stringify(payload))")
                switch type {
                case "boot_fail", "inject_fail":
                    statusLine.wrappedValue = "\(type): \(stringify(payload))"
                case "injected":
                    statusLine.wrappedValue = "已注入，等待动作包/开战…"
                    // 成功注入后，若本轮已是 vanilla 且后续能开战，可清 sticky
                case "swf_ready":
                    statusLine.wrappedValue = "SWF 就绪…"
                case "boot_fallback":
                    RuffleMemPolicy.markWasmCrashed()
                    useVanilla = true
                    statusLine.wrappedValue = "改用兼容 wasm…"
                case "velocimetry":
                    if let p = payload as? [String: Any] {
                        let tag = p["tag"] as? String ?? ""
                        let val = p["val"] as? String ?? ""
                        statusLine.wrappedValue = "vel \(tag) \(val)"
                        if tag == "sal_base_ok" || tag == "ready_go" || tag == "ra_startRound" {
                            RuffleMemPolicy.markFightHealthy()
                        }
                    }
                case "ready_kick":
                    statusLine.wrappedValue = "ready_skip → kick"
                case "net_ok", "net_fail", "net_err":
                    if let p = payload as? [String: Any] {
                        let u = p["url"] as? String ?? ""
                        let short = (u as NSString).lastPathComponent
                        if short.contains("action_") || type != "net_ok" {
                            statusLine.wrappedValue = "\(type) \(short)"
                        }
                    }
                default:
                    break
                }
            }
        }

        private func stringify(_ any: Any?) -> String {
            guard let any else { return "" }
            if let s = any as? String { return s }
            if let d = any as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: d),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return String(describing: any)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let msg = "页面失败: \(error.localizedDescription)"
            statusLine.wrappedValue = msg
            log.append(msg)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            let msg = "加载失败: \(error.localizedDescription)"
            statusLine.wrappedValue = msg
            log.append(msg)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            recoveringFromOOM = false
            statusLine.wrappedValue = "注入战报…"
            log.append("didFinish → queue inject gen=\(injectGeneration + 1)")
            injectGeneration += 1
            inject(into: webView, attempt: 0, generation: injectGeneration)
        }

        /// WebContent 被 jetsam/OOM 杀掉：对齐 APK render_gone → sticky vanilla 降配重载
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            log.append("OOM/terminate WebContent → vanilla reload")
            statusLine.wrappedValue = "内存不足，降配重试…"
            RuffleMemPolicy.markWasmCrashed()
            useVanilla = true
            guard !recoveringFromOOM else { return }
            recoveringFromOOM = true
            let preferMm = ActionPackPrefetch.preferMm(from: act)
            let base: String
            if let pageURL, let host = pageURL.host, host == "127.0.0.1" || host == "localhost",
               let port = pageURL.port {
                base = "http://127.0.0.1:\(port)/"
            } else if let serverBase = RuffleLocalServer.shared.baseURL?.absoluteString {
                base = serverBase
            } else {
                base = "\(RuffleSchemeHandler.scheme)://local/"
            }
            let url = ReplayWebView.fightPageURL(base: base, preferMm: preferMm, vanilla: true)
            pageURL = url
            log.append("reload \(url.absoluteString)")
            webView.load(URLRequest(url: url))
        }

        private func inject(into webView: WKWebView, attempt: Int, generation: Int) {
            guard generation == injectGeneration else { return }
            let b64 = Data(act.utf8).base64EncodedString()
            let idEsc = replayId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let js = "window.__injectFightActB64 && window.__injectFightActB64(\"\(b64)\",\"\(idEsc)\")"
            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self else { return }
                guard generation == self.injectGeneration else { return }
                if let error {
                    self.logLine("注入异常: \(error.localizedDescription)")
                }
                let ok = (result as? Bool) == true
                if !ok, attempt < 40 {
                    if attempt % 5 == 0 {
                        self.log.append("inject wait attempt=\(attempt)")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.inject(into: webView, attempt: attempt + 1, generation: generation)
                    }
                } else if ok {
                    self.logLine("inject queued/ok attempt=\(attempt)")
                } else {
                    self.logLine("inject GIVE UP after \(attempt)")
                }
            }
        }
    }
}

/// 对齐 Android `ruffle_warm` 降配。
/// iOS 与主进程同 WebContent：解析 ~37MB action 包易 jetsam，默认 vanilla；OOM 后 sticky。
enum RuffleMemPolicy {
    private static let keyCrashed = "ruffle_wasm_crashed"
    private static let keyPreferSimd = "ruffle_prefer_simd"
    private static let defaults = UserDefaults.standard

    static var shouldUseVanilla: Bool {
        if defaults.bool(forKey: keyCrashed) { return true }
        // 未显式打开 SIMD 时默认兼容包（对齐 APK 降配思路）
        return !defaults.bool(forKey: keyPreferSimd)
    }

    static func markWasmCrashed() {
        defaults.set(true, forKey: keyCrashed)
        defaults.set(false, forKey: keyPreferSimd)
    }

    static func markFightHealthy() {
        // 开战成功只清 crash 标记；不自动切回 SIMD，避免再次 OOM
        defaults.set(false, forKey: keyCrashed)
    }
}

struct ReplaySheet: View {
    let act: String
    let replayId: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var log = ReplayDebugLog()
    @State private var statusLine = "启动中…"
    @State private var copiedHint = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ReplayWebView(act: act, replayId: replayId, log: log, statusLine: $statusLine)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(log.showPanel ? "藏日志" : "日志") {
                        log.showPanel.toggle()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    Button("复制") {
                        UIPasteboard.general.string = log.joinedText
                        log.flushToDisk()
                        copiedHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedHint = false }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    Button {
                        log.flushToDisk()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                    }
                    .accessibilityLabel("关闭动画")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if copiedHint {
                    Text("已复制全部日志到剪贴板")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                }

                if log.showPanel {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(log.lines.enumerated()), id: \.offset) { i, line in
                                    Text(line)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(color(for: line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(i)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 160)
                        .background(Color.black.opacity(0.72))
                        .onChange(of: log.lines.count) { _ in
                            if let last = log.lines.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            log.append("=== replay open rid=\(replayId) act=\(act.count)B ===")
        }
        .onDisappear {
            log.append("=== replay close ===")
            log.flushToDisk()
        }
    }

    private func color(for line: String) -> Color {
        if line.contains("FAIL") || line.contains("ERR") || line.contains("失败") || line.contains("异常") {
            return .red
        }
        if line.contains("PACK") || line.contains("action_gg") || line.contains("action_mm") {
            return .orange
        }
        if line.contains("vel ") || line.contains("velocimetry") {
            return .mint
        }
        if line.contains("inject") || line.contains("kick") {
            return .yellow
        }
        return .green.opacity(0.9)
    }
}
