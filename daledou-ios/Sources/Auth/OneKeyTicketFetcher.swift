import Foundation
import UIKit
import WebKit

/// 一键辅助：style=35 新鲜 xlogin 上用 ptqrshow 取 **qrcode** 票据，再 `wtloginmqq3?qrcode=` 跳 QQ。
/// iOS **禁止**点页内「一键登录」/ 打开 `p=`（会进「网页申请使用」→ 授权失败、无切号）。
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

    func markOpenedQQ() {
        onEvent(.openedQQ)
    }

    private func run() async {
        guard let wv = webView else { return }
        onEvent(.status("一键登录：请先在本页切号，随后自动跳 QQ…"))
        _ = await eval(QqOneKeyLogin.jsOneKeyPageHint, in: wv)

        // 给用户约 3s 切号，再开始取票
        for _ in 0..<6 {
            guard !Task.isCancelled, !stopped else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        for round in 0..<100 {
            guard !Task.isCancelled, !stopped else { return }

            let diag = await eval(QqOneKeyLogin.jsPtDiag, in: wv) as? String ?? ""
            if diag != "ready" {
                if round % 5 == 0 {
                    onEvent(.status("一键登录：等待登录页 \(diag)…"))
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }

            if lastOpenedQr.isEmpty || QqOneKeyLogin.qrLikelyExpired {
                if QqOneKeyLogin.qrLikelyExpired {
                    _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                    lastOpenedQr = ""
                }
                onEvent(.status("一键登录：取票中（可先切号）…"))
                _ = await eval(QqOneKeyLogin.jsRequestQr, in: wv)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)

            guard let raw = await eval(QqOneKeyLogin.jsPollStatus, in: wv) as? String,
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = obj["status"] as? String else { continue }

            if status == "failed" {
                _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                lastOpenedQr = ""
                onEvent(.status("取票失败，重试…"))
                continue
            }

            if status == "ready", let qr = obj["url"] as? String, !qr.isEmpty {
                guard QqOneKeyLogin.isAuthorizationQR(qr.removingPercentEncoding ?? qr) else {
                    _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                    lastOpenedQr = ""
                    onEvent(.status("票据无效，已丢弃"))
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
                    onEvent(.status("已跳转 QQ，请确认（可切号）…"))
                    return
                }
                onEvent(.status("无法打开 QQ，请确认已安装"))
            }
        }
        if !stopped {
            onEvent(.failed("未跳转 QQ。请改用扫码登陆或 Cookie"))
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
