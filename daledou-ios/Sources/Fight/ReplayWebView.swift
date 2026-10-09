import SwiftUI
import WebKit

struct ReplayWebView: UIViewRepresentable {
    let act: String
    let replayId: String

    func makeCoordinator() -> Coordinator { Coordinator(act: act, replayId: replayId) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let handler = RuffleSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: RuffleSchemeHandler.scheme)
        context.coordinator.handler = handler

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never

        let url = URL(string: "\(RuffleSchemeHandler.scheme)://local/ruffle_fight/index.html?renderer=canvas")!
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let act: String
        let replayId: String
        var handler: RuffleSchemeHandler?
        private var didInject = false

        init(act: String, replayId: String) {
            self.act = act
            self.replayId = replayId
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didInject else { return }
            didInject = true
            inject(into: webView, attempt: 0)
        }

        private func inject(into webView: WKWebView, attempt: Int) {
            let b64 = Data(act.utf8).base64EncodedString()
            let idEsc = replayId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let js = "window.__injectFightActB64 && window.__injectFightActB64(\"\(b64)\",\"\(idEsc)\")"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self else { return }
                let ok = (result as? Bool) == true
                // Ruffle 可能尚未就绪，短暂重试
                if !ok, attempt < 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.inject(into: webView, attempt: attempt + 1)
                    }
                }
            }
        }
    }
}

struct ReplaySheet: View {
    let act: String
    let replayId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ReplayWebView(act: act, replayId: replayId)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .padding(12)
            }
            .accessibilityLabel("关闭动画")
        }
        .statusBarHidden(true)
    }
}
