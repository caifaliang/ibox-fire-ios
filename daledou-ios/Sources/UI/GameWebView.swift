import SwiftUI
import UIKit
import WebKit

struct GameWebView: UIViewRepresentable {
    @ObservedObject var vm: AppViewModel
    /// 退出时递增，触发清 Cookie + 重载
    var clearEpoch: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.webView = wv

        Task { @MainActor in
            let cookie = SessionStore.shared.cookieHeader
            if !cookie.isEmpty {
                await CookieBridge.inject(cookieHeader: cookie, into: wv)
            }
            let start = LoginURLs.shellStartUrl(cookie: cookie)
            if let u = URL(string: start) {
                wv.load(URLRequest(url: u))
            }
        }
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.vm = vm

        if context.coordinator.lastClearEpoch != clearEpoch {
            context.coordinator.lastClearEpoch = clearEpoch
            let next = vm.pendingURL
            Task { @MainActor in
                await CookieBridge.clearAll(from: webView)
                if let u = next {
                    webView.load(URLRequest(url: u))
                    vm.pendingURL = nil
                } else if let u = URL(string: LoginURLs.xloginHome) {
                    webView.load(URLRequest(url: u))
                }
            }
            return
        }

        if let u = vm.pendingURL {
            context.coordinator.consumePending = true
            webView.load(URLRequest(url: u))
            DispatchQueue.main.async { vm.pendingURL = nil }
        }

        if context.coordinator.lastReloadToken != vm.webReloadToken {
            context.coordinator.lastReloadToken = vm.webReloadToken
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var vm: AppViewModel
        weak var webView: WKWebView?
        var lastReloadToken = 0
        var lastClearEpoch = 0
        var consumePending = false
        private var captureTask: Task<Void, Never>?

        init(vm: AppViewModel) {
            self.vm = vm
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url
            Task { @MainActor in
                vm.currentURLString = url?.absoluteString ?? ""
            }
            scheduleCookieCapture(webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            // QQ / 自定义 scheme：交给系统
            if scheme == "daledouapp" {
                Task { @MainActor in vm.handleOpenURL(url) }
                decisionHandler(.cancel)
                return
            }
            if ["wtloginmqq", "wtloginmqq2", "mqq", "mqqapi", "mqqopensdkapi"].contains(scheme) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
                return
            }
            // 其它 scheme 尝试打开
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // target=_blank → 当前页打开
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func scheduleCookieCapture(_ webView: WKWebView) {
            captureTask?.cancel()
            captureTask = Task { @MainActor in
                // 等跳转链写完 Cookie
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                let header = await CookieBridge.readCookieHeader(from: webView)
                if LoginURLs.hasRealSkey(header) {
                    vm.onCookiesCaptured(header)
                }
            }
        }
    }
}
