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
        return host.contains("xui.ptlogin2.qq.com") && u.path.contains("xlogin")
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

    /// 申请 QR 授权串。onload 勿立刻判 failed（CB 可能晚于 onload）。
    static let jsRequestQr = """
    (() => {
        if (location.protocol !== 'https:' || location.hostname !== 'xui.ptlogin2.qq.com' ||
            location.pathname !== '/cgi-bin/xlogin') return 'waiting';
        if (typeof pt === 'undefined' || !pt.hasInit || !pt.qrcode ||
            pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/' || typeof pt.qrcode.polling !== 'function') return 'waiting';
        if (window.__dldQrRequested) return window.__dldQrStatus === 'ready' ? 'ready' : 'requested';
        window.__dldQrRequested = true;
        window.__dldQrStatus = 'waiting';
        window.__dldQrAuthorization = '';
        window.ptui_qrcode_CB = response => {
            if (response && response.ec === 0 && typeof response.qrcode === 'string' && response.qrcode.length > 8) {
                window.__dldQrAuthorization = response.qrcode;
                window.__dldQrStatus = 'ready';
                try {
                    pt.qrcode.used = true;
                    pt.qrcode.done = false;
                    pt.qrcode.polling();
                } catch (e) {}
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
            // CB 偶发晚于 onload：再等 1.5s 才判失败
            setTimeout(() => {
                if (window.__dldQrStatus === 'waiting') window.__dldQrStatus = 'failed';
            }, 1500);
        };
        document.head.appendChild(request);
        return 'requested';
    })();
    """

    static let jsPollStatus = """
    (() => {
        if (location.protocol !== 'https:' || location.hostname !== 'xui.ptlogin2.qq.com' ||
            location.pathname !== '/cgi-bin/xlogin') {
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

    /// 仅 keep-alive polling，不要 qlogin_submit（submit 会弄死未确认的码）
    static let jsKeepPolling = """
    (() => {
        if (typeof pt === 'undefined' || !pt.qrcode || typeof pt.qrcode.polling !== 'function') return 'no';
        try { pt.qrcode.used = true; pt.qrcode.polling(); } catch (e) { return 'err'; }
        return 'ok';
    })();
    """

    /// QQ 已确认 / 回壳之后再 submit
    static let jsResumeAfterQQ = """
    (() => {
        if (location.protocol !== 'https:' || location.hostname !== 'xui.ptlogin2.qq.com' ||
            location.pathname !== '/cgi-bin/xlogin') return 'other-page';
        if (typeof pt === 'undefined' || pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/' ||
            !pt.qrcode || typeof pt.qrcode.polling !== 'function') return 'waiting';
        if (!document.cookie.split(';').some(value => value.trim().startsWith('qrsig='))) return 'missing-session';
        pt.qrcode.used = true;
        pt.qrcode.polling();
        try { if (window.$ && $.http && pt.qlogin_submit) $.http.loadScript(pt.qlogin_submit(pt.qrcode.CGI)); } catch (e) {}
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
        // 手工拼 query，避免 URLQueryItem 对已编码票据二次编码
        let cb = callbackURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callbackURLString
        let qrEnc: String
        if qrAuthorization.removingPercentEncoding != qrAuthorization {
            // 已是百分号编码，原样使用
            qrEnc = qrAuthorization.replacingOccurrences(of: "&", with: "%26")
        } else {
            qrEnc = qrAuthorization.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                ?? qrAuthorization
        }
        let s = "wtloginmqq3://ptlogin/qlogin?qrcode=\(qrEnc)&schemacallback=\(cb)"
        return URL(string: s)
    }

    static func buildLaunchURL(from raw: URL) -> URL? {
        guard let comps = URLComponents(url: raw, resolvingAgainstBaseURL: false),
              let qr = comps.queryItems?.first(where: { $0.name == "qrcode" })?.value,
              !qr.isEmpty else { return nil }
        return launchURL(qrAuthorization: qr)
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
        if body.hasPrefix("http://") || body.hasPrefix("https://") {
            return URL(string: body)
        }
        if body.hasPrefix("(null)") { body = String(body.dropFirst(6)) }
        if body.hasPrefix("?") || body.isEmpty {
            return pendingJumpURL ?? LoginURLs.oneClickJumpURL
        }
        if body.contains(".") {
            return URL(string: "https://" + body)
        }
        return pendingJumpURL ?? LoginURLs.oneClickJumpURL
    }

    @discardableResult
    static func openWithQrAuthorization(_ qr: String, force: Bool = false) -> Bool {
        guard !qr.isEmpty, let launch = launchURL(qrAuthorization: qr) else { return false }
        if !force, launchedQrcode == qr { return true }
        launchedQrcode = qr
        launchedAt = Date()
        pendingJumpURL = LoginURLs.oneClickJumpURL
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

    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        if isBrokenPageOneClick(raw) { return false }
        if let rebuilt = buildLaunchURL(from: raw) {
            let qr = URLComponents(url: rebuilt, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "qrcode" })?.value ?? ""
            return openWithQrAuthorization(qr.removingPercentEncoding ?? qr, force: true)
        }
        return false
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
    }
}
