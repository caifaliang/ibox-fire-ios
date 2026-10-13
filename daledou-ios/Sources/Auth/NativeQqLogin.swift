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
    private var task: Task<Void, Never>?
    private var stopped = false

    /// 手动 Cookie 罐（不依赖 ephemeral storage 是否真写回）
    private var jar: [String: String] = [:]
    private var jarCookies: [HTTPCookie] = []

    private var qrsig = ""
    private var loginSig = ""
    private var qrcode = ""
    private var opened = false
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var burstRunning = false

    /// 取票成功后的 xlogin，供 WebView 双路径 resume（竞品回壳靠页内 polling）
    private(set) var backupXloginURL: URL?
    /// 跳 QQ 前的 pt 登录 Cookie（含 qrsig），注入 WKWebView
    private(set) var ticketCookies: [HTTPCookie] = []

    /// 含 QQ 安全确认倒计时（约 7s）+ 操作余量
    private let waitQQSeconds: TimeInterval = 180
    /// 取票网络失败可重试；一旦已打开 QQ 则不再取新票
    private let maxTicketAttempts = 3

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        cancel()
        stopped = false
        opened = false
        burstRunning = false
        jar.removeAll()
        jarCookies.removeAll()
        qrsig = ""
        loginSig = ""
        qrcode = ""
        backupXloginURL = nil
        ticketCookies = []

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 40
        // 不用自定义 HTTPCookieStorage()：部分系统上 session 写入与读取容器不一致
        session = URLSession(configuration: cfg)
        task = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        stopped = true
        burstRunning = false
        endBackgroundPoll()
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    /// 单次补轮询
    func nudgePoll() {
        guard !stopped, opened, !qrsig.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            if let outcome = await self.pollOnce() {
                await self.handlePollOutcome(outcome)
            }
        }
    }

    /// 回壳后密集轮询 ~12s：后台挂起时容易错过唯一的 code=0
    func burstPollOnReturn() {
        guard !stopped, opened, !qrsig.isEmpty, !burstRunning else {
            nudgePoll()
            return
        }
        burstRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.burstRunning = false }
            let deadline = Date().addingTimeInterval(12)
            var lastCode = -999
            while Date() < deadline, !self.stopped {
                if let outcome = await self.pollOnce() {
                    let code: Int
                    switch outcome {
                    case .waiting: code = 66
                    case .confirming: code = 67
                    case .expired: code = 65
                    case .success: code = 0
                    case .other(let c): code = c
                    }
                    if code != lastCode {
                        lastCode = code
                        AppViewModel.logOneKey("native_burst", "code=\(code)")
                        if code == 67 {
                            self.onEvent(.status("QQ 确认中…"))
                        } else if code == 66 {
                            self.onEvent(.status("已回 App，等待授权生效…"))
                        }
                    }
                    switch outcome {
                    case .success(let jump):
                        await self.finishSuccess(jumpURL: jump)
                        return
                    case .expired:
                        // 票可能已在后台被消费且我们错过了 0 → 交给 WebView resume
                        AppViewModel.logOneKey("native_burst", "code=65 miss_zero")
                        self.onEvent(.status("票已消费，尝试页内续票…"))
                        return
                    case .other(let c) where c != 66 && c != 67:
                        await self.handlePollOutcome(outcome)
                        return
                    case .waiting, .confirming, .other:
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private func beginBackgroundPoll() {
        endBackgroundPoll()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "daledou-qq-poll") { [weak self] in
            self?.endBackgroundPoll()
        }
        AppViewModel.logOneKey("native_bg", "begin")
    }

    private func endBackgroundPoll() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
        AppViewModel.logOneKey("native_bg", "end")
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
            } catch let err as TicketError {
                AppViewModel.logOneKey("native_ticket_fail", "attempt=\(attempt) \(err.code)")
                if attempt >= maxTicketAttempts {
                    onEvent(.failed("取票失败（\(err.code)），请用扫码或 Cookie"))
                    return
                }
                onEvent(.status("取票重试 \(attempt)/\(maxTicketAttempts)…"))
                try? await Task.sleep(nanoseconds: 600_000_000)
                continue
            } catch {
                let msg = (error as NSError).localizedDescription
                AppViewModel.logOneKey("native_ticket_fail", "attempt=\(attempt) net=\(msg)")
                if attempt >= maxTicketAttempts {
                    onEvent(.failed("取票失败（网络），请用扫码或 Cookie"))
                    return
                }
                continue
            }

            // 跳 QQ 前快照，供 WebView 双路径
            ticketCookies = snapshotCookies()
            beginBackgroundPoll()
            guard openQQ(with: qrcode) else {
                endBackgroundPoll()
                onEvent(.failed("无法打开 QQ，请确认已安装后用扫码或 Cookie"))
                return
            }
            opened = true
            onEvent(.openedQQ)
            onEvent(.status("QQ：等倒计时→继续→同意，然后立刻返回"))
            AppViewModel.logOneKey("native_opened_qq", "qr_host=\(qrHostForLog(qrcode))")

            // 同一轮只开一次 QQ；等待期间绝不重新 ptqrshow（会作废 QQ 里那张票）
            let deadline = Date().addingTimeInterval(waitQQSeconds)
            var lastLogged = -999
            var sawConfirm = false
            while Date() < deadline {
                if stopped || Task.isCancelled {
                    endBackgroundPoll()
                    return
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                if stopped || Task.isCancelled {
                    endBackgroundPoll()
                    return
                }
                guard let outcome = await pollOnce() else { continue }
                let code: Int = {
                    switch outcome {
                    case .waiting: return 66
                    case .confirming: return 67
                    case .expired: return 65
                    case .success: return 0
                    case .other(let c): return c
                    }
                }()
                if code != lastLogged {
                    lastLogged = code
                    AppViewModel.logOneKey("native_poll", "code=\(code)")
                }
                switch outcome {
                case .waiting:
                    continue
                case .confirming:
                    sawConfirm = true
                    onEvent(.status("QQ 确认中…同意后请立刻返回"))
                    continue
                case .expired:
                    endBackgroundPoll()
                    // 已确认过：多半同意成功但错过 0 → 回壳页内续票，禁止重开 QQ
                    if sawConfirm {
                        onEvent(.status("授权可能已完成，正在页内续票…"))
                        return
                    }
                    // 未确认就 65：常见于别处重新取票；提示用户回 App 重试，勿在旧 QQ 页再点同意
                    onEvent(.failed("授权票已失效，请回 App 重新点一键登录"))
                    return
                case .success(let jump):
                    await finishSuccess(jumpURL: jump)
                    return
                case .other(let c):
                    endBackgroundPoll()
                    onEvent(.failed("登录失败（\(c)），请用扫码或 Cookie"))
                    return
                }
            }
            endBackgroundPoll()
            onEvent(.failed("一键登录超时，请用扫码或 Cookie 登录"))
            return
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
        endBackgroundPoll()
        onEvent(.status("授权成功，正在同步 Cookie…"))
        AppViewModel.logOneKey("native_poll", "code=0")
        if let jump = jumpURL {
            AppViewModel.logOneKey("native_check_sig", AppViewModel.sanitizeURLLog(jump))
            // 跟完重定向，吃下 skey / p_skey
            _ = try? await data(for: jump, referer: "https://xui.ptlogin2.qq.com/")
        }
        // 再走一遍 authorize，让 connect 侧带上登录态
        if let auth = URL(string: LoginURLs.oneKeyLogin) {
            _ = try? await data(for: auth, referer: "https://xui.ptlogin2.qq.com/")
        }
        let cookies = snapshotCookies()
        let names = cookies.map(\.name).sorted().joined(separator: ",")
        let hasSkey = jar.keys.contains { $0.lowercased() == "skey" || $0.lowercased() == "p_skey" }
        AppViewModel.logOneKey("native_cookies", "names=\(names) has_skey=\(hasSkey)")
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
        AppViewModel.logOneKey(
            "native_auth",
            "\(AppViewModel.sanitizeURLLog(authResp.url)) status=\(authResp.statusCode) html=\(authHTML.count)"
        )

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

        let (_, xResp) = try await data(for: xlogin, referer: "https://graph.qq.com/")
        backupXloginURL = xlogin
        AppViewModel.logOneKey(
            "native_xlogin",
            "\(AppViewModel.sanitizeURLLog(xlogin)) status=\(xResp.statusCode) jar=\(jarNames())"
        )
        if let sig = jar["pt_login_sig"], !sig.isEmpty {
            loginSig = sig
        }

        let t = String(format: "%.16f", Double.random(in: 0..<1))
        let show = "https://xui.ptlogin2.qq.com/ssl/ptqrshow?s=8&e=0&appid=716027609&type=1"
            + "&u1=https%3A%2F%2Fconnect.qq.com&daid=383&pt_3rd_aid=102067279&t=\(t)"
        guard let showURL = URL(string: show) else { throw TicketError.badURL }
        let (showData, showResp) = try await data(for: showURL, referer: xlogin.absoluteString)
        let body = String(data: showData, encoding: .utf8)
            ?? String(data: showData, encoding: .isoLatin1)
            ?? ""

        AppViewModel.logOneKey(
            "native_ptqrshow",
            "status=\(showResp.statusCode) len=\(body.count) jar=\(jarNames()) head=\(sanitizeBodyHead(body))"
        )

        guard let parsed = Self.parsePtqrshowJSONP(body) else {
            throw TicketError.badTicket
        }
        AppViewModel.logOneKey("native_ptqr_parsed", "ec=\(parsed.ec) qr_len=\(parsed.qrcode.count)")
        guard parsed.ec == 0, !parsed.qrcode.isEmpty else {
            throw TicketError.badTicket
        }
        qrcode = parsed.qrcode

        // 禁止用 PNG 另取 qrsig：会与 type=1 的 qrcode 票不匹配
        guard let sig = jar["qrsig"], !sig.isEmpty else {
            throw TicketError.noQrsig
        }
        qrsig = sig
        if loginSig.isEmpty, let s = jar["pt_login_sig"], !s.isEmpty {
            loginSig = s
        }
        AppViewModel.logOneKey(
            "native_ticket",
            "ec=0 qr_host=\(qrHostForLog(qrcode)) has_qrsig=1 jar=\(jarNames())"
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
        // 优先完整 txz URL；再试仅 k=（部分 QQ 版本更认）
        var tickets = [ticket]
        if let k = QqOneKeyLogin.qrcodeKValue(from: ticket) {
            tickets.append(k)
        }
        var urls: [URL] = []
        for t in tickets {
            guard let launch = QqOneKeyLogin.launchURL(qrAuthorization: t) else { continue }
            urls.append(launch)
            if var c = URLComponents(url: launch, resolvingAgainstBaseURL: false) {
                c.scheme = "wtloginmqq"
                if let u = c.url { urls.append(u) }
            }
        }
        guard let first = urls.first else { return false }
        QqOneKeyLogin.markNativeLaunch(qrAuthorization: ticket)
        // 只 open 一次，避免二次拉起作废票
        let target = urls.first(where: { UIApplication.shared.canOpenURL($0) }) ?? first
        let encSample = target.absoluteString
        let starOk = !encSample.contains("%2A") || ticket.removingPercentEncoding?.contains("*") != true
        AppViewModel.logOneKey(
            "native_open_url",
            "host=\(target.host ?? "?") star_raw=\(ticket.contains("*")) enc_has_%2A=\(encSample.contains("%2A"))"
        )
        _ = starOk
        UIApplication.shared.open(target, options: [:], completionHandler: nil)
        return true
    }

    // MARK: - HTTP + Cookie jar

    private func data(for url: URL, referer: String?) async throws -> (Data, HTTPURLResponse) {
        guard let session else { throw TicketError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(LoginURLs.iphoneUA, forHTTPHeaderField: "User-Agent")
        req.setValue(
            "text/html,application/xhtml+xml,application/javascript,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        if let referer, !referer.isEmpty {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if !jar.isEmpty {
            let header = jar.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
            req.setValue(header, forHTTPHeaderField: "Cookie")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw TicketError.badURL
        }
        ingestCookies(from: http, pageURL: http.url ?? url)
        return (data, http)
    }

    private func ingestCookies(from http: HTTPURLResponse, pageURL: URL) {
        var fields: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            fields["\(k)"] = "\(v)"
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: pageURL)
        for c in parsed {
            jar[c.name] = c.value
            upsertJarCookie(c)
        }
        // 再从 session 自带 storage 拉一次（若系统有写入）
        if let store = session?.configuration.httpCookieStorage {
            let urls = [
                pageURL,
                URL(string: "https://ptlogin2.qq.com/")!,
                URL(string: "https://xui.ptlogin2.qq.com/")!,
                URL(string: "https://ssl.ptlogin2.qq.com/")!,
                URL(string: "https://qq.com/")!,
            ]
            for u in urls {
                if let list = store.cookies(for: u) {
                    for c in list {
                        jar[c.name] = c.value
                        upsertJarCookie(c)
                    }
                }
            }
            if let all = store.cookies {
                for c in all where c.domain.lowercased().contains("qq.com") {
                    jar[c.name] = c.value
                    upsertJarCookie(c)
                }
            }
        }
    }

    private func upsertJarCookie(_ c: HTTPCookie) {
        jarCookies.removeAll { $0.name == c.name && $0.domain == c.domain }
        jarCookies.append(c)
    }

    private func snapshotCookies() -> [HTTPCookie] {
        // 优先完整 HTTPCookie；若只有 jar 字典则合成 .qq.com
        if !jarCookies.isEmpty {
            return jarCookies.filter {
                let d = $0.domain.lowercased()
                return d.contains("qq.com") || d.contains("gtimg.cn")
            }
        }
        var out: [HTTPCookie] = []
        for (name, value) in jar {
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: ".qq.com",
                .path: "/",
                .secure: "TRUE",
            ]
            if let c = HTTPCookie(properties: props) {
                out.append(c)
            }
        }
        return out
    }

    private func jarNames() -> String {
        jar.keys.sorted().joined(separator: ",")
    }

    private func sanitizeBodyHead(_ body: String) -> String {
        let head = String(body.prefix(80))
            .replacingOccurrences(of: "\n", with: " ")
        // 去掉可能的票面内容，只留结构
        if let r = head.range(of: "qrcode") {
            return String(head[..<r.lowerBound]) + "qrcode=…"
        }
        return head
    }

    // MARK: - Parse

    struct PtqrshowResult {
        var ec: Int
        var qrcode: String
    }

    static func parsePtqrshowJSONP(_ body: String) -> PtqrshowResult? {
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

        var code: String {
            switch self {
            case .noXlogin: return "noXlogin"
            case .badURL: return "badURL"
            case .badTicket: return "badTicket"
            case .noQrsig: return "noQrsig"
            }
        }
    }
}
