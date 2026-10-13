import Foundation
import UIKit
import WebKit

/// 一键辅助：在**已有** WKWebView（主壳）上等到 pt 就绪后取票并跳 QQ。
/// 主壳需已打开 graph authorize → 新鲜 xlogin（用户可在页内点「切换账号」）。
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
        onEvent(.status("一键登录：等待登录页就绪（可先点「切换账号」）…"))

        for round in 0..<100 {
            guard !Task.isCancelled, !stopped else { return }

            // 等 pt 真正初始化（饭点严格条件）
            let diag = await eval(QqOneKeyLogin.jsPtDiag, in: wv) as? String ?? ""
            if diag != "ready" {
                if round % 4 == 0 {
                    onEvent(.status("一键登录：等待脚本 \(diag.isEmpty ? "…" : diag)（可切号）"))
                }
                // graph 页尝试点进 xlogin / 一键
                if QqOneKeyLogin.isGraphOAuthPage(wv.url) {
                    if let target = await eval(QqOneKeyLogin.jsFindLoginTarget, in: wv) as? String,
                       let u = URL(string: target), u.host?.contains("ptlogin") == true {
                        wv.load(URLRequest(url: u))
                    } else {
                        _ = await eval(QqOneKeyLogin.jsClickOneKeyButton, in: wv)
                    }
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }

            onEvent(.status("一键登录：生成授权并跳转 QQ…"))
            if lastOpenedQr.isEmpty || QqOneKeyLogin.qrLikelyExpired {
                if QqOneKeyLogin.qrLikelyExpired {
                    _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                    lastOpenedQr = ""
                }
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
                onEvent(.status("取票失败，重试中（仍可页内切号）…"))
                continue
            }

            if status == "ready", let qr = obj["url"] as? String, !qr.isEmpty {
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
                    onEvent(.status("已跳转 QQ；若 QQ 提示失败，请回本页用「切换账号」"))
                    // 跳转成功后继续 keep-alive，等回壳
                } else {
                    onEvent(.status("未能打开 QQ，请在本页切换账号或扫码"))
                }
            }
        }
        if !stopped {
            onEvent(.failed("未自动跳转 QQ。请在本页点「切换账号」完成登录，或用扫码/Cookie"))
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
