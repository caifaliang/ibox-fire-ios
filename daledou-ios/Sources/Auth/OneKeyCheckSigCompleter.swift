import Foundation
import UIKit
import WebKit

/// 拉起 QQ 后立刻后台 poll `ptqrlogin`；用户点同意瞬间收 `check_sig`/skey。
/// 回壳再 poll 往往已是 65。只 merge，不清 WK。
@MainActor
enum OneKeyCheckSigCompleter {
    private(set) static var pendingSkeyCookies: [HTTPCookie] = []
    private static var bgTask: Task<Void, Never>?
    private static var uiBgTask: UIBackgroundTaskIdentifier = .invalid

    static func clearPending() {
        bgTask?.cancel()
        bgTask = nil
        pendingSkeyCookies = []
        endUIBackground()
    }

    static func takePendingSkeyCookies() -> [HTTPCookie] {
        let c = pendingSkeyCookies
        pendingSkeyCookies = []
        return c
    }

    private static func beginUIBackground() {
        endUIBackground()
        uiBgTask = UIApplication.shared.beginBackgroundTask(withName: "daledou-check-sig") {
            endUIBackground()
        }
    }

    private static func endUIBackground() {
        guard uiBgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(uiBgTask)
        uiBgTask = .invalid
    }

    /// QQ 已打开：用当前 WebView 的 qrsig 后台收票（与页内 polling 并行）
    static func startBackgroundHarvest(from webView: WKWebView) {
        bgTask?.cancel()
        beginUIBackground()
        bgTask = Task { @MainActor in
            defer { endUIBackground() }
            let cookies = await runHarvestLoop(from: webView, maxRounds: 150, gapMs: 800)
            if !cookies.isEmpty {
                pendingSkeyCookies = cookies
                AppViewModel.logOneKey("check_sig", "bg_got_skey n=\(cookies.count)")
            }
        }
    }

    /// 回壳兜底：再试一轮短 poll（票可能已 65）
    static func tryHarvestSkey(from webView: WKWebView) async -> [HTTPCookie] {
        if !pendingSkeyCookies.isEmpty {
            return takePendingSkeyCookies()
        }
        return await runHarvestLoop(from: webView, maxRounds: 8, gapMs: 600)
    }

    private static func runHarvestLoop(
        from webView: WKWebView,
        maxRounds: Int,
        gapMs: UInt64
    ) async -> [HTTPCookie] {
        let existing = await CookieBridge.snapshotQQCookies(from: webView)
        guard let qrsig = existing.first(where: { $0.name.lowercased() == "qrsig" })?.value,
              !qrsig.isEmpty else {
            AppViewModel.logOneKey("check_sig", "no_qrsig")
            return []
        }
        let loginSig = existing.first(where: {
            $0.name.lowercased() == "pt_login_sig" || $0.name.lowercased() == "login_sig"
        })?.value ?? ""

        var jar: [String: String] = [:]
        var jarCookies: [HTTPCookie] = existing
        for c in existing { jar[c.name] = c.value }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: cfg)
        if let store = cfg.httpCookieStorage {
            for c in existing { store.setCookie(c) }
        }

        AppViewModel.logOneKey("check_sig", "poll_begin rounds=\(maxRounds) qrsig_len=\(qrsig.count)")
        var jump: URL?
        for i in 0..<maxRounds {
            if Task.isCancelled { return [] }
            let outcome = await pollOnce(
                session: session,
                qrsig: qrsig,
                loginSig: loginSig,
                jar: &jar,
                jarCookies: &jarCookies
            )
            switch outcome {
            case .waiting:
                if i == 0 || i == 10 || i == 40 {
                    AppViewModel.logOneKey("check_sig", "poll=66 t=\(i)")
                }
            case .confirming:
                // 67≈用户已扫/确认中；若随后无 callback，说明同意未触发 schemacallback
                AppViewModel.logOneKey("check_sig", "poll=67 agree_signal")
            case .expired:
                AppViewModel.logOneKey("check_sig", "poll=65_expired t=\(i)")
                return []
            case .success(let url):
                jump = url
                AppViewModel.logOneKey("check_sig", "poll=0 ticket_ok t=\(i)")
            case .other(let code):
                AppViewModel.logOneKey("check_sig", "poll=\(code)")
                return []
            case .noResult:
                break
            }
            if jump != nil { break }
            try? await Task.sleep(nanoseconds: gapMs * 1_000_000)
        }
        guard let jump else {
            AppViewModel.logOneKey("check_sig", "no_jump")
            return []
        }

        AppViewModel.logOneKey("check_sig", "follow \(AppViewModel.sanitizeURLLog(jump))")
        _ = await fetch(
            session: session, url: jump,
            referer: "https://xui.ptlogin2.qq.com/",
            jar: &jar, jarCookies: &jarCookies
        )
        if let auth = URL(string: LoginURLs.oneKeyLogin) {
            _ = await fetch(
                session: session, url: auth,
                referer: "https://xui.ptlogin2.qq.com/",
                jar: &jar, jarCookies: &jarCookies
            )
        }

        let names = jar.keys.sorted().joined(separator: ",")
        let hasSkey = jar.keys.contains { $0.lowercased() == "skey" || $0.lowercased() == "p_skey" }
        AppViewModel.logOneKey("check_sig", "done has_skey=\(hasSkey) names=\(names)")
        guard hasSkey else { return [] }
        return jarCookies.filter {
            let n = $0.name.lowercased()
            return n.contains("skey") || n == "uin" || n == "p_uin" || n == "luin"
        }
    }

    private enum Outcome {
        case waiting, confirming, expired, success(URL?), other(Int), noResult
    }

    /// ptlogin hash33：必须 32 位 wrapping；Swift Int `+=`/`<<` 溢出会 EXC_BREAKPOINT（fd74 冷启闪退）
    private static func hash33(_ qrsig: String) -> Int {
        var e: UInt32 = 0
        for ch in qrsig.utf16 {
            e = e &+ ((e &<< 5) &+ UInt32(ch))
        }
        return Int(e & 0x7fff_ffff)
    }

    private static func pollOnce(
        session: URLSession,
        qrsig: String,
        loginSig: String,
        jar: inout [String: String],
        jarCookies: inout [HTTPCookie]
    ) async -> Outcome {
        let token = hash33(qrsig)
        guard var comps = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrlogin") else {
            return .noResult
        }
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
        guard let url = comps.url else { return .noResult }
        guard let text = await fetch(
            session: session, url: url,
            referer: "https://xui.ptlogin2.qq.com/",
            jar: &jar, jarCookies: &jarCookies
        ) else { return .noResult }
        return parsePtuiCB(text)
    }

    private static func fetch(
        session: URLSession,
        url: URL,
        referer: String?,
        jar: inout [String: String],
        jarCookies: inout [HTTPCookie]
    ) async -> String? {
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
            req.setValue(
                jar.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; "),
                forHTTPHeaderField: "Cookie"
            )
        }
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse {
                ingest(http, pageURL: http.url ?? url, jar: &jar, jarCookies: &jarCookies)
            }
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    private static func ingest(
        _ http: HTTPURLResponse,
        pageURL: URL,
        jar: inout [String: String],
        jarCookies: inout [HTTPCookie]
    ) {
        var fields: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            fields["\(k)"] = "\(v)"
        }
        for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: pageURL) {
            jar[c.name] = c.value
            jarCookies.removeAll { $0.name == c.name && $0.domain == c.domain }
            jarCookies.append(c)
        }
    }

    private static func parsePtuiCB(_ text: String) -> Outcome {
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
            return .success(jumpRaw.isEmpty ? nil : URL(string: jumpRaw))
        default:
            return .other(code)
        }
    }
}
