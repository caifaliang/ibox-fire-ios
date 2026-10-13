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
        window.__dldQrRequested = false;
        window.__dldQrStatus = 'waiting';
        window.__dldQrAuthorization = '';
        try { if (pt && pt.qrcode) { pt.qrcode.done = false; pt.qrcode.used = false; } } catch (e) {}
        return 'ok';
    })();
    """

    /// 藏起页内「一键登录」（点了会走 p= → 授权失败）；提示等自动跳 QQ
    static let jsOneKeyPageHint = """
    (() => {
        var b = document.getElementById('onekey');
        if (b) { b.style.display = 'none'; b.style.pointerEvents = 'none'; }
        if (document.getElementById('dld-onekey-hint')) return 'ok';
        var bar = document.createElement('div');
        bar.id = 'dld-onekey-hint';
        bar.setAttribute('style',
            'position:fixed;left:0;right:0;top:0;z-index:2147483647;padding:10px 12px;' +
            'background:#0b57d0;color:#fff;font:14px/1.4 -apple-system,sans-serif;text-align:center;');
        bar.textContent = '一键登录：即将跳转 QQ，请点「同意」；返回后会自动刷新';
        document.documentElement.appendChild(bar);
        document.documentElement.style.scrollPaddingTop = '48px';
        return 'ok';
    })();
    """

    // MARK: - Launch

    static func isAuthorizationQR(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 16 else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    static func launchURL(qrAuthorization: String) -> URL? {
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
        return URL(string: s) ?? (NSURL(string: s) as URL?)
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

    static func markReturned() { awaitingReturn = false }

    static func clearLaunchStamp() {
        launchedQrcode = nil
        launchedAt = nil
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
