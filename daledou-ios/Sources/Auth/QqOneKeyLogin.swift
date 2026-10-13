import Foundation
import UIKit

/// QQ 一键登录（对齐竞品 FandianAssistant `QqOneKeyLoginBridge`）。
/// iOS 正确路径：xlogin 页 → `ptqrshow` 取授权串 →
/// `wtloginmqq3://ptlogin/qlogin?qrcode=<授权串>&schemacallback=daledoulogin://`。
/// 页内「一键」产生的 `p=` 在 iOS QQ 上会变成「网页申请使用 / 授权失败」。
enum QqOneKeyLogin {
    static let callbackScheme = "daledoulogin"
    static let callbackURLString = "daledoulogin://"
    static let callbackSchemeAlt = "com.daledou.ioslogin"

    private(set) static var pendingJumpURL: URL?
    private(set) static var awaitingReturn = false
    /// 已对当前授权串唤过 QQ，避免重复弹
    private(set) static var launchedQrcode: String?

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

    /// 页内 `p=` 的 wtlogin（安卓一键）—— iOS 上不要打开，会授权失败。
    static func isBrokenPageOneClick(_ url: URL) -> Bool {
        guard isWtloginScheme(url.scheme) else { return false }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        let hasP = items.contains { $0.name == "p" && !($0.value ?? "").isEmpty }
        let hasQr = items.contains { $0.name == "qrcode" && !($0.value ?? "").isEmpty }
        return hasP && !hasQr
    }

    // MARK: - 竞品注入脚本

    /// 向 xlogin 申请 QR 授权串（ptui_qrcode_CB）
    static let jsRequestQr = """
    (() => {
        if (location.protocol !== 'https:' || location.hostname !== 'xui.ptlogin2.qq.com' ||
            location.pathname !== '/cgi-bin/xlogin') return 'waiting';
        if (typeof pt === 'undefined' || !pt.hasInit || !pt.qrcode ||
            pt.loginUrl !== 'https://ssl.ptlogin2.qq.com/' || typeof pt.qrcode.polling !== 'function') return 'waiting';
        if (window.__dldQrRequested) return 'requested';
        window.__dldQrRequested = true;
        window.__dldQrStatus = 'waiting';
        window.ptui_qrcode_CB = response => {
            if (response && response.ec === 0 && typeof response.qrcode === 'string') {
                window.__dldQrAuthorization = response.qrcode;
                window.__dldQrStatus = 'ready';
                pt.qrcode.used = true;
                pt.qrcode.polling();
            } else {
                window.__dldQrStatus = 'failed';
            }
        };
        pt.qrcode.used = true;
        pt.qrcode.done = false;
        const request = document.createElement('script');
        request.src = 'https://xui.ptlogin2.qq.com/ssl/ptqrshow?s=8&e=0&appid=716027609&type=1' +
            '&u1=https%3A%2F%2Fconnect.qq.com&daid=383&pt_3rd_aid=102067279&t=' + Math.random();
        request.onerror = () => { window.__dldQrStatus = 'failed'; request.remove(); };
        request.onload = () => {
            if (window.__dldQrStatus !== 'ready') window.__dldQrStatus = 'failed';
            request.remove();
        };
        document.head.appendChild(request);
        return 'requested';
    })();
    """

    /// 轮询授权串状态 → JSON `{status,url}`
    static let jsPollStatus = """
    (() => {
        if (location.protocol !== 'https:' || location.hostname !== 'xui.ptlogin2.qq.com' ||
            location.pathname !== '/cgi-bin/xlogin') return JSON.stringify({status:'waiting',url:''});
        return JSON.stringify({
            status: window.__dldQrStatus || 'waiting',
            url: window.__dldQrAuthorization || ''
        });
    })();
    """

    /// QQ 确认后：若已有 qrsig，继续 polling + submit
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

    /// 重置页内 QR 状态以便重试
    static let jsResetQr = """
    (() => {
        window.__dldQrRequested = false;
        window.__dldQrStatus = 'waiting';
        window.__dldQrAuthorization = '';
        return 'ok';
    })();
    """

    static func launchURL(qrAuthorization: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "wtloginmqq3"
        comps.host = "ptlogin"
        comps.path = "/qlogin"
        comps.queryItems = [
            URLQueryItem(name: "qrcode", value: qrAuthorization),
            URLQueryItem(name: "schemacallback", value: callbackURLString),
        ]
        return comps.url
    }

    /// 仅用于「已是 qrcode=授权串」的链接：补 schemacallback，不改 qrcode。
    static func buildLaunchURL(from raw: URL) -> URL? {
        guard let comps = URLComponents(url: raw, resolvingAgainstBaseURL: false),
              let qr = comps.queryItems?.first(where: { $0.name == "qrcode" })?.value,
              !qr.isEmpty else { return nil }
        return launchURL(qrAuthorization: qr.removingPercentEncoding ?? qr)
    }

    static func extractContinueURL(from wtlogin: URL) -> URL? {
        guard let comps = URLComponents(url: wtlogin, resolvingAgainstBaseURL: false) else { return nil }
        for name in ["p", "qrcode", "url"] {
            guard let raw = comps.queryItems?.first(where: { $0.name == name })?.value else { continue }
            let decoded = raw.removingPercentEncoding ?? raw
            if decoded.hasPrefix("http"), let u = URL(string: decoded) { return u }
        }
        return nil
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
            return mergeClientParams(into: pendingJumpURL ?? LoginURLs.oneClickJumpURL, from: url)
        }
        if body.contains(".") {
            return URL(string: "https://" + body)
        }
        return mergeClientParams(into: pendingJumpURL ?? LoginURLs.oneClickJumpURL, from: url)
    }

    private static func mergeClientParams(into base: URL?, from callback: URL) -> URL? {
        guard var comps = base.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return base
        }
        var items = comps.queryItems ?? []
        let cbItems = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["clientuin", "clientkey", "keyindex"] {
            if let v = cbItems.first(where: { $0.name == name })?.value, !v.isEmpty {
                items.removeAll { $0.name == name }
                items.append(URLQueryItem(name: name, value: v))
            }
        }
        comps.queryItems = items
        return comps.url ?? base
    }

    @discardableResult
    static func openWithQrAuthorization(_ qr: String) -> Bool {
        guard !qr.isEmpty, let launch = launchURL(qrAuthorization: qr) else { return false }
        if launchedQrcode == qr { return true }
        launchedQrcode = qr
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

    /// 兼容旧调用：仅当 URL 自带 qrcode 时打开；`p=` 一律拒绝。
    @discardableResult
    static func openInQQ(_ raw: URL) -> Bool {
        if isBrokenPageOneClick(raw) { return false }
        if let rebuilt = buildLaunchURL(from: raw) {
            let qr = URLComponents(url: rebuilt, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "qrcode" })?.value ?? ""
            return openWithQrAuthorization(qr.removingPercentEncoding ?? qr)
        }
        return false
    }

    static func markReturned() { awaitingReturn = false }

    static func takePendingJump() -> URL? {
        let u = pendingJumpURL
        pendingJumpURL = nil
        return u
    }

    static func clearPending() {
        pendingJumpURL = nil
        awaitingReturn = false
        launchedQrcode = nil
    }
}
