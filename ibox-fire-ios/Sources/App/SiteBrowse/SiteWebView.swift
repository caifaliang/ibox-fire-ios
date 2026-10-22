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
        if #available(iOS 14.0, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        // 独立数据仓，避免与系统 Safari 冲突
        cfg.websiteDataStore = WKWebsiteDataStore.default()

        let js = Self.bootstrapJS(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken)
        cfg.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 IboxFire/1.0"
        context.coordinator.webView = wv
        context.coordinator.lastReloadToken = reloadToken
        // 延后一拍加载，避开 SwiftUI present 动画中同步建页闪退
        DispatchQueue.main.async {
            wv.load(URLRequest(url: self.url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastReloadToken != reloadToken else { return }
        context.coordinator.lastReloadToken = reloadToken
        let js = Self.bootstrapJS(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken)
        DispatchQueue.main.async {
            uiView.evaluateJavaScript(js, completionHandler: nil)
            uiView.reload()
        }
    }

    static func bootstrapJS(siteToken: String, userCacheJSON: String, iboxToken: String) -> String {
        let st = jsonString(siteToken)
        let ib = jsonString(iboxToken)
        // userCache 必须是合法 JSON 对象字面量或 null；再包一层字符串解析更稳
        let cacheLiteral: String
        if userCacheJSON.isEmpty || userCacheJSON == "null" {
            cacheLiteral = "null"
        } else {
            cacheLiteral = jsonString(userCacheJSON) // 变成 JS 字符串，再 JSON.parse
        }
        return """
        (function(){
          try {
            var t = \(st);
            if (t) {
              localStorage.setItem('token', t);
              sessionStorage.setItem('token', t);
            }
            var cacheRaw = \(cacheLiteral);
            if (cacheRaw) {
              try {
                var cache = (typeof cacheRaw === 'string') ? JSON.parse(cacheRaw) : cacheRaw;
                if (cache && typeof cache === 'object') {
                  localStorage.setItem('userCache', JSON.stringify(cache));
                }
              } catch (_) {}
            }
            var ib = \(ib);
            if (ib) {
              localStorage.setItem('snipeToken', ib);
              sessionStorage.setItem('snipeToken', ib);
              try {
                document.cookie = 'snipeToken=' + encodeURIComponent(ib) + ';max-age=2592000;path=/;SameSite=Lax';
              } catch (_) {}
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
        var lastReloadToken = -1

        init(_ parent: SiteWebView) { self.parent = parent }

        private func ui(_ block: @escaping () -> Void) {
            if Thread.isMainThread { block() }
            else { DispatchQueue.main.async(execute: block) }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            let cb = parent.onLoading
            ui { cb?(true) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let title = webView.title ?? ""
            let onTitle = parent.onTitle
            let onLoading = parent.onLoading
            let js = SiteWebView.bootstrapJS(
                siteToken: parent.siteToken,
                userCacheJSON: parent.userCacheJSON,
                iboxToken: parent.iboxToken
            )
            ui {
                onLoading?(false)
                onTitle?(title.isEmpty ? "iBox 站" : title)
            }
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let cb = parent.onLoading
            ui { cb?(false) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let cb = parent.onLoading
            ui { cb?(false) }
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
