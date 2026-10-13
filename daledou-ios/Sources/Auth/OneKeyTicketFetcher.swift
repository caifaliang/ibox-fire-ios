import Foundation
import UIKit
import WebKit

/// 竞品同款：在 xlogin 页内取票 → `pt.qrcode.polling()` → 拉起 QQ。
/// 一旦打开 QQ，**禁止**再 ptqrshow（否则倒计时后点同意会「二维码已过期」）。
@MainActor
final class OneKeyTicketFetcher: NSObject {
    enum Event {
        case status(String)
        case openedQQ
        case leftAuthPage
        case ticketFailed
        case cannotOpenQQ
        case timeout
        case loginLikelyDone
    }

    private let onEvent: (Event) -> Void
    private weak var webView: WKWebView?
    private var task: Task<Void, Never>?
    private var lastOpenedQr = ""
    private var stopped = false
    private var openedQQ = false
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    init(webView: WKWebView, onEvent: @escaping (Event) -> Void) {
        self.webView = webView
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        cancel()
        stopped = false
        openedQQ = false
        lastOpenedQr = ""
        task = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        stopped = true
        endBG()
        task?.cancel()
        task = nil
    }

    func markOpenedQQ() {
        openedQQ = true
        onEvent(.openedQQ)
    }

    func resumeAfterQQ() {
        guard let wv = webView, !stopped else { return }
        Task { @MainActor in
            await CookieBridge.restore(QqOneKeyLogin.savedCookies, into: wv)
            _ = await eval(QqOneKeyLogin.jsFreezeQr, in: wv)
            _ = await eval(QqOneKeyLogin.jsResumeAfterQQ, in: wv)
            _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
            onEvent(.status("已回 App，正在校验会话…"))
        }
    }

    private func beginBG() {
        endBG()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "daledou-webview-poll") { [weak self] in
            self?.endBG()
        }
    }

    private func endBG() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    private func run() async {
        guard let wv = webView else { return }
        onEvent(.status("一键登录：等待授权页…"))

        var failStreak = 0
        // 阶段 1：取票（最多 ~30s）
        for _ in 0..<75 {
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

            // 已打开 QQ：只保活 polling，绝不再取票
            if openedQQ || !lastOpenedQr.isEmpty {
                break
            }

            _ = await eval(QqOneKeyLogin.jsRequestQr, in: wv)

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
            let decoded = qr.removingPercentEncoding ?? qr
            guard QqOneKeyLogin.isAuthorizationQR(decoded) else {
                AppViewModel.logOneKey("fetcher_bad_qr", "len=\(decoded.count)")
                _ = await eval(QqOneKeyLogin.jsResetQr, in: wv)
                continue
            }

            let cookies = await CookieBridge.snapshotQQCookies(from: wv)
            QqOneKeyLogin.rememberAuthorization(loginURL: wv.url, cookies: cookies)
            // 冻结页内再取票，再拉起 QQ
            _ = await eval(QqOneKeyLogin.jsFreezeQr, in: wv)
            let ok = QqOneKeyLogin.openWithQrAuthorization(qr, force: true)
            if ok {
                lastOpenedQr = qr
                openedQQ = true
                beginBG()
                onEvent(.openedQQ)
                onEvent(.status("QQ：等倒计时→继续→同意，然后立刻返回"))
                AppViewModel.logOneKey("fetcher_opened", "ok")
                break
            } else {
                onEvent(.cannotOpenQQ)
                return
            }
        }

        if !openedQQ {
            if !stopped { onEvent(.timeout) }
            return
        }

        // 阶段 2：等 QQ 同意（最多 180s），只 keepPolling + freeze，不取新票
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if stopped || Task.isCancelled {
                endBG()
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if stopped || Task.isCancelled {
                endBG()
                return
            }
            if !QqOneKeyLogin.isXloginPage(wv.url) {
                // 可能已跳转授权成功
                onEvent(.loginLikelyDone)
                endBG()
                return
            }
            _ = await eval(QqOneKeyLogin.jsFreezeQr, in: wv)
            _ = await eval(QqOneKeyLogin.jsKeepPolling, in: wv)
        }
        endBG()
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
