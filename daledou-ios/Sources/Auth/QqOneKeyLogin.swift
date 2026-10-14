import Foundation
import UIKit

/// QQ 一键登录 — 对齐竞品 **iOS** FandianAssistant（非安卓 p=）。
///
/// 实机对拍：竞品也切不了号，但能点「同意」；回 App 后手动刷新才能拿到 Cookie。
/// 本实现：`ptqrshow` → `wtloginmqq3?qrcode=&schemacallback=daledoulogin://` →
/// 回壳后 restore + resume + **自动刷新 phonepk** 取 Cookie。
/// 禁止 `p=`（iOS 会「登录授权失败」）。
enum QqOneKeyLogin {
    static let callbackScheme = "daledoulogin"
    static let callbackURLString = "daledoulogin://"
    static let callbackSchemeAlt = "com.daledou.ioslogin"

    static let qrRefreshSeconds: TimeInterval = 40

    private(set) static var pendingJumpURL: URL?
    private(set) static var awaitingReturn = false
    private(set) static var launchedQrcode: String?
    private(set) static var launchedAt: Date?
    private(set) static var savedCookies: [HTTPCookie] = []
    private(set) static var savedLoginURL: URL?

    static func isWtloginScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased(), !s.isEmpty else { return false }
        return s.hasPrefix("wtlogin") || s.hasPrefix("mqq")
    }

    static func isOurCallback(_ url: URL) -> Bool {
        let s = (url.scheme ?? "").lowercased()
        return s == callbackScheme
            || s == callbackSchemeAlt
            || s == "daledouapp"
            || s == LoginURLs.tencentScheme.lowercased()
            || s.hasPrefix("tencent")
    }

    static func isXloginPage(_ url: URL?) -> Bool {
        guard let u = url, let host = u.host?.lowercased() else { return false }
        return host.contains("ptlogin2.qq.com") && u.path.lowercased().contains("xlogin")
    }

    static var qrLikelyExpired: Bool {
        guard let t = launchedAt else { return false }
        return Date().timeIntervalSince(t) >= qrRefreshSeconds
    }

    // MARK: - 注入脚本（对齐竞品二进制字面量）

    /// 申请 QR：style=35 上挂 ptui_qrcode_CB + ptqrshow（竞品同款参数）
    static let jsRequestQr = """
    (() => {
        if (location.protocol !== 'https:' || !/\\.ptlogin2\\.qq\\.com$/i.test(location.hostname) ||
            location.pathname.indexOf('xlogin') < 0) return 'waiting';
        if (typeof pt === 'undefined' || !pt.qrcode ||
            pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/' ||
            typeof pt.qrcode.polling !== 'function') return 'waiting';
        if (window.__dldQrRequested) return window.__dldQrStatus === 'ready' ? 'ready' : 'requested';
        window.__dldQrRequested = true;
        window.__dldQrStatus = 'waiting';
        window.__dldQrAuthorization = '';
        window.ptui_qrcode_CB = response => {
            if (response && response.ec === 0 && typeof response.qrcode === 'string' && response.qrcode.length > 0) {
                window.__dldQrAuthorization = response.qrcode;
                window.__dldQrStatus = 'ready';
                try { pt.qrcode.used = true; pt.qrcode.polling(); } catch (e) {}
            } else {
                window.__dldQrStatus = 'failed';
            }
        };
        try { pt.qrcode.used = true; pt.qrcode.done = false; } catch (e) {}
        const request = document.createElement('script');
        request.src = 'https://xui.ptlogin2.qq.com/ssl/ptqrshow?s=8&e=0&appid=716027609&type=1' +
            '&u1=https%3A%2F%2Fconnect.qq.com&daid=383&pt_3rd_aid=102067279&t=' + Math.random();
        request.onerror = () => { window.__dldQrStatus = 'failed'; try { request.remove(); } catch (e) {} };
        request.onload = () => {
            try { request.remove(); } catch (e) {}
            setTimeout(() => {
                if (window.__dldQrStatus === 'waiting') window.__dldQrStatus = 'failed';
            }, 2500);
        };
        document.head.appendChild(request);
        return 'requested';
    })();
    """

    static let jsPtDiag = """
    (() => {
        if (location.protocol !== 'https:' || !/\\.ptlogin2\\.qq\\.com$/i.test(location.hostname) ||
            location.pathname.indexOf('xlogin') < 0) {
            return 'page:' + location.hostname + location.pathname;
        }
        if (typeof pt === 'undefined') return 'no-pt';
        if (!pt.qrcode) return 'no-qrcode';
        if (pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/') return 'bad-loginUrl';
        return 'ready';
    })();
    """

    static let jsPollStatus = """
    (() => {
        if (location.protocol !== 'https:' || !/\\.ptlogin2\\.qq\\.com$/i.test(location.hostname) ||
            location.pathname.indexOf('xlogin') < 0) {
            return JSON.stringify({status:'waiting',url:'',qrsig:false});
        }
        var hasSig = document.cookie.split(';').some(function(v){ return v.trim().indexOf('qrsig=')===0; });
        return JSON.stringify({
            status: window.__dldQrStatus || 'waiting',
            url: window.__dldQrAuthorization || '',
            qrsig: hasSig
        });
    })();
    """

    static let jsKeepPolling = """
    (() => {
        if (typeof pt === 'undefined' || !pt.qrcode || typeof pt.qrcode.polling !== 'function') return 'no';
        try { pt.qrcode.used = true; pt.qrcode.polling(); } catch (e) { return 'err'; }
        return 'ok';
    })();
    """

    /// QQ 已同意后：polling + qlogin_submit（竞品 resume）
    static let jsResumeAfterQQ = """
    (() => {
        if (location.protocol !== 'https:' || !/\\.ptlogin2\\.qq\\.com$/i.test(location.hostname) ||
            location.pathname.indexOf('xlogin') < 0) return 'other-page';
        if (typeof pt === 'undefined' || pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/' ||
            !pt.qrcode || typeof pt.qrcode.polling !== 'function') return 'waiting';
        if (!document.cookie.split(';').some(value => value.trim().startsWith('qrsig='))) return 'missing-session';
        pt.qrcode.used = true;
        pt.qrcode.polling();
        try { $.http.loadScript(pt.qlogin_submit(pt.qrcode.CGI)); } catch (e) { return 'submit-err'; }
        return 'resumed';
    })();
    """

    static let jsResetQr = """
    (() => {
        if (window.__dldQrFrozen) return 'frozen';
        window.__dldQrRequested = false;
        window.__dldQrStatus = 'waiting';
        window.__dldQrAuthorization = '';
        try { if (pt && pt.qrcode) { pt.qrcode.done = false; pt.qrcode.used = false; } } catch (e) {}
        return 'ok';
    })();
    """

    /// 打开 QQ 后冻结：拦截后续 ptqrshow，避免票被刷新导致「二维码已过期」
    static let jsFreezeQr = """
    (() => {
        window.__dldQrFrozen = true;
        try {
            if (pt && pt.qrcode) {
                pt.qrcode.used = true;
                pt.qrcode.done = false;
            }
        } catch (e) {}
        if (!window.__dldPtqrHooked) {
            window.__dldPtqrHooked = true;
            const ce = document.createElement.bind(document);
            document.createElement = function(tag) {
                const el = ce(tag);
                try {
                    if (String(tag).toLowerCase() === 'script') {
                        const sa = el.setAttribute.bind(el);
                        el.setAttribute = function(name, value) {
                            if (window.__dldQrFrozen && String(name).toLowerCase() === 'src' &&
                                String(value).indexOf('ptqrshow') >= 0) {
                                return;
                            }
                            return sa(name, value);
                        };
                        try {
                            Object.defineProperty(el, 'src', {
                                configurable: true,
                                set: function(v) {
                                    if (window.__dldQrFrozen && String(v).indexOf('ptqrshow') >= 0) return;
                                    sa('src', v);
                                },
                                get: function() { return el.getAttribute('src'); }
                            });
                        } catch (e2) {}
                    }
                } catch (e3) {}
                return el;
            };
        }
        // 撤掉页面上尚未执行的 ptqrshow script
        try {
            document.querySelectorAll('script[src*="ptqrshow"]').forEach(function(n) {
                try { n.remove(); } catch (e) {}
            });
        } catch (e) {}
        return 'frozen';
    })();
    """

    /// 不再藏 #onekey / 不再盖蓝条（会闪一下消失，体验差）。
    /// 用户点页内按钮若走 p=，原生拦截后改 qrcode 取票；Fetcher 也会自动跳 QQ。
    static let jsOneKeyPageHint = """
    (() => { return 'ok'; })();
    """

    // MARK: - Launch

    /// type=1 现网返回 `http://txz.qq.com/p?k=…&f=appid`；旧路径偶发纯字母数字票。
    static func isAuthorizationQR(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 16 else { return false }
        if s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            return true
        }
        let lower = s.lowercased()
        if lower.hasPrefix("http://txz.qq.com/") || lower.hasPrefix("https://txz.qq.com/") {
            return true
        }
        if lower.contains("txz.qq.com/p?k=") || lower.contains("txz.qq.com/p?k%") {
            return true
        }
        return false
    }

    /// 对齐 JS `encodeURIComponent`：保留 `*` `!` `~` `'` `(` `)`。
    /// 之前把 `*` 编成 `%2A` 会导致 QQ 校验票失败 → 倒计时后点同意报「二维码已过期」。
    private static let jsEncodeURIComponentAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-_.!~*'()")
        return s
    }()

    static func launchURL(qrAuthorization: String) -> URL? {
        let ticket = qrAuthorization.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticket.isEmpty else { return nil }
        let decoded = ticket.removingPercentEncoding ?? ticket
        let qrEnc = decoded.addingPercentEncoding(withAllowedCharacters: jsEncodeURIComponentAllowed)
            ?? decoded
        let cb = callbackURLString.addingPercentEncoding(withAllowedCharacters: jsEncodeURIComponentAllowed)
            ?? "daledoulogin%3A%2F%2F"
        let s = "wtloginmqq3://ptlogin/qlogin?qrcode=\(qrEnc)&schemacallback=\(cb)"
        return URL(string: s) ?? (NSURL(string: s) as URL?)
    }

    /// 从 txz URL 抽出 k=，作备用拉起参数
    static func qrcodeKValue(from ticket: String) -> String? {
        let raw = (ticket.removingPercentEncoding ?? ticket).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: raw),
              let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems,
              let k = items.first(where: { $0.name == "k" })?.value,
              k.count >= 16 else { return nil }
        return k
    }

    private static let awaitingReturnDefaultsKey = "daledou.oneKeyAwaitingReturn"
    private static let persistedCookiesKey = "daledou.oneKeyLaunchCookies"
    private static let persistedLoginURLKey = "daledou.oneKeyLoginURL"

    private struct PersistedCookie: Codable {
        var name: String
        var value: String
        var domain: String
        var path: String
    }

    /// 进程被杀后仍能在冷启动识别「一键去了 QQ 还没收尾」
    static var persistedAwaitingReturn: Bool {
        get { UserDefaults.standard.bool(forKey: awaitingReturnDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: awaitingReturnDefaultsKey) }
    }

    /// 拉起 QQ 前把 qrsig 等落到 UserDefaults（防 jetsam 后 WK Cookie 未刷盘）
    static func persistLaunchSession(loginURL: URL?, cookies: [HTTPCookie]) {
        let rows = cookies.map {
            PersistedCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path.isEmpty ? "/" : $0.path)
        }
        if let data = try? JSONEncoder().encode(rows) {
            UserDefaults.standard.set(data, forKey: persistedCookiesKey)
        }
        if let s = loginURL?.absoluteString, !s.isEmpty {
            UserDefaults.standard.set(s, forKey: persistedLoginURLKey)
        }
        persistedAwaitingReturn = true
        UserDefaults.standard.synchronize()
    }

    static func loadPersistedCookies() -> [HTTPCookie] {
        guard let data = UserDefaults.standard.data(forKey: persistedCookiesKey),
              let rows = try? JSONDecoder().decode([PersistedCookie].self, from: data) else {
            return []
        }
        return rows.compactMap { row in
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: row.name,
                .value: row.value,
                .domain: row.domain.hasPrefix(".") ? row.domain : ".\(row.domain)",
                .path: row.path,
                .secure: "TRUE",
            ]
            return HTTPCookie(properties: props)
        }
    }

    static var persistedLoginURL: URL? {
        guard let s = UserDefaults.standard.string(forKey: persistedLoginURLKey),
              let u = URL(string: s) else { return nil }
        return u
    }

    static func clearPersistedLaunchSession() {
        persistedAwaitingReturn = false
        UserDefaults.standard.removeObject(forKey: persistedCookiesKey)
        UserDefaults.standard.removeObject(forKey: persistedLoginURLKey)
    }

    /// 原生路径：标记已拉起，供回壳判定（不经 WebView）
    static func markNativeLaunch(qrAuthorization: String) {
        let ticket = (qrAuthorization.removingPercentEncoding ?? qrAuthorization)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        launchedQrcode = ticket
        launchedAt = Date()
        awaitingReturn = true
        persistedAwaitingReturn = true
    }

    static func qrcodeTicket(fromWtlogin url: URL) -> String? {
        guard isWtloginScheme(url.scheme) else { return nil }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        // 任何 p= → 不要当票据
        if items.contains(where: { $0.name == "p" && !($0.value ?? "").isEmpty }) {
            return nil
        }
        guard let raw = items.first(where: { $0.name == "qrcode" })?.value else { return nil }
        let ticket = raw.removingPercentEncoding ?? raw
        return isAuthorizationQR(ticket) ? ticket : nil
    }

    static func rememberAuthorization(loginURL: URL?, cookies: [HTTPCookie]) {
        savedLoginURL = loginURL
        savedCookies = cookies
        // 必须在 open QQ 前落盘：进程常在切 QQ 后数秒内被杀
        persistLaunchSession(loginURL: loginURL, cookies: cookies)
    }

    @discardableResult
    static func openWithQrAuthorization(_ qr: String, force: Bool = false) -> Bool {
        let ticket = (qr.removingPercentEncoding ?? qr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAuthorizationQR(ticket), let launch = launchURL(qrAuthorization: ticket) else { return false }
        if launch.absoluteString.contains("?p=") || launch.absoluteString.contains("&p=") {
            return false
        }
        if !force, launchedQrcode == ticket { return true }
        launchedQrcode = ticket
        launchedAt = Date()
        pendingJumpURL = savedLoginURL
        awaitingReturn = true
        // 再刷一次：此时 savedCookies 应已有 qrsig
        persistLaunchSession(loginURL: savedLoginURL, cookies: savedCookies)
        var candidates = [launch]
        if var c = URLComponents(url: launch, resolvingAgainstBaseURL: false) {
            c.scheme = "wtloginmqq"
            if let u = c.url { candidates.append(u) }
        }
        // 延长后台存活，降低刚切 QQ 就被 jetsam
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "daledou-open-qq") {
            if bg != .invalid {
                UIApplication.shared.endBackgroundTask(bg)
                bg = .invalid
            }
        }
        for u in candidates where UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u, options: [:], completionHandler: { _ in
                if bg != .invalid {
                    UIApplication.shared.endBackgroundTask(bg)
                    bg = .invalid
                }
            })
            return true
        }
        UIApplication.shared.open(launch, options: [:], completionHandler: { _ in
            if bg != .invalid {
                UIApplication.shared.endBackgroundTask(bg)
                bg = .invalid
            }
        })
        return true
    }

    static func continueURL(fromCallback url: URL) -> URL? {
        let abs = url.absoluteString
        let prefixes = [
            "\(callbackScheme)://",
            "\(callbackSchemeAlt)://",
            "daledouapp://",
            "\(LoginURLs.tencentScheme)://",
        ]
        var rest: String?
        for p in prefixes {
            if abs.lowercased().hasPrefix(p.lowercased()) {
                rest = String(abs.dropFirst(p.count))
                break
            }
        }
        guard var body = rest else { return nil }
        if body.hasPrefix("(null)") { body = String(body.dropFirst(6)) }
        if body.hasPrefix("?") || body.isEmpty { return nil }
        if body.hasPrefix("http://") || body.hasPrefix("https://") {
            return URL(string: body)
        }
        if body.contains(".") {
            return URL(string: "https://" + body)
        }
        return nil
    }

    /// 冷启动从落盘 Cookie 恢复「仍在等 QQ」
    static func markRestoredAwaitingReturn(cookies: [HTTPCookie], loginURL: URL?) {
        savedCookies = cookies
        savedLoginURL = loginURL ?? savedLoginURL
        awaitingReturn = true
        launchedAt = Date()
        persistedAwaitingReturn = true
    }

    static func markReturned() {
        awaitingReturn = false
        clearPersistedLaunchSession()
    }

    static func clearLaunchStamp() {
        launchedQrcode = nil
        launchedAt = nil
    }

    static func clearPending() {
        pendingJumpURL = nil
        awaitingReturn = false
        clearPersistedLaunchSession()
        launchedQrcode = nil
        launchedAt = nil
        savedCookies = []
        savedLoginURL = nil
    }
}
