import Foundation
import UIKit
import WebKit

/// 一键辅助：主壳已加载**新鲜 xlogin** 后，等 pt 就绪 → ptqrshow → 仅 qrcode 跳 QQ。
/// 禁止点页内「一键登录」（会走 p= →「APP网页申请」授权失败、无切号）。
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

    func resumeAfterQQ() {
        guard let wv = webView, !stopped else { return }
        Task { @MainActor in
            await CookieBridge.restore(QqOneKeyLogin.savedCookies, into: wv)
            _ = await eval(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
            _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
            onEvent(.status("已回 App，正在写入会话…"))
        }
    }

    private func run() async {
        guard let wv = webView else { return }
        onEvent(.status("一键登录：等待登录脚本（可先点页内「切换账号」）…"))

        for round in 0..<120 {
            guard !Task.isCancelled, !stopped else { return }

            let diag = await eval(QqOneKeyLogin.jsPtDiag, in: wv) as? String ?? ""
            if diag != "ready" {
                if round % 5 == 0 {
                    onEvent(.status("一键登录：脚本未就绪 \(diag)（请用页内切号）"))
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }

            if lastOpenedQr.isEmpty || QqOneKeyLogin.qrLikelyExpired {
                if QqOneKeyLogin.qrLikelyExpired {
                    _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                    lastOpenedQr = ""
                }
                onEvent(.status("一键登录：取票中…"))
                _ = await eval(QqOneKeyLogin.jsRequestQr, in: wv)
            }

            try? await Task.sleep(nanoseconds: 450_000_000)

            guard let raw = await eval(QqOneKeyLogin.jsPollStatus, in: wv) as? String,
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = obj["status"] as? String else { continue }

            if status == "failed" {
                _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                lastOpenedQr = ""
                onEvent(.status("取票失败，重试…（仍可用页内切换账号）"))
                continue
            }

            if status == "ready", let qr = obj["url"] as? String, !qr.isEmpty {
                guard QqOneKeyLogin.isAuthorizationQR(qr.removingPercentEncoding ?? qr) else {
                    _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                    lastOpenedQr = ""
                    onEvent(.status("票据无效，已丢弃（避免网页授权失败页）"))
                    continue
                }
                if qr == lastOpenedQr, !QqOneKeyLogin.qrLikelyExpired {
                    _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
                    continue
                }
                lastOpenedQr = qr
                let cookies = await CookieBridge.snapshotQQCookies(from: wv)
                QqOneKeyLogin.rememberAuthorization(loginURL: wv.url, cookies: cookies)
                let ok = QqOneKeyLogin.openWithQrAuthorization(qr, force: true)
                if ok {
                    onEvent(.openedQQ)
                    onEvent(.status("已用 qrcode 跳转 QQ，请确认（可切号）…"))
                } else {
                    onEvent(.status("无法打开 QQ；请在本页点「切换账号」后扫码/继续"))
                }
            }
        }
        if !stopped {
            onEvent(.failed("未跳转 QQ。请在登录页点「切换账号」，或改用扫码/Cookie"))
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
