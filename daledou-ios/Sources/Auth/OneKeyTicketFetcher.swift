import Foundation
import UIKit
import WebKit

/// 一键辅助：主壳已加载 **style=35 + 新鲜 h5sig** 的 xlogin 后：
/// 等「一键登录」按钮可见 → 点击 → 页内发出 wtlogin?p= → GameWebView 打开 QQ（饭点同路径）。
/// 不再等 `pt.hasInit` / ptqrshow（当前腾讯页已无该 API，会永久 no-init）。
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
    private var stopped = false
    private var didClick = false
    private var opened = false

    init(webView: WKWebView, onEvent: @escaping (Event) -> Void) {
        self.webView = webView
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        cancel()
        stopped = false
        didClick = false
        opened = false
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
        onEvent(.status("一键登录：等待账号列表（可先切号）…"))
        _ = await eval(QqOneKeyLogin.jsOneKeyPageHint, in: wv)

        // 前几秒留给用户切号，再自动点「一键登录」
        for round in 0..<100 {
            guard !Task.isCancelled, !stopped else { return }
            if opened { return }

            if round >= 5 {
                let click = await eval(QqOneKeyLogin.jsClickOneKeyButton, in: wv) as? String ?? ""
                if click == "clicked" {
                    if !didClick {
                        didClick = true
                        onEvent(.status("已点「一键登录」，正在唤起 QQ…"))
                    }
                } else if round % 5 == 0 {
                    onEvent(.status("一键登录：按钮\(click.isEmpty ? "等待" : click)（可先切号）…"))
                }
            } else if round % 2 == 0 {
                onEvent(.status("一键登录：请先切换账号，稍后自动跳 QQ…"))
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if !stopped, !opened {
            onEvent(.failed("未跳转 QQ。请手动点页内「一键登录」，或改用扫码/Cookie"))
        }
    }

    func markOpenedQQ() {
        opened = true
        onEvent(.openedQQ)
    }

    private func eval(_ script: String, in webView: WKWebView) async -> Any? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: result)
            }
        }
    }
}
