import Foundation
import UIKit
import WebKit

/// 一键登录取票器：隐藏 WKWebView 跑 graph→xlogin→ptqrshow，前台绝不展示二维码页。
@MainActor
final class OneKeyTicketFetcher: NSObject, WKNavigationDelegate, WKUIDelegate {
    enum Event {
        case status(String)
        case openedQQ
        case loggedIn(cookieHeader: String)
        case failed(String)
    }

    private let onEvent: (Event) -> Void
    private var webView: WKWebView?
    private var task: Task<Void, Never>?
    private var lastOpenedQr = ""
    private var finished = false

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    var loginWebView: WKWebView? { webView }

    func start() {
        cancel()
        finished = false
        lastOpenedQr = ""

        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = LoginURLs.desktopUA
        webView = wv

        onEvent(.status("一键登录：后台准备授权…"))
        guard let url = URL(string: LoginURLs.oneKeyLogin) else {
            onEvent(.failed("授权入口无效"))
            return
        }
        wv.load(URLRequest(url: url))
        task = Task { @MainActor [weak self] in
            await self?.runPipeline()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        QqOneKeyLogin.clearLaunchStamp()
    }

    /// QQ schemacallback / 回前台：在隐藏页 resume
    func resumeAfterQQ() {
        guard let wv = webView, !finished else { return }
        Task { @MainActor in
            await CookieBridge.restore(QqOneKeyLogin.savedCookies, into: wv)
            _ = await eval(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
            _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
            onEvent(.status("已回 App，正在写入会话…"))
            // 等 skey
            for _ in 0..<20 {
                guard !Task.isCancelled, !finished else { return }
                let header = await CookieBridge.waitForSkey(from: wv, attempts: 2, gapMs: 300)
                if LoginURLs.hasRealSkey(header) {
                    finished = true
                    onEvent(.loggedIn(cookieHeader: header))
                    return
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private func runPipeline() async {
        guard let wv = webView else { return }
        for round in 0..<120 {
            guard !Task.isCancelled, !finished else { return }

            let url = wv.url
            if let url, LoginURLs.isOauthLanding(url), LoginURLs.oauthCode(from: url) == nil {
                // 空落地，重走开 authorize
                onEvent(.status("一键登录：重新进入授权…"))
                wv.load(URLRequest(url: URL(string: LoginURLs.oneKeyLogin)!))
                try? await Task.sleep(nanoseconds: 800_000_000)
                continue
            }

            if QqOneKeyLogin.isGraphOAuthPage(url) {
                if let target = await eval(QqOneKeyLogin.jsFindLoginTarget, in: wv) as? String,
                   !target.isEmpty,
                   let turl = URL(string: target) {
                    if QqOneKeyLogin.isWtloginScheme(turl.scheme) {
                        await openQQ(with: turl, from: wv)
                        continue
                    }
                    if turl.host?.contains("ptlogin") == true {
                        onEvent(.status("一键登录：打开登录框…"))
                        wv.load(URLRequest(url: turl))
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        continue
                    }
                }
                _ = await eval(QqOneKeyLogin.jsClickOneKeyButton, in: wv)
            }

            if QqOneKeyLogin.isXloginPage(url) {
                if lastOpenedQr.isEmpty || QqOneKeyLogin.qrLikelyExpired {
                    if QqOneKeyLogin.qrLikelyExpired {
                        _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                        QqOneKeyLogin.clearLaunchStamp()
                        lastOpenedQr = ""
                        onEvent(.status("授权将过期，换新码…"))
                    }
                    if round % 2 == 0 {
                        _ = await eval(QqOneKeyLogin.jsRequestQr, in: wv)
                    }
                }

                try? await Task.sleep(nanoseconds: 350_000_000)

                guard let raw = await eval(QqOneKeyLogin.jsPollStatus, in: wv) as? String,
                      let data = raw.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = obj["status"] as? String else { continue }

                if status == "failed" {
                    _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                    lastOpenedQr = ""
                    onEvent(.status("授权准备失败，重试…"))
                    continue
                }

                if status == "ready", let qr = obj["url"] as? String, !qr.isEmpty {
                    if qr == lastOpenedQr, !QqOneKeyLogin.qrLikelyExpired {
                        _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
                        // 已跳过 QQ 后轮询 Cookie
                        let header = await CookieBridge.readCookieHeader(from: wv)
                        if LoginURLs.hasRealSkey(header) {
                            finished = true
                            onEvent(.loggedIn(cookieHeader: header))
                            return
                        }
                        continue
                    }
                    lastOpenedQr = qr
                    let cookies = await CookieBridge.snapshotQQCookies(from: wv)
                    QqOneKeyLogin.rememberAuthorization(loginURL: wv.url, cookies: cookies)
                    let ok = QqOneKeyLogin.openWithQrAuthorization(qr, force: true)
                    if ok {
                        onEvent(.openedQQ)
                        onEvent(.status("已跳转 QQ，请在 QQ 内切换账号并确认…"))
                    } else {
                        onEvent(.status("无法打开 QQ，请确认已安装手机 QQ"))
                    }
                    continue
                }
            } else {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        if !finished {
            onEvent(.failed("一键登录超时，请重试或改用扫码/Cookie"))
        }
    }

    private func openQQ(with url: URL, from wv: WKWebView) async {
        let cookies = await CookieBridge.snapshotQQCookies(from: wv)
        QqOneKeyLogin.rememberAuthorization(loginURL: wv.url, cookies: cookies)
        let ok = QqOneKeyLogin.openInQQ(url)
        if ok {
            onEvent(.openedQQ)
            onEvent(.status("已跳转 QQ，请在 QQ 内切换账号并确认…"))
        }
    }

    private func eval(_ script: String, in webView: WKWebView) async -> Any? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: result)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        if QqOneKeyLogin.isWtloginScheme(scheme) {
            decisionHandler(.cancel)
            Task { @MainActor in
                await self.openQQ(with: url, from: webView)
            }
            return
        }
        if LoginURLs.isCallbackScheme(scheme) {
            decisionHandler(.cancel)
            resumeAfterQQ()
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
        if let url = navigationAction.request.url {
            if QqOneKeyLogin.isWtloginScheme(url.scheme) {
                Task { @MainActor in await self.openQQ(with: url, from: webView) }
            } else if url.scheme == "http" || url.scheme == "https" {
                webView.load(URLRequest(url: url))
            }
        }
        return nil
    }
}
