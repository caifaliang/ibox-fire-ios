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

        let handler = RuffleSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: RuffleSchemeHandler.scheme)
        context.coordinator.handler = handler

        let uc = config.userContentController
        uc.add(context.coordinator, name: "ruffleStatus")
        uc.add(context.coordinator, name: "ruffleEvent")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
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

        // iOS：强制 vanilla wasm，避免 SIMD 扩展导致黑屏
        let url = URL(
            string: "\(RuffleSchemeHandler.scheme)://local/ruffle_fight/index.html?renderer=canvas&wasm=vanilla"
        )!
        statusLine = "加载播放器…"
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ruffleStatus")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ruffleEvent")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let act: String
        let replayId: String
        var handler: RuffleSchemeHandler?
        private var didInject = false
        private var statusLine: Binding<String>

        init(act: String, replayId: String, statusLine: Binding<String>) {
            self.act = act
            self.replayId = replayId
            self.statusLine = statusLine
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
                if type == "boot_fail" || type == "inject_fail" {
                    statusLine.wrappedValue = "\(type): \(dict["payload"] ?? "")"
                } else if type == "injected" {
                    statusLine.wrappedValue = "动画数据已注入"
                } else if type == "swf_ready" {
                    statusLine.wrappedValue = "SWF 已就绪…"
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
            guard !didInject else { return }
            didInject = true
            statusLine.wrappedValue = "页面就绪，注入 Act…"
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
                    self.statusLine.wrappedValue = "注入异常: \(error.localizedDescription)"
                }
                let ok = (result as? Bool) == true
                if !ok, attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.inject(into: webView, attempt: attempt + 1)
                    }
                } else if ok {
                    self.statusLine.wrappedValue = "已注入，等待渲染…"
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
