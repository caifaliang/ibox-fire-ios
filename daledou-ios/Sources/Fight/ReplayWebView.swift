import SwiftUI
import WebKit
import UIKit

/// 容器承载 Ruffle WKWebView，便于 Warm detach（对齐 APK detachFromParent）。
struct ReplayWebView: UIViewRepresentable {
    let act: String
    let replayId: String
    @ObservedObject var log: ReplayDebugLog
    @Binding var statusLine: String

    func makeCoordinator() -> Coordinator {
        Coordinator(act: act, replayId: replayId, log: log, statusLine: $statusLine)
    }

    func makeUIView(context: Context) -> UIView {
        let box = UIView()
        box.backgroundColor = .black
        box.autoresizesSubviews = true

        let preferMm = ActionPackPrefetch.preferMm(from: act)
        ActionPackPrefetch.sessionPreferMm = preferMm
        // 饭店助手 flashreplay 在 iOS 上假注入/卡 loadingSWC；切回已验证能进 action_gg 的 ruffle_fight
        // 版本戳：若日志不是这一行，说明装的不是本提交 IPA
        log.append("boot RUFFLE_FIGHT build=762e051-fws replayId=\(replayId) actLen=\(act.count) preferMm=\(preferMm)")
        let packRel = preferMm ? ActionPackPrefetch.mmRel : ActionPackPrefetch.ggRel
        let packFile = ActionPackPrefetch.localURL(for: packRel)
        if FileManager.default.fileExists(atPath: packFile.path) {
            let stripped = SwfPrefixStrip.stripFileIfNeeded(packFile)
            let beforeSig = SwfZwsInflate.signature(of: packFile)
            let beforeSize = (try? FileManager.default.attributesOfItem(atPath: packFile.path)[.size] as? NSNumber)?.int64Value ?? 0
            log.append("packFile strip=\(stripped) sig=\(beforeSig) size=\(beforeSize)")
            // 双保险：ensure 若未 inflate，开战前在此强制 ZWS→FWS（写入本日志）
            if beforeSig == "ZWS" {
                statusLine = "预解压动作包…"
                let ok = SwfZwsInflate.inflateFileIfNeeded(packFile) { msg in
                    log.append(msg)
                }
                let afterSig = SwfZwsInflate.signature(of: packFile)
                let afterSize = (try? FileManager.default.attributesOfItem(atPath: packFile.path)[.size] as? NSNumber)?.int64Value ?? 0
                log.append("packInflate ok=\(ok) → sig=\(afterSig) size=\(afterSize)")
                if afterSig == "ZWS" {
                    log.append("WARN still ZWS — WebContent will LZMA (OOM risk)")
                }
            }
        }
        log.append("diskReady=\(ActionPackPrefetch.isDiskReady(preferMm: preferMm)) sig=\(SwfZwsInflate.signature(of: packFile))")

        let warm = RuffleWarmHolder.shared
        if warm.canReuse(preferMm: preferMm), let wv = warm.webView {
            log.append("WARM reuse actionReady=\(warm.actionPackReady)")
            statusLine = warm.actionPackReady ? "暖机复用…" : "暖机等待动作包…"
            context.coordinator.bind(webView: wv, cold: false)
            Self.pin(wv, in: box)
            context.coordinator.pageURL = wv.url
            // 对齐 APK：包已就绪直接 reinject；否则挂 pending
            if warm.actionPackReady {
                DispatchQueue.main.async {
                    context.coordinator.injectNow(into: wv)
                }
            } else {
                warm.pendingAct = act
                warm.pendingReplayId = replayId
                DispatchQueue.main.async {
                    context.coordinator.injectNow(into: wv)
                }
            }
            return box
        }

        // Cold path — 性别/版本变化或首次
        if warm.webView != nil {
            log.append("WARM discard → cold")
            warm.destroy()
        }

        let config = WKWebViewConfiguration()
        config.processPool = RuffleMemPolicy.sharedProcessPool
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let handler = RuffleSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: RuffleSchemeHandler.scheme)
        context.coordinator.handler = handler
        handler.onActionPackEvent = { [weak coordinator = context.coordinator] kind in
            coordinator?.onPackEvent(kind)
        }
        handler.onResourceLog = { [weak coordinator = context.coordinator] msg in
            coordinator?.logLine(msg)
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = true
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            wv.isInspectable = true
        }
        warm.adopt(wv, preferMm: preferMm)
        context.coordinator.bind(webView: wv, cold: true)
        Self.pin(wv, in: box)

        guard handler.rootExists else {
            let msg = "资源缺失: \(handler.rootPath)"
            statusLine = msg
            log.append(msg)
            wv.loadHTMLString(
                "<html><body style='background:#111;color:#f66;font:16px sans-serif;padding:24px'>"
                    + "ruffle_fight 未打进包<br/>\(handler.rootPath)</body></html>",
                baseURL: nil
            )
            return box
        }
        log.append("bundleOK root=\(handler.rootPath)")

        let server = RuffleLocalServer.shared
        server.onLog = { [weak coordinator = context.coordinator] msg in
            coordinator?.logLine(msg)
        }
        RuffleMemPolicy.migrateIfNeeded()
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
        log.append("load \(pageURL.absoluteString) (game WebView already torn down)")
        context.coordinator.pageURL = pageURL
        // AppViewModel 已等 ~1.4s 拆游戏页；此处只再让一帧布局
        DispatchQueue.main.async {
            wv.load(URLRequest(url: pageURL))
        }
        return box
    }

    private static func pin(_ wv: WKWebView, in box: UIView) {
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = true
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.frame = box.bounds
        box.addSubview(wv)
    }

    private static func fightPageURL(base: String, preferMm: Bool, vanilla: Bool, lowmem: Bool = false) -> URL {
        var s = base
        if !s.hasSuffix("/") { s += "/" }
        var q = "renderer=canvas&preferMm=\(preferMm ? 1 : 0)&replay=1&lowmem=\(lowmem ? 1 : 0)"
        if vanilla { q += "&wasm=vanilla" }
        return URL(string: "\(s)ruffle_fight/index.html?\(q)")!
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let wv = uiView.subviews.first as? WKWebView {
            context.coordinator.webView = wv
            wv.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // 对齐 APK：只 detach，不 destroy——保留已 parse 的 action_gg。
        // 必须卸掉 message handler，否则 coordinator 释放后 JS 回调会崩。
        coordinator.handler?.onActionPackEvent = nil
        coordinator.handler?.onResourceLog = nil
        if let wv = RuffleWarmHolder.shared.webView ?? uiView.subviews.first as? WKWebView {
            wv.navigationDelegate = nil
        }
        RuffleWarmHolder.shared.uninstallHandlersIfNeeded()
        RuffleWarmHolder.shared.detachFromParent()
        coordinator.log.append("WARM detach (keep parsed pack)")
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
        private var oomCount = 0
        private var statusLine: Binding<String>
        private var isCold = true

        init(act: String, replayId: String, log: ReplayDebugLog, statusLine: Binding<String>) {
            self.act = act
            self.replayId = replayId
            self.log = log
            self.statusLine = statusLine
        }

        func bind(webView: WKWebView, cold: Bool) {
            // 换 coordinator 时重绑 message handler / navigationDelegate
            RuffleWarmHolder.shared.uninstallHandlersIfNeeded()
            let uc = webView.configuration.userContentController
            uc.add(self, name: "ruffleStatus")
            uc.add(self, name: "ruffleEvent")
            RuffleWarmHolder.shared.markHandlersInstalled(true)
            webView.navigationDelegate = self
            self.webView = webView
            self.isCold = cold
            oomCount = 0
            recoveringFromOOM = false
        }

        func logLine(_ msg: String) {
            log.append(msg)
            if msg.contains("action_gg") || msg.contains("action_mm")
                || msg.contains("FAIL") || msg.contains("ERR")
                || msg.hasPrefix("vel ") || msg.contains("inject")
                || msg.contains("WARM") {
                statusLine.wrappedValue = msg
            }
        }

        func onPackEvent(_ kind: String) {
            if kind == "delivered" {
                let msg = "PACK delivered (gg/mm 已交给 Flash，开始解析)"
                statusLine.wrappedValue = msg
                log.append(msg)
            } else if kind == "parsed" {
                RuffleWarmHolder.shared.markActionPackReady()
                let msg = "PACK parsed (收到 gg2/mm2 请求)"
                statusLine.wrappedValue = msg
                log.append(msg)
                // 双保险：原生侧再踢一次退出 parse-safe（JS fetch 钩子也可能已退出）
                webView?.evaluateJavaScript(
                    "window.__setParseSafe && window.__setParseSafe(false,'native_pack_parsed')",
                    completionHandler: nil
                )
                if let (a, id) = RuffleWarmHolder.shared.takePendingAct(), let wv = webView {
                    log.append("WARM drain pending act=\(a.count)")
                    injectAct(a, id: id, into: wv)
                }
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
                case "injected", "reinjected":
                    statusLine.wrappedValue = "已注入，等待动作包/开战…"
                case "swf_ready":
                    statusLine.wrappedValue = "SWF 就绪…"
                    RuffleWarmHolder.shared.markPageReady()
                    // 开战前仍保持 parse-safe；勿在此恢复舞台
                case "boot_fallback":
                    RuffleMemPolicy.markWasmCrashed()
                    useVanilla = true
                    statusLine.wrappedValue = "改用兼容 wasm…"
                case "velocimetry":
                    if let p = payload as? [String: Any] {
                        let tag = p["tag"] as? String ?? ""
                        let val = p["val"] as? String ?? ""
                        statusLine.wrappedValue = "vel \(tag) \(val)"
                        // APK：velocimetry 6 / CloseFlash ≈ action pack ready
                        if tag == "6" || tag == "sal_base_ok" || tag == "ready_go" || tag == "ra_startRound" {
                            RuffleWarmHolder.shared.markActionPackReady()
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
                        if short.contains("gg2") || short.contains("mm2") {
                            RuffleWarmHolder.shared.markActionPackReady()
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
            RuffleWarmHolder.shared.markPageReady()
            statusLine.wrappedValue = "注入战报…"
            log.append("didFinish → queue inject gen=\(injectGeneration + 1)")
            injectGeneration += 1
            inject(into: webView, attempt: 0, generation: injectGeneration)
        }

        /// jetsam：保持 SIMD；清缓存后再试一次；再失败则停并销毁 warm。
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            oomCount += 1
            log.append("OOM/terminate WebContent count=\(oomCount) (jetsam, keep simd)")
            // 饭店助手：onRenderProcessGone → destroy + 提示，不无限冷启重 parse
            recoveringFromOOM = true
            injectGeneration += 1
            RuffleWarmHolder.shared.destroy()
            let msg = "内存不足，官方动画已停止。请关掉本页后重开一次，或用文字战报。"
            statusLine.wrappedValue = msg
            log.append("OOM STOP (no reload) → \(msg)")
            webView.loadHTMLString(
                """
                <html><body style="background:#111;color:#ccc;font:15px -apple-system;padding:28px;line-height:1.5">
                <b style="color:#f66">内存不足</b><br/><br/>
                解析动作包时 WebContent 被回收（对齐饭店助手：不自动重载）。<br/>
                请关闭后重开一次；日志应含 dpr≈1.x（盖住 3x 屏）。
                </body></html>
                """,
                baseURL: nil
            )
        }

        func injectNow(into webView: WKWebView) {
            injectGeneration += 1
            inject(into: webView, attempt: 0, generation: injectGeneration)
        }

        private func injectAct(_ act: String, id: String, into webView: WKWebView) {
            let b64 = Data(act.utf8).base64EncodedString()
            let idEsc = id
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let js = "window.__injectFightActB64 && window.__injectFightActB64(\"\(b64)\",\"\(idEsc)\")"
            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    self.logLine("注入异常: \(error.localizedDescription)")
                }
                let ok = (result as? Bool) == true
                self.logLine(ok ? "inject queued/ok (direct)" : "inject pending")
            }
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

/// 对齐 Android：默认 SIMD；仅 WASM 编译崩溃才 sticky vanilla。jetsam ≠ wasm crash。
enum RuffleMemPolicy {
    private static let keyCrashed = "ruffle_wasm_crashed"
    private static let keyPolicyV = "ruffle_mem_policy_v"
    private static let defaults = UserDefaults.standard
    static let sharedProcessPool = WKProcessPool()

    static func migrateIfNeeded() {
        if defaults.integer(forKey: keyPolicyV) < 2 {
            defaults.set(false, forKey: keyCrashed)
            defaults.set(2, forKey: keyPolicyV)
        }
    }

    static var shouldUseVanilla: Bool {
        migrateIfNeeded()
        return defaults.bool(forKey: keyCrashed)
    }

    static func markWasmCrashed() {
        defaults.set(true, forKey: keyCrashed)
    }

    static func markFightHealthy() {
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
        if line.contains("inject") || line.contains("kick") || line.contains("WARM") {
            return .yellow
        }
        return .green.opacity(0.9)
    }
}
