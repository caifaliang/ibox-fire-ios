import SwiftUI
import WebKit

/// 线上站 WebView（对齐 Capacitor：加载 https://ai.iboxai.top，注入网站/iBox 登录态）
struct SiteWebView: UIViewRepresentable {
    let url: URL
    let siteToken: String
    let userCacheJSON: String
    let iboxToken: String
    @Binding var reloadToken: Int
    var onTitle: ((String) -> Void)? = nil
    var onLoading: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.websiteDataStore = .default()

        let script = WKUserScript(
            source: Self.bootstrapJS(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        cfg.userContentController.addUserScript(script)

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        // 移动 UA，让站点走 H5 / 仿 App 布局
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 IboxFire/1.0"
        context.coordinator.webView = wv
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            // 刷新前再注入一次，避免 SPA 清掉 localStorage
            uiView.evaluateJavaScript(
                Self.bootstrapJS(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken)
            )
            uiView.reload()
        }
    }

    static func bootstrapJS(siteToken: String, userCacheJSON: String, iboxToken: String) -> String {
        let st = jsonString(siteToken)
        let ib = jsonString(iboxToken)
        let cache = userCacheJSON.isEmpty ? "null" : userCacheJSON
        return """
        (function(){
          try {
            var t = \(st);
            if (t) {
              localStorage.setItem('token', t);
              sessionStorage.setItem('token', t);
            }
            var cache = \(cache);
            if (cache && typeof cache === 'object') {
              localStorage.setItem('userCache', JSON.stringify(cache));
            }
            var ib = \(ib);
            if (ib) {
              localStorage.setItem('snipeToken', ib);
              sessionStorage.setItem('snipeToken', ib);
              document.cookie = 'snipeToken=' + encodeURIComponent(ib) + ';max-age=2592000;path=/;SameSite=Lax';
            }
          } catch (e) {}
        })();
        """
    }

    private static func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: []),
              let out = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return out
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: SiteWebView
        weak var webView: WKWebView?
        var lastReloadToken = 0

        init(_ parent: SiteWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoading?(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading?(false)
            parent.onTitle?(webView.title ?? "")
            // 页面加载后再写一次，覆盖站点初始化脚本
            webView.evaluateJavaScript(
                SiteWebView.bootstrapJS(
                    siteToken: parent.siteToken,
                    userCacheJSON: parent.userCacheJSON,
                    iboxToken: parent.iboxToken
                )
            )
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoading?(false)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
