import Foundation
import UIKit
import WebKit

/// 仅在确认的 xlogin 页取 qrcode；失败分类上报，不在营销页重试。
@MainActor
final class OneKeyTicketFetcher: NSObject {
    enum Event {
        case status(String)
        case openedQQ
        case leftAuthPage
        case ticketFailed
        case cannotOpenQQ
        case timeout
    }

    private let onEvent: (Event) -> Void
    private weak var webView: WKWebView?
    private var task: Task<Void, Never>?
    private var lastOpenedQr = ""
    private var stopped = false

    init(webView: WKWebView, onEvent: @escaping (Event) -> Void) {
        self.webView = webView
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        cancel()
        stopped = false
        lastOpenedQr = ""
        task = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        stopped = true
        task?.cancel()
        task = nil
        // 勿 clearLaunchStamp：回壳 recovering 仍需 launchedQrcode 判定
    }

    func markOpenedQQ() {
        onEvent(.openedQQ)
    }

    func resumeAfterQQ() {
        guard let wv = webView, !stopped else { return }
        Task { @MainActor in
            await CookieBridge.restore(QqOneKeyLogin.savedCookies, into: wv)
            _ = await eval(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
            _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
            onEvent(.status("已回 App，正在校验会话…"))
        }
    }

    private func run() async {
        guard let wv = webView else { return }
        onEvent(.status("一键登录：准备跳转 QQ…"))

        var failStreak = 0
        for _ in 0..<60 {
            if stopped || Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 400_000_000)

            if !QqOneKeyLogin.isXloginPage(wv.url) {
                onEvent(.leftAuthPage)
                return
            }

            let diag = await eval(QqOneKeyLogin.jsPtDiag, in: wv) as? String ?? ""
            if diag != "ready" {
                onEvent(.status("一键登录：等待授权页就绪…"))
                continue
            }

            if lastOpenedQr.isEmpty || QqOneKeyLogin.qrLikelyExpired {
                if QqOneKeyLogin.qrLikelyExpired {
                    _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                    lastOpenedQr = ""
                }
                _ = await eval(QqOneKeyLogin.jsRequestQr, in: wv)
            }

            guard let raw = await eval(QqOneKeyLogin.jsPollStatus, in: wv) as? String,
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = obj["status"] as? String else {
                continue
            }

            if status == "failed" {
                failStreak += 1
                _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                if failStreak >= 3 {
                    onEvent(.ticketFailed)
                    return
                }
                onEvent(.status("取票失败，重试中…"))
                continue
            }
            failStreak = 0
            guard status == "ready", let qr = obj["url"] as? String, !qr.isEmpty else {
                continue
            }
            guard QqOneKeyLogin.isAuthorizationQR(qr.removingPercentEncoding ?? qr) else {
                _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                continue
            }
            if qr == lastOpenedQr, !QqOneKeyLogin.qrLikelyExpired {
                _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
                continue
            }

            let cookies = await CookieBridge.snapshotQQCookies(from: wv)
            QqOneKeyLogin.rememberAuthorization(loginURL: wv.url, cookies: cookies)
            let ok = QqOneKeyLogin.openWithQrAuthorization(qr, force: true)
            if ok {
                lastOpenedQr = qr
                onEvent(.openedQQ)
            } else {
                onEvent(.cannotOpenQQ)
                return
            }
        }
        if !stopped {
            onEvent(.timeout)
        }
    }

    private func eval(_ script: String, in webView: WKWebView) async -> Any? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: result)
            }
        }
    }
}
