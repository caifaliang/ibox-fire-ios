import Foundation
import WebKit

/// 对齐 Android `RuffleWarmHolder`：跨场保留已解析的 PetFunFight + action_gg。
/// 磁盘已有 ~37MB；贵的是 Ruffle 再 parse。关动画页只 detach，不 destroy。
@MainActor
final class RuffleWarmHolder {
    static let shared = RuffleWarmHolder()

    private(set) var webView: WKWebView?
    private(set) var pageReady = false
    private(set) var actionPackReady = false
    private(set) var preferMm: Bool?
    /// message handler 是否仍挂在 webView 上（重复 remove 会崩）
    private(set) var handlersInstalled = false

    var pendingAct: String?
    var pendingReplayId: String?

    func canReuse(preferMm: Bool) -> Bool {
        guard webView != nil else { return false }
        guard pageReady else { return false }
        if let was = self.preferMm, was != preferMm { return false }
        return true
    }

    func adopt(_ webView: WKWebView, preferMm: Bool) {
        self.webView = webView
        self.preferMm = preferMm
        pageReady = false
        actionPackReady = false
        pendingAct = nil
        pendingReplayId = nil
        // handlersInstalled 由 bind / uninstall 维护
    }

    func markHandlersInstalled(_ on: Bool) {
        handlersInstalled = on
    }

    func markPageReady() { pageReady = true }

    func markActionPackReady() { actionPackReady = true }

    func takePendingAct() -> (String, String)? {
        guard let act = pendingAct else { return nil }
        let id = pendingReplayId ?? "app_replay"
        pendingAct = nil
        pendingReplayId = nil
        return (act, id)
    }

    func detachFromParent() {
        webView?.removeFromSuperview()
    }

    /// 卸掉 script handlers（dismantle / destroy 共用，保证只 remove 一次）
    func uninstallHandlersIfNeeded() {
        guard handlersInstalled, let wv = webView else { return }
        let uc = wv.configuration.userContentController
        uc.removeScriptMessageHandler(forName: "ruffleStatus")
        uc.removeScriptMessageHandler(forName: "ruffleEvent")
        handlersInstalled = false
    }

    func destroy() {
        uninstallHandlersIfNeeded()
        let wv = webView
        webView = nil
        pageReady = false
        preferMm = nil
        actionPackReady = false
        pendingAct = nil
        pendingReplayId = nil
        guard let wv else { return }
        wv.stopLoading()
        wv.navigationDelegate = nil
        wv.load(URLRequest(url: URL(string: "about:blank")!))
    }
}
