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
        log.append("diskReady=\(ActionPackPrefetch.isDiskReady(preferMm: preferMm))")

        let config = WKWebViewConfiguration()
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

        let url = URL(
            string: "\(RuffleSchemeHandler.scheme)://local/ruffle_fight/index.html?renderer=canvas"
        )!
        statusLine = "加载播放器…"
        log.append("load \(url.absoluteString)")
        wv.load(URLRequest(url: url))
        return wv
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
        private var didInject = false
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
                case "swf_ready":
                    statusLine.wrappedValue = "SWF 就绪…"
                case "boot_fallback":
                    statusLine.wrappedValue = "改用兼容 wasm…"
                case "velocimetry":
                    if let p = payload as? [String: Any] {
                        let tag = p["tag"] as? String ?? ""
                        let val = p["val"] as? String ?? ""
                        statusLine.wrappedValue = "vel \(tag) \(val)"
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
            guard !didInject else { return }
            didInject = true
            statusLine.wrappedValue = "注入战报…"
            log.append("didFinish → queue inject")
            inject(into: webView, attempt: 0)
        }

        private func inject(into webView: WKWebView, attempt: Int) {
            let b64 = Data(act.utf8).base64EncodedString()
            let idEsc = replayId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let js = "window.__injectFightActB64 && window.__injectFightActB64(\"\(b64)\",\"\(idEsc)\")"
            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    self.logLine("注入异常: \(error.localizedDescription)")
                }
                let ok = (result as? Bool) == true
                if !ok, attempt < 40 {
                    if attempt % 5 == 0 {
                        self.log.append("inject wait attempt=\(attempt)")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.inject(into: webView, attempt: attempt + 1)
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
