import SwiftUI
import WebKit
import UIKit

/// 完整对齐饭店助手·动画版：flashreplay + wgpu-webgl + PetFunFight-v10.19 + a=replay
struct ReplayWebView: UIViewRepresentable {
    let act: String
    let replayId: String
    @ObservedObject var log: ReplayDebugLog
    @Binding var statusLine: String

    static let petFunFightURL = "https://fightimg.pet.qq.com/swf/gres/main/PetFunFight-v10.19.swf"

    func makeCoordinator() -> Coordinator {
        Coordinator(act: act, replayId: replayId, log: log, statusLine: $statusLine)
    }

    func makeUIView(context: Context) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(red: 24 / 255, green: 20 / 255, blue: 18 / 255, alpha: 1)
        box.autoresizesSubviews = true

        let preferMm = ActionPackPrefetch.preferMm(from: act)
        ActionPackPrefetch.sessionPreferMm = preferMm
        log.append("boot FANDIAN flashreplay replayId=\(replayId) actLen=\(act.count) preferMm=\(preferMm)")
        log.append("diskReady=\(ActionPackPrefetch.isDiskReady(preferMm: preferMm))")

        let warm = RuffleWarmHolder.shared
        if warm.canReuse(preferMm: preferMm), let wv = warm.webView {
            log.append("WARM reuse actionReady=\(warm.actionPackReady)")
            statusLine = "暖机复用…"
            context.coordinator.bind(webView: wv, cold: false)
            Self.pin(wv, in: box)
            DispatchQueue.main.async {
                context.coordinator.startReplay(into: wv)
            }
            return box
        }
        if warm.webView != nil {
            log.append("WARM discard → cold")
            warm.destroy()
        }

        guard let flashRoot = Self.flashRootURL() else {
            let msg = "flashreplay 未打进包"
            statusLine = msg
            log.append(msg)
            let label = UILabel(frame: box.bounds)
            label.text = msg
            label.textColor = .red
            label.numberOfLines = 0
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            box.addSubview(label)
            return box
        }
        log.append("flashRoot=\(flashRoot.path)")

        let config = WKWebViewConfiguration()
        config.processPool = RuffleMemPolicy.sharedProcessPool
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // 饭店助手：LOAD_NO_CACHE / 关 DOM storage
        config.websiteDataStore = .nonPersistent()

        let bridge = """
        window.FlashReplay = {
          onState: function(name, message, token) {
            try {
              window.webkit.messageHandlers.ruffleEvent.postMessage({
                type: 'state',
                name: String(name || ''),
                message: String(message || ''),
                token: String(token || '')
              });
            } catch (e) {}
            try {
              window.webkit.messageHandlers.ruffleStatus.postMessage(
                String(name || '') + (message ? (' ' + message) : '')
              );
            } catch (e) {}
          },
          onUserResume: function() {}
        };
        true;
        """
        let script = WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = true
        wv.backgroundColor = UIColor(red: 24 / 255, green: 20 / 255, blue: 18 / 255, alpha: 1)
        wv.scrollView.backgroundColor = wv.backgroundColor
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            wv.isInspectable = true
        }
        warm.adopt(wv, preferMm: preferMm)
        context.coordinator.bind(webView: wv, cold: true)
        Self.pin(wv, in: box)

        let server = RuffleLocalServer.shared
        server.onLog = { [weak coordinator = context.coordinator] msg in
            coordinator?.logLine(msg)
        }
        do {
            let base = try server.start(flashRoot: flashRoot)
            let pageURL = URL(string: base.absoluteString + "assets/flashreplay/index.html")!
            context.coordinator.pageURL = pageURL
            log.append("HTTP \(base.absoluteString) stack=fandian wgpu-webgl PetFunFight-v10.19")
            statusLine = "加载饭店助手播放器…"
            log.append("load \(pageURL.absoluteString)")
            DispatchQueue.main.async {
                wv.load(URLRequest(url: pageURL))
            }
        } catch {
            let msg = "HTTP start FAIL \(error.localizedDescription)"
            log.append(msg)
            statusLine = msg
        }
        return box
    }

    private static func flashRootURL() -> URL? {
        let bundle = Bundle.main
        if let u = bundle.url(forResource: "index", withExtension: "html", subdirectory: "flashreplay") {
            return u.deletingLastPathComponent()
        }
        if let u = bundle.resourceURL?.appendingPathComponent("flashreplay"),
           FileManager.default.fileExists(atPath: u.appendingPathComponent("index.html").path) {
            return u
        }
        let u = bundle.bundleURL.appendingPathComponent("flashreplay")
        if FileManager.default.fileExists(atPath: u.appendingPathComponent("index.html").path) {
            return u
        }
        return nil
    }

    private static func pin(_ wv: WKWebView, in box: UIView) {
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = true
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.frame = box.bounds
        box.addSubview(wv)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let wv = uiView.subviews.first as? WKWebView {
            context.coordinator.webView = wv
            wv.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let wv = RuffleWarmHolder.shared.webView ?? uiView.subviews.first as? WKWebView {
            wv.navigationDelegate = nil
        }
        RuffleWarmHolder.shared.uninstallHandlersIfNeeded()
        RuffleWarmHolder.shared.detachFromParent()
        coordinator.log.append("WARM detach")
        coordinator.log.flushToDisk()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let act: String
        let replayId: String
        let log: ReplayDebugLog
        weak var webView: WKWebView?
        var pageURL: URL?
        private var injectGeneration = 0
        private var started = false
        private var statusLine: Binding<String>

        init(act: String, replayId: String, log: ReplayDebugLog, statusLine: Binding<String>) {
            self.act = act
            self.replayId = replayId
            self.log = log
            self.statusLine = statusLine
        }

        func bind(webView: WKWebView, cold: Bool) {
            RuffleWarmHolder.shared.uninstallHandlersIfNeeded()
            let uc = webView.configuration.userContentController
            uc.add(self, name: "ruffleStatus")
            uc.add(self, name: "ruffleEvent")
            RuffleWarmHolder.shared.markHandlersInstalled(true)
            webView.navigationDelegate = self
            self.webView = webView
            started = false
        }

        func logLine(_ msg: String) {
            log.append(msg)
            if msg.contains("PACK") || msg.contains("action_") || msg.contains("FAIL")
                || msg.contains("ERR") || msg.contains("OOM") || msg.contains("CDN")
                || msg.contains("state ") {
                statusLine.wrappedValue = msg
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "ruffleStatus", let s = message.body as? String {
                statusLine.wrappedValue = s
                log.append("status \(s)")
                return
            }
            if message.name == "ruffleEvent", let dict = message.body as? [String: Any] {
                let type = dict["type"] as? String ?? ""
                if type == "state" {
                    let name = dict["name"] as? String ?? ""
                    let msg = dict["message"] as? String ?? ""
                    log.append("state \(name) \(msg)")
                    statusLine.wrappedValue = msg.isEmpty ? name : "\(name) \(msg)"
                    if name == "hostReady", !started, let wv = webView {
                        startReplay(into: wv)
                    }
                    if name == "playing" || name == "complete" {
                        RuffleWarmHolder.shared.markActionPackReady()
                        RuffleMemPolicy.markFightHealthy()
                    }
                    if name == "error" {
                        statusLine.wrappedValue = msg.isEmpty ? "播放失败" : msg
                    }
                    return
                }
                log.append("event \(type) \(String(describing: dict))")
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            RuffleWarmHolder.shared.markPageReady()
            log.append("didFinish → wait hostReady / start")
            // hostReady 可能已在 bridge 前发出；兜底再 start
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let wv = self.webView else { return }
                self.startReplay(into: wv)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            log.append("OOM/terminate WebContent (fandian: stop, no reload)")
            RuffleWarmHolder.shared.destroy()
            started = false
            statusLine.wrappedValue = "内存不足，动画已停止"
            webView.loadHTMLString(
                """
                <html><body style="background:#181412;color:#ccc;font:15px -apple-system;padding:28px;line-height:1.5">
                <b style="color:#f66">内存不足</b><br/><br/>
                WebContent 被回收。已对齐饭店助手栈（wgpu-webgl / v10.19）；请关页后重开一次。
                </body></html>
                """,
                baseURL: nil
            )
        }

        func startReplay(into webView: WKWebView) {
            guard !started else { return }
            started = true
            injectGeneration += 1
            let gen = injectGeneration

            let replayObj: [String: Any] = [
                "result": "0",
                "msg": "",
                "string": act,
                "sn": "1",
                "replayType": "0",
                "replayId": replayId,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: replayObj),
                  let replayJson = String(data: data, encoding: .utf8) else {
                logLine("replayJson encode fail")
                started = false
                return
            }
            let b64 = Data(replayJson.utf8).base64EncodedString()
            let idEsc = replayId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let mainURL = ReplayWebView.petFunFightURL
            let js = """
            (function(){
              if (!window.DaledouReplay || !window.DaledouReplay.start) return 'no-api';
              var bin = atob('\(b64)');
              var bytes = new Uint8Array(bin.length);
              for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
              var replayJson = new TextDecoder('utf-8').decode(bytes);
              window.DaledouReplay.setSound(false);
              window.DaledouReplay.setSpeed(1);
              window.DaledouReplay.setQuality('standard');
              window.DaledouReplay.start({
                mainUrl: '\(mainURL)',
                replayId: '\(idEsc)',
                replayJson: replayJson,
                sessionToken: 'ios',
                paused: false,
                sound: false,
                speed: 1,
                quality: 'standard'
              });
              return 'started';
            })()
            """
            statusLine.wrappedValue = "正在加载动画资源…"
            log.append("DaledouReplay.start PetFunFight-v10.19 wgpu-webgl")
            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self, gen == self.injectGeneration else { return }
                if let error {
                    self.logLine("start ERR \(error.localizedDescription)")
                    self.started = false
                    return
                }
                let s = result as? String ?? String(describing: result ?? "")
                self.logLine("start → \(s)")
                if s == "no-api" {
                    self.started = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        guard let self, let wv = self.webView else { return }
                        self.startReplay(into: wv)
                    }
                }
            }
        }
    }
}

enum RuffleMemPolicy {
    private static let keyCrashed = "ruffle_wasm_crashed"
    private static let keyPolicyV = "ruffle_mem_policy_v"
    private static let defaults = UserDefaults.standard
    static let sharedProcessPool = WKProcessPool()

    static func migrateIfNeeded() {
        if defaults.integer(forKey: keyPolicyV) < 3 {
            defaults.set(false, forKey: keyCrashed)
            defaults.set(3, forKey: keyPolicyV)
        }
    }

    static var shouldUseVanilla: Bool {
        migrateIfNeeded()
        return defaults.bool(forKey: keyCrashed)
    }

    static func markWasmCrashed() {
        defaults.set(true, forKey: keyCrashed)
    }

    static func markFightHealthy() {
        defaults.set(false, forKey: keyCrashed)
    }
}

struct ReplaySheet: View {
    let act: String
    let replayId: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var log = ReplayDebugLog()
    @State private var statusLine = "启动中…"
    @State private var copiedHint = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 24 / 255, green: 20 / 255, blue: 18 / 255).ignoresSafeArea()
            ReplayWebView(act: act, replayId: replayId, log: log, statusLine: $statusLine)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(log.showPanel ? "藏日志" : "日志") {
                        log.showPanel.toggle()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    Button("复制") {
                        UIPasteboard.general.string = log.joinedText
                        log.flushToDisk()
                        copiedHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedHint = false }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    Button {
                        log.flushToDisk()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if copiedHint {
                    Text("已复制全部日志")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if log.showPanel {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(log.lines.enumerated()), id: \.offset) { i, line in
                                    Text(line)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.green.opacity(0.9))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(i)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 160)
                        .background(Color.black.opacity(0.72))
                        .onChange(of: log.lines.count) { _ in
                            if let last = log.lines.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .statusBarHidden(true)
        .onAppear { log.append("=== fandian flashreplay open ===") }
        .onDisappear {
            log.append("=== replay close ===")
            log.flushToDisk()
        }
    }
}
