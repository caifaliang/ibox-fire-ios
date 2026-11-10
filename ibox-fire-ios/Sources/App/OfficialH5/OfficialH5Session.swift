import Foundation
import WebKit
import Combine
import ObjectiveC

/// 对齐 APK OfficialH5Activity 保活：WebView 不随「回科技」销毁，再次进入不重复注入。
@MainActor
final class OfficialH5Session: NSObject, ObservableObject {
    static let shared = OfficialH5Session()

    @Published var status = "未启动"
    @Published var progress: Double = 0
    @Published var pageTitle = ""
    @Published var pageURL = ""
    @Published var isReady = false
    @Published var lastError: String?

    private(set) var webView: WKWebView?
    private var bridge: H5ApiBridge?
    private var bootedToken: String = ""
    private var verifyStarted = false
    private var progressObs: NSKeyValueObservation?
    private var titleObs: NSKeyValueObservation?
    private var urlObs: NSKeyValueObservation?

    private override init() { super.init() }

    var hasCache: Bool { webView != nil && isReady }

    func ensureStarted(token: String, refreshToken: String = "", deviceId: String = "", uid: Int64 = 0) {
        let t = JwtUtil.normalize(token)
        guard !t.isEmpty else {
            lastError = "缺少 iBox Token"
            status = "未登录"
            return
        }
        // 已有同票会话：只恢复，不重载
        if let wv = webView, bootedToken == t, isReady {
            status = "已恢复缓存页"
            progress = 1
            return
        }
        if webView != nil, bootedToken != t {
            tearDown()
        }
        bootedToken = t
        lastError = nil
        verifyStarted = false
        isReady = false
        status = "准备官方页…"
        progress = 0.05

        let expSec = JwtUtil.exp(t) ?? 0
        let expMs = expSec > 0 ? expSec * 1000 : 0
        let pack = SharedPrefsPack.build(
            accessToken: t,
            refreshToken: refreshToken,
            deviceId: deviceId.isEmpty ? IboxClient.makeDeviceId(t) : deviceId,
            uid: uid > 0 ? uid : (JwtUtil.uid(t) ?? 0),
            expMs: expMs
        )
        warmCookies(pack)

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        if #available(iOS 14.0, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let uc = cfg.userContentController
        // document-start：禁 SW + 票 + API 桥（对齐 APK 预注入，避免空票启动）
        let startJS = [
            Self.swKillSource,
            H5ApiBridge.bootScriptSource,
            pack.toSyncInjectJs(),
        ].joined(separator: ";\n")
        uc.addUserScript(WKUserScript(source: startJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.navigationDelegate = self
        wv.uiDelegate = self
        let b = H5ApiBridge(webView: wv)
        b.accessToken = t
        b.deviceId = deviceId.isEmpty ? IboxClient.makeDeviceId(t) : deviceId
        // configuration 会拷贝：handler 必须挂到 webView 实际使用的 controller
        b.attach(to: wv.configuration.userContentController)
        bridge = b
        webView = wv
        bindObservers(wv)

        status = "进入官方…"
        var req = URLRequest(url: URL(string: SharedPrefsPack.h5Launcher)!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        wv.load(req)

        // 保存 pack 供 onFinish 补注（struct 需装箱）
        objc_setAssociatedObject(wv, &Associated.packKey, PackBox(pack), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func tearDown() {
        progressObs = nil
        titleObs = nil
        urlObs = nil
        if let wv = webView {
            bridge?.detach(from: wv.configuration.userContentController)
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            wv.stopLoading()
            wv.loadHTMLString("", baseURL: nil)
        }
        bridge = nil
        webView = nil
        bootedToken = ""
        isReady = false
        verifyStarted = false
        status = "未启动"
        progress = 0
    }

    private func bindObservers(_ wv: WKWebView) {
        progressObs = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
            Task { @MainActor in self?.progress = w.estimatedProgress }
        }
        titleObs = wv.observe(\.title, options: [.new]) { [weak self] w, _ in
            Task { @MainActor in
                let t = (w.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, t.lowercased() != "ibox", t != "about:blank" {
                    self?.pageTitle = t
                }
            }
        }
        urlObs = wv.observe(\.url, options: [.new]) { [weak self] w, _ in
            Task { @MainActor in
                if let u = w.url?.absoluteString, u.hasPrefix(SharedPrefsPack.h5Origin) {
                    self?.pageURL = u
                }
            }
        }
    }

    private func warmCookies(_ pack: SharedPrefsPack) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let hosts = ["h5.ibox.art", "sail-api.ibox.art", "personal-center.ibox.art"]
        for host in hosts {
            if let c = HTTPCookie(properties: [
                .domain: ".ibox.art",
                .path: "/",
                .name: "token",
                .value: pack.cookieToken,
                .secure: "TRUE",
            ]) {
                store.setCookie(c)
            }
            if !pack.cookieExpiredAt.isEmpty,
               let c2 = HTTPCookie(properties: [
                   .domain: ".ibox.art",
                   .path: "/",
                   .name: "expiredAt",
                   .value: pack.cookieExpiredAt,
                   .secure: "TRUE",
               ]) {
                store.setCookie(c2)
            }
            _ = host
        }
    }

    private func runVerify(on wv: WKWebView) {
        guard !verifyStarted else { return }
        verifyStarted = true
        status = "确认注入…"
        let pack = (objc_getAssociatedObject(wv, &Associated.packKey) as? PackBox)?.pack
        let reinject = (pack?.toSyncInjectJs() ?? "null") + ";\n" + Self.swKillSource
        wv.evaluateJavaScript(reinject) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let r = Self.normalizeJs(result)
                if !r.hasPrefix("ok"), pack == nil {
                    self.status = "注入失败: \(r)"
                    self.verifyStarted = false
                    return
                }
                self.status = "校验票…"
                wv.evaluateJavaScript(Self.verifyJS) { _, _ in
                    Task { @MainActor in self.pollDecrypt(wv, attempt: 0) }
                }
            }
        }
    }

    private func pollDecrypt(_ wv: WKWebView, attempt: Int) {
        if attempt > 40 {
            status = "校验超时"
            lastError = "校验超时"
            return
        }
        wv.evaluateJavaScript("window.__iboxDec||'pending'") { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let r = Self.normalizeJs(result)
                if r == "pending" || r.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.pollDecrypt(wv, attempt: attempt + 1)
                    }
                } else {
                    self.progress = 1
                    self.isReady = true
                    self.status = "校验 \(r)"
                    wv.evaluateJavaScript(Self.netProbeJS) { _, _ in
                        Task { @MainActor in self.pollNet(wv, verify: r, attempt: 0) }
                    }
                }
            }
        }
    }

    private func pollNet(_ wv: WKWebView, verify: String, attempt: Int) {
        if attempt > 50 { return }
        wv.evaluateJavaScript("window.__iboxNet||'pending'") { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let net = Self.normalizeJs(result)
                if net == "pending" || net.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        self.pollNet(wv, verify: verify, attempt: attempt + 1)
                    }
                } else {
                    self.status = "校验 \(verify) · \(net)"
                }
            }
        }
    }

    private static func normalizeJs(_ result: Any?) -> String {
        guard let result else { return "" }
        if let s = result as? String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 {
                t = String(t.dropFirst().dropLast())
            }
            return t
        }
        return "\(result)"
    }

    private static let swKillSource = """
    (function(){
      try{
        if(navigator.serviceWorker){
          navigator.serviceWorker.register=function(){
            return Promise.reject(new Error('ibox-fire: sw disabled'));
          };
          if(navigator.serviceWorker.getRegistrations){
            navigator.serviceWorker.getRegistrations().then(function(rs){
              rs.forEach(function(r){ try{ r.unregister(); }catch(e){} });
            });
          }
        }
        if(window.caches&&caches.keys){
          caches.keys().then(function(ks){
            ks.forEach(function(k){ try{ caches.delete(k); }catch(e){} });
          });
        }
      }catch(e){}
      return 'sw-kill';
    })()
    """

    private static let verifyJS = """
    (function(){
      window.__iboxDec='pending';
      try{
        function jget(k){
          var raw=localStorage.getItem(k);
          if(raw==null) return null;
          try{ return JSON.parse(raw); }catch(e){ return raw; }
        }
        var tok=jget('flutter.access_token');
        var ui=jget('flutter.user_info');
        if(!tok || typeof tok!=='string' || tok.indexOf('eyJ')!==0){
          window.__iboxDec='miss-tok'; return 'started';
        }
        var obj = ui;
        if (typeof ui === 'string') {
          try { obj = JSON.parse(ui); } catch (e2) { window.__iboxDec='bad-ui'; return 'started'; }
        }
        if (!obj || typeof obj !== 'object') {
          window.__iboxDec='miss-ui'; return 'started';
        }
        var uid = obj && (obj.userId!=null ? obj.userId : obj.user_id);
        window.__iboxDec = 'ok:uid='+uid+':'+location.hash;
      }catch(e){ window.__iboxDec='err:'+(e&&e.message?e.message:e); }
      return 'started';
    })()
    """

    private static let netProbeJS = """
    (function(){
      window.__iboxNet='pending';
      try{
        var api='https://sail-api.ibox.art/public-service/markets?pageNo=1&pageSize=1&segmentId=-1&sortField=2&sortType=0&timeRange=0';
        fetch('https://h5.ibox.art/version.json',{method:'GET',credentials:'omit',cache:'no-store'})
          .then(function(r){
            return fetch(api,{
              method:'GET', credentials:'omit', cache:'no-store', mode:'cors',
              headers:{'Accept':'application/json'}
            }).then(function(r2){
              window.__iboxNet='net:h5='+r.status+',api='+r2.status+(window.IboxFireNet?'+bridge':'');
            }).catch(function(e2){
              window.__iboxNet='net:h5='+r.status+',api-fail:'+((e2&&e2.message)||e2);
            });
          }).catch(function(e){
            window.__iboxNet='net:h5-fail:'+((e&&e.message)||e);
          });
      }catch(e){
        window.__iboxNet='net:err:'+((e&&e.message)||e);
      }
      return 'started';
    })()
    """
}

private enum Associated {
    static var packKey: UInt8 = 0
}

private final class PackBox: NSObject {
    let pack: SharedPrefsPack
    init(_ pack: SharedPrefsPack) { self.pack = pack }
}

extension OfficialH5Session: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let u = webView.url?.absoluteString, u.hasPrefix(SharedPrefsPack.h5Origin) {
            pageURL = u
        }
        runVerify(on: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status = "页面错误: \(error.localizedDescription)"
        lastError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        status = "加载失败: \(error.localizedDescription)"
        lastError = error.localizedDescription
    }
}
