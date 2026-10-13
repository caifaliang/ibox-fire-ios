import Foundation
import UIKit

/// 原生一键登录：不经过 WKWebView 拉起 QQ。
///
/// 流程：authorize/xlogin 建签 → `ptqrshow` type=1 取票 →
/// `wtloginmqq3://…qlogin?qrcode=&schemacallback=` → 轮询 `ptqrlogin` →
/// 跟 `check_sig` 收 Cookie → 交给壳注入。
@MainActor
final class NativeQqLogin {
    enum Event {
        case status(String)
        case openedQQ
        case succeeded(cookies: [HTTPCookie])
        case failed(String)
    }

    private let onEvent: (Event) -> Void
    private var session: URLSession!
    private var cookieStorage: HTTPCookieStorage!
    private var task: Task<Void, Never>?
    private var stopped = false

    private var qrsig = ""
    private var loginSig = ""
    private var qrcode = ""
    private var opened = false
    private var startedAt = Date()

    /// 等 QQ 同意上限
    private let waitQQSeconds: TimeInterval = 120
    /// 取票最多次数（含失效重取）
    private let maxTicketAttempts = 2

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        cancel()
        stopped = false
        opened = false
        startedAt = Date()
        let store = HTTPCookieStorage()
        store.cookieAcceptPolicy = .always
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = store
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 20
        cookieStorage = store
        session = URLSession(configuration: cfg)
        task = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        stopped = true
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    /// 回壳 / schemacallback：立刻再轮询一次（后台时 Timer 会停）
    func nudgePoll() {
        guard !stopped, opened, !qrsig.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            if let outcome = await self.pollOnce() {
                await self.handlePollOutcome(outcome)
            }
        }
    }

    // MARK: - Main

    private func run() async {
        guard canOpenQQ() else {
            onEvent(.failed("未安装 QQ，请用扫码或 Cookie 登录"))
            return
        }
        onEvent(.status("一键登录：正在取票…"))
        AppViewModel.logOneKey("native_preflight", "ok")

        for attempt in 1...maxTicketAttempts {
            if stopped || Task.isCancelled { return }
            do {
                try await fetchTicket()
            } catch {
                AppViewModel.logOneKey("native_ticket_fail", "attempt=\(attempt)")
                if attempt >= maxTicketAttempts {
                    onEvent(.failed("取票失败，请用扫码或 Cookie 登录"))
                    return
                }
                continue
            }

            guard openQQ(with: qrcode) else {
                onEvent(.failed("无法打开 QQ，请确认已安装后用扫码或 Cookie"))
                return
            }
            opened = true
            onEvent(.openedQQ)
            onEvent(.status("已跳转 QQ，请点「同意」…"))
            AppViewModel.logOneKey("native_opened_qq", "qr_host=\(qrHostForLog(qrcode))")

            let deadline = Date().addingTimeInterval(waitQQSeconds)
            while Date() < deadline {
                if stopped || Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if stopped || Task.isCancelled { return }
                guard let outcome = await pollOnce() else { continue }
                switch outcome {
                case .waiting, .confirming:
                    continue
                case .expired:
                    AppViewModel.logOneKey("native_poll", "code=65")
                    if attempt < maxTicketAttempts {
                        onEvent(.status("二维码已失效，重新取票…"))
                        break
                    }
                    onEvent(.failed("二维码已失效，请用扫码或 Cookie 登录"))
                    return
                case .success(let jump):
                    await finishSuccess(jumpURL: jump)
                    return
                case .other(let code):
                    AppViewModel.logOneKey("native_poll", "code=\(code)")
                    onEvent(.failed("登录失败（\(code)），请用扫码或 Cookie"))
                    return
                }
                // expired → retry outer loop
                if case .expired = outcome { break }
            }
            if Date() >= deadline {
                onEvent(.failed("一键登录超时，请用扫码或 Cookie 登录"))
                return
            }
        }
        onEvent(.failed("取票失败，请用扫码或 Cookie 登录"))
    }

    private func handlePollOutcome(_ outcome: PollOutcome) async {
        switch outcome {
        case .waiting, .confirming:
            break
        case .expired:
            onEvent(.failed("二维码已失效，请用扫码或 Cookie 登录"))
        case .success(let jump):
            await finishSuccess(jumpURL: jump)
        case .other(let code):
            onEvent(.failed("登录失败（\(code)），请用扫码或 Cookie"))
        }
    }

    private func finishSuccess(jumpURL: URL?) async {
        guard !stopped else { return }
        stopped = true
        onEvent(.status("授权成功，正在同步 Cookie…"))
        AppViewModel.logOneKey("native_poll", "code=0")
        if let jump = jumpURL {
            AppViewModel.logOneKey("native_check_sig", AppViewModel.sanitizeURLLog(jump))
            _ = try? await data(for: jump, referer: "https://xui.ptlogin2.qq.com/")
        }
        let cookies = snapshotCookies()
        let names = cookies.map(\.name).sorted().joined(separator: ",")
        AppViewModel.logOneKey("native_cookies", "names=\(names)")
        if cookies.isEmpty {
            onEvent(.failed("未拿到登录 Cookie，请用扫码或 Cookie"))
            return
        }
        onEvent(.succeeded(cookies: cookies))
    }

    // MARK: - Ticket

    private func fetchTicket() async throws {
        qrsig = ""
        loginSig = ""
        qrcode = ""

        let authURL = URL(string: LoginURLs.oneKeyLogin)!
        let (authData, authResp) = try await data(for: authURL, referer: nil)
        let authHTML = String(data: authData, encoding: .utf8)
            ?? String(data: authData, encoding: .isoLatin1)
            ?? ""
        AppViewModel.logOneKey("native_auth", AppViewModel.sanitizeURLLog(authResp.url))

        let xlogin: URL
        if let u = authResp.url,
           (u.host ?? "").lowercased().contains("ptlogin2.qq.com"),
           u.path.lowercased().contains("xlogin") {
            xlogin = u
        } else if let u = LoginURLs.extractXloginURL(fromAuthorizeHTML: authHTML) {
            xlogin = u
        } else if let u = await LoginURLs.resolveLiveXloginURL() {
            xlogin = u
        } else {
            throw TicketError.noXlogin
        }

        _ = try await data(for: xlogin, referer: "https://graph.qq.com/")
        AppViewModel.logOneKey("native_xlogin", AppViewModel.sanitizeURLLog(xlogin))

        if let sig = cookieValue("pt_login_sig") {
            loginSig = sig
        }

        let t = String(format: "%.16f", Double.random(in: 0..<1))
        let show = "https://xui.ptlogin2.qq.com/ssl/ptqrshow?s=8&e=0&appid=716027609&type=1"
            + "&u1=https%3A%2F%2Fconnect.qq.com&daid=383&pt_3rd_aid=102067279&t=\(t)"
        guard let showURL = URL(string: show) else { throw TicketError.badURL }
        let (showData, _) = try await data(for: showURL, referer: xlogin.absoluteString)
        let body = String(data: showData, encoding: .utf8)
            ?? String(data: showData, encoding: .isoLatin1)
            ?? ""

        guard let parsed = Self.parsePtqrshowJSONP(body),
              parsed.ec == 0,
              !parsed.qrcode.isEmpty else {
            throw TicketError.badTicket
        }
        qrcode = parsed.qrcode
        guard let sig = cookieValue("qrsig"), !sig.isEmpty else {
            throw TicketError.noQrsig
        }
        qrsig = sig
        if loginSig.isEmpty, let s = cookieValue("pt_login_sig") {
            loginSig = s
        }
        AppViewModel.logOneKey(
            "native_ticket",
            "ec=0 qr_host=\(qrHostForLog(qrcode)) has_qrsig=1"
        )
    }

    // MARK: - Poll

    private enum PollOutcome {
        case waiting
        case confirming
        case expired
        case success(URL?)
        case other(Int)
    }

    private func pollOnce() async -> PollOutcome? {
        guard !qrsig.isEmpty else { return nil }
        let token = Self.hash33(qrsig)
        var comps = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrlogin")!
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        comps.queryItems = [
            .init(name: "u1", value: "https://connect.qq.com"),
            .init(name: "ptqrtoken", value: String(token)),
            .init(name: "ptredirect", value: "0"),
            .init(name: "h", value: "1"),
            .init(name: "t", value: "1"),
            .init(name: "g", value: "1"),
            .init(name: "from_ui", value: "1"),
            .init(name: "ptlang", value: "2052"),
            .init(name: "action", value: "0-0-\(ms)"),
            .init(name: "js_ver", value: "24051615"),
            .init(name: "js_type", value: "1"),
            .init(name: "login_sig", value: loginSig),
            .init(name: "pt_uistyle", value: "40"),
            .init(name: "aid", value: "716027609"),
            .init(name: "daid", value: "383"),
            .init(name: "pt_3rd_aid", value: "102067279"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await data(for: url, referer: "https://xui.ptlogin2.qq.com/")
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            return Self.parsePtuiCB(text)
        } catch {
            return nil
        }
    }

    // MARK: - Open QQ

    private func canOpenQQ() -> Bool {
        let probes = ["wtloginmqq3://", "wtloginmqq://", "mqq://"]
        for s in probes {
            if let u = URL(string: s), UIApplication.shared.canOpenURL(u) {
                return true
            }
        }
        return false
    }

    private func openQQ(with ticket: String) -> Bool {
        guard let launch = QqOneKeyLogin.launchURL(qrAuthorization: ticket) else { return false }
        QqOneKeyLogin.markNativeLaunch(qrAuthorization: ticket)
        var candidates = [launch]
        if var c = URLComponents(url: launch, resolvingAgainstBaseURL: false) {
            c.scheme = "wtloginmqq"
            if let u = c.url { candidates.append(u) }
        }
        for u in candidates where UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
            return true
        }
        UIApplication.shared.open(launch, options: [:], completionHandler: nil)
        return true
    }

    // MARK: - HTTP

    private func data(for url: URL, referer: String?) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(LoginURLs.iphoneUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/javascript,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer, !referer.isEmpty {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw TicketError.badURL
        }
        return (data, http)
    }

    private func cookieValue(_ name: String) -> String? {
        cookieStorage.cookies?.first { $0.name == name }?.value
    }

    private func snapshotCookies() -> [HTTPCookie] {
        (cookieStorage.cookies ?? []).filter {
            let d = $0.domain.lowercased()
            return d.contains("qq.com") || d.contains("gtimg.cn")
        }
    }

    // MARK: - Parse

    struct PtqrshowResult {
        var ec: Int
        var qrcode: String
    }

    static func parsePtqrshowJSONP(_ body: String) -> PtqrshowResult? {
        // ptui_qrcode_CB({"em":"...","qrcode":"...","ec":0})
        guard let qr = extractJSONString(body, key: "qrcode") else { return nil }
        let ecPat = #""ec"\s*:\s*(\d+)"#
        var ec = -1
        if let r = try? NSRegularExpression(pattern: ecPat),
           let m = r.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           m.numberOfRanges > 1,
           let range = Range(m.range(at: 1), in: body) {
            ec = Int(body[range]) ?? -1
        }
        return PtqrshowResult(ec: ec, qrcode: qr)
    }

    private static func extractJSONString(_ body: String, key: String) -> String? {
        let pat = #""\#(key)"\s*:\s*"((?:\\.|[^"\\])*)""#
        guard let r = try? NSRegularExpression(pattern: pat) else { return nil }
        let ns = NSRange(body.startIndex..., in: body)
        guard let m = r.firstMatch(in: body, range: ns), m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: body) else { return nil }
        var s = String(body[range])
        s = s.replacingOccurrences(of: "\\/", with: "/")
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        s = s.replacingOccurrences(of: "\\\\", with: "\\")
        return s
    }

    private static func parsePtuiCB(_ text: String) -> PollOutcome {
        // ptuiCB('66','0','','0','…', '')
        let pat = #"ptuiCB\(\s*'(\d+)'\s*,\s*'[^']*'\s*,\s*'([^']*)'"#
        guard let r = try? NSRegularExpression(pattern: pat),
              let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges >= 3,
              let codeRange = Range(m.range(at: 1), in: text),
              let urlRange = Range(m.range(at: 2), in: text),
              let code = Int(text[codeRange]) else {
            return .other(-1)
        }
        let jumpRaw = String(text[urlRange])
        switch code {
        case 66: return .waiting
        case 67: return .confirming
        case 65: return .expired
        case 0:
            let jump = jumpRaw.isEmpty ? nil : URL(string: jumpRaw)
            return .success(jump)
        default:
            return .other(code)
        }
    }

    /// 与腾讯前端一致：`ptqrtoken = hash33(qrsig)`
    static func hash33(_ qrsig: String) -> Int {
        var e = 0
        for ch in qrsig.utf16 {
            e += (e << 5) &+ Int(ch)
        }
        return e & 2147483647
    }

    private func qrHostForLog(_ qr: String) -> String {
        if let u = URL(string: qr), let h = u.host {
            return "\(h)\(u.path)"
        }
        return "len=\(qr.count)"
    }

    private enum TicketError: Error {
        case noXlogin, badURL, badTicket, noQrsig
    }
}
