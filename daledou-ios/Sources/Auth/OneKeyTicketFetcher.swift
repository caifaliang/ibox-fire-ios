import Foundation
import UIKit
import WebKit

/// style=35 xlogin 上取 qrcode，再 `wtloginmqq3?qrcode=` 跳 QQ（竞品 iOS 同款）。
@MainActor
final class OneKeyTicketFetcher: NSObject {
    enum Event {
        case status(String)
        case openedQQ
        case failed(String)
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
        QqOneKeyLogin.clearLaunchStamp()
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
            onEvent(.status("已回 App，正在完成授权…"))
        }
    }

    private func run() async {
        guard let wv = webView else { return }
        onEvent(.status("一键登录：准备跳转 QQ…"))

        for _ in 0..<90 {
            if stopped || Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 400_000_000)

            let diag = await eval(QqOneKeyLogin.jsPtDiag, in: wv) as? String ?? ""
            if diag != "ready" {
                onEvent(.status("一键登录：等待登录页就绪…"))
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
                _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                onEvent(.status("取票失败，重试中…"))
                continue
            }
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
                onEvent(.status("已跳转 QQ，请点「同意」…"))
            } else {
                onEvent(.failed("无法打开 QQ，请确认已安装"))
                return
            }
        }
        if !stopped {
            onEvent(.failed("一键登录超时，请重试或用扫码"))
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
