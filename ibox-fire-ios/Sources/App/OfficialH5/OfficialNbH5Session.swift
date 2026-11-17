import Foundation
import WebKit

/// 对齐 Android OfficialNbH5Activity：uni-app H5 注入 token/userinfo，默认市场页。
final class OfficialNbH5Session: NSObject, ObservableObject {
    static let shared = OfficialNbH5Session()

    static let h5Origin = "https://h5.newbee.net.cn"
    static let marketPath = "#/pages/musicMarket/index"
    static let homePath = "#/pages/home/index"
    static let activityPath = "#/pages/activity/index"
    static let minePath = "#/pages/my/index"

    @Published private(set) var hasCache = false
    @Published private(set) var status = "未打开"
    @Published private(set) var webView: WKWebView?

    private var token = ""
    private var uid = ""
    private var lastNav = "市场"

    private override init() {
        super.init()
    }

    func open(token raw: String, uid: String = "") {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            status = "缺少 NewBee Token"
            return
        }
        token = t
        self.uid = uid
        if let wv = webView {
            inject(into: wv)
            navigate(path: Self.marketPath, label: "市场")
            hasCache = true
            status = "复用 NbH5 · \(lastNav)"
            return
        }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        webView = wv
        hasCache = true
        status = "加载 NbH5…"
        loadMarket(into: wv)
    }

    func tearDown() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        hasCache = false
        status = "已清除 NbH5 缓存"
        token = ""
        uid = ""
    }

    func navigate(path: String, label: String) {
        lastNav = label
        guard let wv = webView else { return }
        let js = """
        (function(){
          var path = \(Self.jsString(path.hasPrefix("#") ? String(path.dropFirst()) : path));
          try {
            if (typeof uni !== 'undefined' && uni.switchTab) {
              uni.switchTab({ url: '/' + path.replace(/^#?\\/?/, '') });
              return 'switchTab';
            }
          } catch(e) {}
          try {
            location.hash = path.charAt(0) === '#' ? path : ('#' + path);
            return 'hash';
          } catch(e) { return String(e); }
        })();
        """
        wv.evaluateJavaScript(js) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = "NbH5 · \(label)"
            }
        }
    }

    private func loadMarket(into wv: WKWebView) {
        let pack = NbH5SessionPack.build(token: token, uid: uid)
        var comp = URLComponents(string: "\(Self.h5Origin)/")!
        comp.fragment = "pages/musicMarket/index"
        var items = comp.queryItems ?? []
        items.append(URLQueryItem(name: "token", value: token))
        comp.queryItems = items
        guard let url = comp.url else { return }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "token")
        // 先装 cookie，再加载
        let store = WKWebsiteDataStore.default().httpCookieStore
        if let cookie = HTTPCookie(properties: [
            .domain: ".newbee.net.cn",
            .path: "/",
            .name: "token",
            .value: token,
            .secure: "TRUE",
        ]) {
            store.setCookie(cookie) { [weak self] in
                DispatchQueue.main.async {
                    wv.load(req)
                    self?.status = "NbH5 · 市场"
                    // 延迟再灌一次注入，覆盖首屏
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self?.inject(into: wv)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.inject(into: wv)
                        _ = pack
                    }
                }
            }
        } else {
            wv.load(req)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.inject(into: wv)
            }
        }
    }

    private func inject(into wv: WKWebView) {
        let pack = NbH5SessionPack.build(token: token, uid: uid)
        wv.evaluateJavaScript(pack.toRuntimeInjectJs()) { [weak self] result, _ in
            DispatchQueue.main.async {
                let r = (result as? String) ?? ""
                if r == "ok" || r.hasPrefix("ok") {
                    self?.status = "NbH5 已注入 · \(self?.lastNav ?? "市场")"
                } else if !r.isEmpty {
                    self?.status = "NbH5 注入: \(r)"
                }
            }
        }
    }

    private static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }
}

extension OfficialNbH5Session: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        inject(into: webView)
        DispatchQueue.main.async { self.hasCache = true }
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

/// 对齐 Android NbH5SessionPack
struct NbH5SessionPack {
    let token: String
    let userInfoJson: String

    static func build(token: String, uid: String = "") -> NbH5SessionPack {
        var ui: [String: Any] = [
            "token": token,
            "is_authentication": 1,
        ]
        if !uid.isEmpty {
            if let n = Int64(uid) { ui["id"] = n } else { ui["id"] = uid }
        }
        let data = (try? JSONSerialization.data(withJSONObject: ui)) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return NbH5SessionPack(token: token, userInfoJson: json)
    }

    func toRuntimeInjectJs() -> String {
        let tok = Self.jsQuote(token)
        let ui = Self.jsQuote(userInfoJson)
        return """
        (function(){
          try {
            var token = \(tok);
            var userinfoRaw = \(ui);
            var userinfoObj = null;
            try { userinfoObj = JSON.parse(userinfoRaw); } catch(e) {}
            function write(k, v) {
              try {
                var s = (typeof v === 'string') ? v : JSON.stringify(v);
                localStorage.setItem(k, s);
              } catch(e) {}
            }
            if (!userinfoObj || typeof userinfoObj !== 'object') userinfoObj = {};
            userinfoObj.token = userinfoObj.token || token;
            userinfoObj.is_authentication = 1;
            write('token', token);
            write('userinfo', userinfoObj);
            write('userInfo', userinfoObj);
            window.__NB_FIRE_TOKEN__ = token;
            window.__NB_FIRE_USERINFO__ = userinfoObj;
            try {
              if (typeof uni !== 'undefined' && uni.setStorageSync) {
                uni.setStorageSync('token', token);
                uni.setStorageSync('userinfo', userinfoObj);
              }
            } catch(e) {}
            try {
              fetch('https://api.newbee.net.cn/api/account', {
                method: 'GET',
                headers: { 'token': token, 'Content-Type': 'application/json;charset=UTF-8' }
              }).then(function(r){ return r.json(); }).then(function(j){
                if (j && (j.code == 1 || j.code === '1') && j.data) {
                  try { localStorage.setItem('userinfo', JSON.stringify(j.data)); } catch(e) {}
                  try { if (uni && uni.setStorageSync) uni.setStorageSync('userinfo', j.data); } catch(e) {}
                }
              }).catch(function(){});
            } catch(e) {}
            window.__NB_FIRE_INJECTED__ = true;
            var has = (typeof uni !== 'undefined' && uni.getStorageSync)
              ? !!uni.getStorageSync('token') : !!localStorage.getItem('token');
            return has ? 'ok' : 'empty';
          } catch(e) { return String(e); }
        })();
        """
    }

    private static func jsQuote(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }
}
