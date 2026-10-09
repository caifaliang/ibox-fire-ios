import SwiftUI
import WebKit

struct ReplayWebView: UIViewRepresentable {
    let act: String
    let replayId: String
    @Binding var statusLine: String

    func makeCoordinator() -> Coordinator {
        Coordinator(act: act, replayId: replayId, statusLine: $statusLine)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        ActionPackPrefetch.sessionPreferMm = ActionPackPrefetch.preferMm(from: act)

        let handler = RuffleSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: RuffleSchemeHandler.scheme)
        context.coordinator.handler = handler
        handler.onActionPackEvent = { [weak coordinator = context.coordinator] kind in
            coordinator?.onPackEvent(kind)
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
            statusLine = "资源缺失: \(handler.rootPath)"
            wv.loadHTMLString(
                "<html><body style='background:#111;color:#f66;font:16px sans-serif;padding:24px'>"
                    + "ruffle_fight 未打进包<br/>\(handler.rootPath)</body></html>",
                baseURL: nil
            )
            return wv
        }

        // 与 APK 一致：优先 SIMD（动作包解析快）。失败时 index.html 自动 fallback vanilla
        let url = URL(
            string: "\(RuffleSchemeHandler.scheme)://local/ruffle_fight/index.html?renderer=canvas"
        )!
        statusLine = "加载播放器…"
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
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let act: String
        let replayId: String
        var handler: RuffleSchemeHandler?
        weak var webView: WKWebView?
        private var didInject = false
        private var statusLine: Binding<String>

        init(act: String, replayId: String, statusLine: Binding<String>) {
            self.act = act
            self.replayId = replayId
            self.statusLine = statusLine
        }

        func onPackEvent(_ kind: String) {
            if kind == "delivered" {
                statusLine.wrappedValue = "动作包加载中…"
            } else if kind == "parsed" {
                statusLine.wrappedValue = "动作包已解析"
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "ruffleStatus", let s = message.body as? String {
                statusLine.wrappedValue = s
                return
            }
            if message.name == "ruffleEvent", let dict = message.body as? [String: Any] {
                let type = dict["type"] as? String ?? ""
                switch type {
                case "boot_fail", "inject_fail":
                    statusLine.wrappedValue = "\(type): \(dict["payload"] ?? "")"
                case "injected":
                    statusLine.wrappedValue = "已注入，解析动作中…"
                case "swf_ready":
                    statusLine.wrappedValue = "SWF 就绪…"
                case "boot_fallback":
                    statusLine.wrappedValue = "改用兼容 wasm…"
                default:
                    break
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            statusLine.wrappedValue = "页面失败: \(error.localizedDescription)"
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            statusLine.wrappedValue = "加载失败: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            guard !didInject else { return }
            didInject = true
            statusLine.wrappedValue = "注入战报…"
            inject(into: webView, attempt: 0)
            // 补丁 SWF：倒计时后 ENTER_FRAME 若卡住，原生再踢两次
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak webView] in
                webView?.evaluateJavaScript("window.__kickStartRound && window.__kickStartRound()", completionHandler: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak webView] in
                webView?.evaluateJavaScript("window.__kickStartRound && window.__kickStartRound()", completionHandler: nil)
            }
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
                    self.statusLine.wrappedValue = "注入异常: \(error.localizedDescription)"
                }
                let ok = (result as? Bool) == true
                if !ok, attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.inject(into: webView, attempt: attempt + 1)
                    }
                } else if ok {
                    self.statusLine.wrappedValue = "已注入，等待开打…"
                }
            }
        }
    }
}

struct ReplaySheet: View {
    let act: String
    let replayId: String
    @Environment(\.dismiss) private var dismiss
    @State private var statusLine = "启动中…"

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ReplayWebView(act: act, replayId: replayId, statusLine: $statusLine)
                .ignoresSafeArea()
            HStack {
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
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
        }
        .statusBarHidden(true)
    }
}
