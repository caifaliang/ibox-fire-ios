import UIKit
import WebKit

/// 纯 UIKit 全屏打开线上站，避开 SwiftUI fullScreenCover + WKWebView 组合闪退。
enum SiteBrowsePresenter {
    static let siteURL = URL(string: "https://ai.iboxai.top/")!

    static func present(siteToken: String, userCacheJSON: String, iboxToken: String) {
        DispatchQueue.main.async {
            guard let host = topViewController() else { return }
            if host is SiteBrowseViewController { return }
            if host.presentedViewController is SiteBrowseViewController { return }
            let vc = SiteBrowseViewController(
                siteToken: siteToken,
                userCacheJSON: userCacheJSON,
                iboxToken: iboxToken
            )
            vc.modalPresentationStyle = .fullScreen
            vc.modalTransitionStyle = .coverVertical
            host.present(vc, animated: true)
        }
    }

    static func userCacheJSON(from user: SiteUser?) -> String {
        guard let u = user else { return "null" }
        let obj: [String: Any] = [
            "token": u.token,
            "username": u.username,
            "is_vip": u.isVip,
            "is_admin": u.isAdmin,
            "is_year_vip": u.isYearVip,
            "is_month_vip": u.isMonthVip,
            "vip_expires_at": u.vipExpiresAt,
        ]
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController? = {
            if let base { return base }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? scenes.first?.windows.first
            return window?.rootViewController
        }()
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}

final class SiteBrowseViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let siteToken: String
    private let userCacheJSON: String
    private let iboxToken: String

    private let chromeBar = UIView()
    private var webView: WKWebView?
    private let titleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let waitSpinner = UIActivityIndicatorView(style: .large)

    init(siteToken: String, userCacheJSON: String, iboxToken: String) {
        self.siteToken = siteToken
        self.userCacheJSON = userCacheJSON
        self.iboxToken = iboxToken
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildChrome()
        // present 动画结束后再建 WKWebView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.mountWebView()
        }
    }

    private func buildChrome() {
        chromeBar.translatesAutoresizingMaskIntoConstraints = false
        chromeBar.backgroundColor = .secondarySystemBackground
        view.addSubview(chromeBar)

        let close = UIButton(type: .system)
        close.setTitle("关闭", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "iBox 站"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let reload = UIButton(type: .system)
        reload.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reload.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        reload.translatesAutoresizingMaskIntoConstraints = false

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        chromeBar.addSubview(close)
        chromeBar.addSubview(titleLabel)
        chromeBar.addSubview(reload)
        chromeBar.addSubview(spinner)

        let hairline = UIView()
        hairline.backgroundColor = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        chromeBar.addSubview(hairline)

        waitSpinner.translatesAutoresizingMaskIntoConstraints = false
        waitSpinner.startAnimating()
        view.addSubview(waitSpinner)

        NSLayoutConstraint.activate([
            chromeBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chromeBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chromeBar.heightAnchor.constraint(equalToConstant: 48),

            close.leadingAnchor.constraint(equalTo: chromeBar.leadingAnchor, constant: 16),
            close.centerYAnchor.constraint(equalTo: chromeBar.centerYAnchor),

            reload.trailingAnchor.constraint(equalTo: chromeBar.trailingAnchor, constant: -16),
            reload.centerYAnchor.constraint(equalTo: chromeBar.centerYAnchor),

            spinner.trailingAnchor.constraint(equalTo: reload.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: chromeBar.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: chromeBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: chromeBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: close.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -8),

            hairline.leadingAnchor.constraint(equalTo: chromeBar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: chromeBar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: chromeBar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            waitSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            waitSpinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func mountWebView() {
        waitSpinner.stopAnimating()
        waitSpinner.removeFromSuperview()
        guard webView == nil else { return }

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        if #available(iOS 14.0, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        cfg.websiteDataStore = .default()
        let js = Self.bootstrapJS(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken)
        cfg.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 IboxFire/1.0"
        view.addSubview(wv)

        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: chromeBar.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        webView = wv
        spinner.startAnimating()
        wv.load(URLRequest(url: SiteBrowsePresenter.siteURL))
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func reloadTapped() {
        let js = Self.bootstrapJS(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken)
        webView?.evaluateJavaScript(js, completionHandler: nil)
        webView?.reload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        spinner.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        let t = webView.title ?? ""
        titleLabel.text = t.isEmpty ? "iBox 站" : t
        let js = Self.bootstrapJS(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken)
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        spinner.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        spinner.stopAnimating()
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

    static func bootstrapJS(siteToken: String, userCacheJSON: String, iboxToken: String) -> String {
        let st = jsonString(siteToken)
        let ib = jsonString(iboxToken)
        let cacheLiteral: String
        if userCacheJSON.isEmpty || userCacheJSON == "null" {
            cacheLiteral = "null"
        } else {
            cacheLiteral = jsonString(userCacheJSON)
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
}
