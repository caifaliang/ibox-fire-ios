import SwiftUI
import WebKit

struct OfficialH5WebView: UIViewRepresentable {
    let html: String
    let baseURL: URL
    var onTitle: ((String) -> Void)?
    var onURL: ((String) -> Void)?
    var onProgress: ((Double) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitle: onTitle, onURL: onURL, onProgress: onProgress)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        context.coordinator.bridge = H5ApiBridge(webView: wv)
        context.coordinator.bridge?.attach(to: cfg.userContentController)
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = wv
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            uiView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.bridge?.detach(from: uiView.configuration.userContentController)
        coordinator.bridge = nil
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var bridge: H5ApiBridge?
        weak var webView: WKWebView?
        var loadedHTML: String?
        var onTitle: ((String) -> Void)?
        var onURL: ((String) -> Void)?
        var onProgress: ((Double) -> Void)?
        private var progressObs: NSKeyValueObservation?
        private var titleObs: NSKeyValueObservation?

        init(
            onTitle: ((String) -> Void)?,
            onURL: ((String) -> Void)?,
            onProgress: ((Double) -> Void)?
        ) {
            self.onTitle = onTitle
            self.onURL = onURL
            self.onProgress = onProgress
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            bindObservers(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onURL?(webView.url?.absoluteString ?? "")
            onTitle?(webView.title ?? "")
            onProgress?(1)
        }

        private func bindObservers(_ webView: WKWebView) {
            progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                self?.onProgress?(wv.estimatedProgress)
            }
            titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                self?.onTitle?(wv.title ?? "")
            }
        }
    }
}
