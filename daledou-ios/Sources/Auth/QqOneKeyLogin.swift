import Foundation
import UIKit

/// QQ 一键登录（对齐竞品：ptqrshow 授权串 + wtloginmqq3?qrcode=）。
/// 注意：确认前不要调 `qlogin_submit`，否则 QQ 里会「二维码已过期」。
enum QqOneKeyLogin {
    static let callbackScheme = "daledoulogin"
    static let callbackURLString = "daledoulogin://"
    static let callbackSchemeAlt = "com.daledou.ioslogin"

    /// QR 约 60s 过期；到点前主动换新并重开 QQ
    static let qrRefreshSeconds: TimeInterval = 40

    private(set) static var pendingJumpURL: URL?
    private(set) static var awaitingReturn = false
    private(set) static var launchedQrcode: String?
    private(set) static var launchedAt: Date?
    /// 跳 QQ 前 Cookie 快照（qrsig 等）；回壳 restore 后再 qlogin_submit
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

    /// graph authorize / show：桌面 UA 下像扫码页，一键模式要遮罩并催向 QQ
    static func isGraphOAuthPage(_ url: URL?) -> Bool {
        guard let u = url, let host = u.host?.lowercased() else { return false }
        return host.contains("graph.qq.com") && u.path.lowercased().contains("oauth2.0")
    }

    static func isBrokenPageOneClick(_ url: URL) -> Bool {
        guard isWtloginScheme(url.scheme) else { return false }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        let hasP = items.contains { $0.name == "p" && !($0.value ?? "").isEmpty }
        let hasQr = items.contains { $0.name == "qrcode" && !($0.value ?? "").isEmpty }
        return hasP && !hasQr
    }

    static var qrLikelyExpired: Bool {
        guard let t = launchedAt else { return false }
        return Date().timeIntervalSince(t) >= qrRefreshSeconds
    }

    // MARK: - 注入脚本

    /// 从 graph/authorize 页抠出 iframe/a 的 xlogin 或 wtlogin（饭点同款入口落地后的真登录框）
    static let jsFindLoginTarget = """
    (() => {
        function pick(u) {
            if (!u || typeof u !== 'string') return '';
            var s = u.trim();
            if (!s) return '';
            if (/^wtlogin/i.test(s) || /^mqq/i.test(s)) return s;
            if (/ptlogin2\\.qq\\.com/i.test(s) && /xlogin/i.test(s)) return s;
            return '';
        }
        var ifr = document.querySelectorAll('iframe');
        for (var i = 0; i < ifr.length; i++) {
            var a = pick(ifr[i].src || '');
            if (a) return a;
        }
        var links = document.querySelectorAll('a[href]');
        for (var j = 0; j < links.length; j++) {
            var b = pick(links[j].href || '');
            if (b) return b;
        }
        return '';
    })();
    """

    /// 无遮罩：点「一键登录 / QQ手机版」
    static let jsClickOneKeyButton = """
    (() => {
        var nodes = document.querySelectorAll('a,button,div,span,li');
        for (var i = 0; i < nodes.length; i++) {
            var t = (nodes[i].innerText || nodes[i].textContent || '').replace(/\\s+/g, '');
            if (t.indexOf('一键登录') >= 0 || t.indexOf('QQ手机版') >= 0 || t.indexOf('手机QQ') >= 0) {
                try { nodes[i].click(); return 'clicked'; } catch (e) {}
            }
        }
        return 'none';
    })();
    """

    /// 申请 QR 授权串（严格：对齐饭点，需 pt 已初始化）
    static let jsRequestQr = """
    (() => {
        if (location.protocol !== 'https:' || !/\\.ptlogin2\\.qq\\.com$/i.test(location.hostname) ||
            location.pathname.indexOf('xlogin') < 0) return 'waiting';
        if (typeof pt === 'undefined' || !pt.hasInit || !pt.qrcode ||
            pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/' || typeof pt.qrcode.polling !== 'function') return 'waiting';
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
        try {
            pt.qrcode.used = true;
            pt.qrcode.done = false;
        } catch (e) {}
        const request = document.createElement('script');
        request.src = 'https://xui.ptlogin2.qq.com/ssl/ptqrshow?s=8&e=0&appid=716027609&type=1' +
            '&u1=https%3A%2F%2Fconnect.qq.com&daid=383&pt_3rd_aid=102067279&t=' + Math.random();
        request.onerror = () => { window.__dldQrStatus = 'failed'; try { request.remove(); } catch (e) {} };
        request.onload = () => {
            try { request.remove(); } catch (e) {}
            setTimeout(() => {
                if (window.__dldQrStatus === 'waiting') window.__dldQrStatus = 'failed';
            }, 1500);
        };
        document.head.appendChild(request);
        return 'requested';
    })();
    """

    /// 诊断 pt 是否可取票（对齐饭点门闩）
    static let jsPtDiag = """
    (() => {
        if (location.protocol !== 'https:' || !/\\.ptlogin2\\.qq\\.com$/i.test(location.hostname) ||
            location.pathname.indexOf('xlogin') < 0) {
            return 'page:' + location.hostname + location.pathname;
        }
        if (typeof pt === 'undefined') return 'no-pt';
        if (!pt.hasInit) return 'no-init';
        if (!pt.qrcode || typeof pt.qrcode.polling !== 'function') return 'no-qrcode';
        if (pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/') return 'bad-loginUrl';
        return 'ready';
    })();
    """

    static let jsPollStatus = """
    (() => {
        if (location.protocol !== 'https:' || !/\\.ptlogin2\\.qq\\.com$/i.test(location.hostname) ||
            location.pathname.indexOf('xlogin') < 0) {
            return JSON.stringify({status:'waiting',url:'',qrsig:false,page:location.hostname+location.pathname});
        }
        var hasSig = document.cookie.split(';').some(function(v){ return v.trim().indexOf('qrsig=')===0; });
        return JSON.stringify({
            status: window.__dldQrStatus || 'waiting',
            url: window.__dldQrAuthorization || '',
            qrsig: hasSig
        });
    })();
    """

    /// 页内提示：优先切号，勿去点会失败的网页授权
    static let jsOneKeyPageHint = """
    (() => {
        if (document.getElementById('dld-onekey-hint')) return 'ok';
        var bar = document.createElement('div');
        bar.id = 'dld-onekey-hint';
        bar.setAttribute('style',
            'position:fixed;left:0;right:0;top:0;z-index:2147483647;padding:10px 12px;' +
            'background:#0b57d0;color:#fff;font:14px/1.4 -apple-system,sans-serif;text-align:center;');
        bar.textContent = '一键登录：请先点本页「切换账号」选号；选好后等自动跳转 QQ 确认（不要点网页授权失败页）';
        document.documentElement.appendChild(bar);
        document.documentElement.style.scrollPaddingTop = '48px';
        return 'ok';
    })();
    """

    /// 仅 keep-alive polling，不要 qlogin_submit（确认前 submit 会弄死未确认的码）
    static let jsKeepPolling = """
    (() => {
        if (typeof pt === 'undefined' || !pt.qrcode || typeof pt.qrcode.polling !== 'function') return 'no';
        try { pt.qrcode.used = true; pt.qrcode.polling(); } catch (e) { return 'err'; }
        return 'ok';
    })();
    """

    /// QQ 已确认 / 回壳之后再 submit（对齐饭点：polling + qlogin_submit，勿跳 p= jump）
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
        window.__dldQrRequested = false;
        window.__dldQrStatus = 'waiting';
        window.__dldQrAuthorization = '';
        try { if (pt && pt.qrcode) { pt.qrcode.done = false; pt.qrcode.used = false; } } catch (e) {}
        return 'ok';
    })();
    """

    static func launchURL(qrAuthorization: String) -> URL? {
        // 饭点：qrcode= 原样拼接；schemacallback 编码。字母数字票据勿二次编码。
        let ticket = qrAuthorization.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticket.isEmpty else { return nil }
        let cb = callbackURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? "daledoulogin://"
        let qrEnc: String
        if ticket.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil {
            qrEnc = ticket
        } else if ticket.removingPercentEncoding != ticket {
            qrEnc = ticket.replacingOccurrences(of: "&", with: "%26")
        } else {
            qrEnc = ticket.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticket
        }
        let s = "wtloginmqq3://ptlogin/qlogin?qrcode=\(qrEnc)&schemacallback=\(cb)"
        if let u = URL(string: s) { return u }
        return NSURL(string: s) as URL?
    }

    static func buildLaunchURL(from raw: URL) -> URL? {
        guard let comps = URLComponents(url: raw, resolvingAgainstBaseURL: false),
              let qr = comps.queryItems?.first(where: { $0.name == "qrcode" })?.value,
              !qr.isEmpty else { return nil }
        return launchURL(qrAuthorization: qr)
    }

    /// schemacallback 体里若带 https 落地 URL 则返回；空/`?` 回调 **不要** 落到 Android `p=` jump（iOS 会「授权失败」）。
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

    /// 饭点 `isAuthorizationQR`：仅字母数字（拒 https/p= 垃圾串，否则 QQ 会进「APP网页申请」失败页）
    static func isAuthorizationQR(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 16 else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    /// 从 wtlogin URL 提取合法 qrcode；带 `p=` 或无票据 → nil（禁止打开）
    static func qrcodeTicket(fromWtlogin url: URL) -> String? {
        guard isWtloginScheme(url.scheme) else { return nil }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        if items.contains(where: { $0.name == "p" && !($0.value ?? "").isEmpty }) {
            return nil
        }
        guard let raw = items.first(where: { $0.name == "qrcode" })?.value else { return nil }
        let ticket = raw.removingPercentEncoding ?? raw
        return isAuthorizationQR(ticket) ? ticket : nil
    }

    /// 跳转前记住 xlogin URL + Cookie
    static func rememberAuthorization(loginURL: URL?, cookies: [HTTPCookie]) {
        savedLoginURL = loginURL
        savedCookies = cookies
    }

    @discardableResult
    static func openWithQrAuthorization(_ qr: String, force: Bool = false) -> Bool {
        let ticket = (qr.removingPercentEncoding ?? qr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAuthorizationQR(ticket), let launch = launchURL(qrAuthorization: ticket) else { return false }
        // 双保险：最终 URL 不得含 p=
        if launch.absoluteString.contains("?p=") || launch.absoluteString.contains("&p=") {
            return false
        }
        if !force, launchedQrcode == ticket { return true }
        launchedQrcode = ticket
        launchedAt = Date()
        pendingJumpURL = savedLoginURL
        awaitingReturn = true
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

    /// 仅当 URL 含合法 qrcode 时打开 QQ；`p=` / 网页授权一律拒绝（否则「登录授权失败」且无切号）
    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        guard let ticket = qrcodeTicket(fromWtlogin: raw) else { return false }
        return openWithQrAuthorization(ticket, force: true)
    }

    static func markReturned() { awaitingReturn = false }

    static func clearLaunchStamp() {
        launchedQrcode = nil
        launchedAt = nil
    }

    static func takePendingJump() -> URL? {
        let u = pendingJumpURL
        pendingJumpURL = nil
        return u
    }

    static func clearPending() {
        pendingJumpURL = nil
        awaitingReturn = false
        launchedQrcode = nil
        launchedAt = nil
        savedCookies = []
        savedLoginURL = nil
    }
}
