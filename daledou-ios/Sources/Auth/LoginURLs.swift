import Foundation

/// 登录常量：一键 = 饭点 QQ_ONE_KEY（phonepk→style=35→wtlogin p=）；扫码 = graph show。
enum LoginURLs {
    static let qqAppId = "102067279"
    /// QQ 互联 iOS 惯例：tencent + AppID
    static let tencentScheme = "tencent102067279"

    /// 饭点 QQ_ONE_KEY 入口（ordinal==0 字面量）
    static let ledouEntry =
        "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?cmd=index&channel=0"

    /// 已在腾讯侧登记的回调（与安卓扫码/一键同源），用于落地写 Cookie
    static let oauthRedirect = "https://dld.qzapp.z.qq.com/index.php"

    /// 备用：直接 authorize（正常一键不走这条，入口是 phonepk）
    static let oneKeyLogin =
        "https://graph.qq.com/oauth2.0/authorize?response_type=code"
            + "&client_id=\(qqAppId)"
            + "&redirect_uri=https%3A%2F%2Fdld.qzapp.z.qq.com%2Findex.php"
            + "&scope=all"

    static var oneClickAuthorize: String { oneKeyLogin }
    static var xloginHome: String { oneKeyLogin }

    /// 手机 UA 拉 authorize → HTML 里带 **新鲜 h5sig** 的 style=35 xlogin（饭点/安卓一键同源）。
    /// 禁止用桌面 UA：会 302 到 show/style=33 扫码框，页内已无 `pt.hasInit`，会永久 no-init。
    static func resolveLiveXloginURL() async -> URL? {
        if let mobile = await resolveMobileAuthorizeXlogin() {
            return mobile
        }
        // 兜底：桌面 show 拼装（仅扫码框，无「一键登录」按钮）
        guard let start = URL(string: oneKeyLogin) else { return nil }
        var req = URLRequest(url: start)
        req.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let final = resp.url else { return nil }
            let host = (final.host ?? "").lowercased()
            let path = final.path.lowercased()
            if host.contains("ptlogin2.qq.com"), path.contains("xlogin") {
                return final
            }
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            if let parsed = xloginURL(fromShowHTML: html, pageURL: final) {
                return parsed
            }
            return assembleShowXloginURL(clientId: clientId(from: final) ?? qqAppId)
        } catch {
            return assembleShowXloginURL(clientId: qqAppId)
        }
    }

    /// iPhone UA：authorize 不 HTTP 跳转，而是 meta/JS 指向带 time+h5sig 的 style=35 xlogin
    private static func resolveMobileAuthorizeXlogin() async -> URL? {
        guard let start = URL(string: oneKeyLogin) else { return nil }
        var req = URLRequest(url: start)
        req.setValue(iphoneUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let final = resp.url,
               (final.host ?? "").lowercased().contains("ptlogin2.qq.com"),
               final.path.lowercased().contains("xlogin"),
               final.absoluteString.contains("style=35") {
                return final
            }
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            return extractXloginURL(fromAuthorizeHTML: html)
        } catch {
            return nil
        }
    }

    /// 从 authorize 中间页抠 xlogin（支持 `\x3A`、`&#61;`）
    static func extractXloginURL(fromAuthorizeHTML html: String) -> URL? {
        var text = html
            .replacingOccurrences(of: "&#61;", with: "=")
            .replacingOccurrences(of: "&amp;", with: "&")
        text = decodeJSHexEscapes(text)
        let pat = #"https://xui\.ptlogin2\.qq\.com/cgi-bin/xlogin\?[^\s\"'<>]+"#
        guard let r = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { return nil }
        let ns = NSRange(text.startIndex..., in: text)
        let matches = r.matches(in: text, range: ns)
        // 优先 style=35 + h5sig（一键）；否则任意 xlogin
        var fallback: URL?
        for m in matches {
            guard let range = Range(m.range, in: text) else { continue }
            var raw = String(text[range])
            if raw.hasSuffix("\\") { raw = String(raw.dropLast()) }
            guard let u = URL(string: raw), u.path.lowercased().contains("xlogin") else { continue }
            let s = u.absoluteString
            if s.contains("style=35"), s.contains("h5sig") {
                return u
            }
            if fallback == nil { fallback = u }
        }
        return fallback
    }

    private static func decodeJSHexEscapes(_ s: String) -> String {
        guard let r = try? NSRegularExpression(pattern: #"\\x([0-9A-Fa-f]{2})"#) else { return s }
        let ns = NSMutableString(string: s)
        let matches = r.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            guard m.numberOfRanges > 1 else { continue }
            let hex = ns.substring(with: m.range(at: 1))
            guard let val = UInt32(hex, radix: 16), let scalar = UnicodeScalar(val) else { continue }
            ns.replaceCharacters(in: m.range, with: String(Character(scalar)))
        }
        return ns as String
    }

    /// graph oauth2.0/show 内 `Q.ptlogin2()` 等价拼装（无写死 h5sig）
    static func assembleShowXloginURL(clientId: String) -> URL? {
        let jump = "https://graph.qq.com/oauth2.0/login_jump"
        let feedback =
            "https://support.qq.com/products/77942?customInfo=.appid\(clientId)"
        var c = URLComponents()
        c.scheme = "https"
        c.host = "xui.ptlogin2.qq.com"
        c.path = "/cgi-bin/xlogin"
        c.queryItems = [
            .init(name: "appid", value: "716027609"),
            .init(name: "daid", value: "383"),
            .init(name: "style", value: "33"),
            .init(name: "login_text", value: "登录"),
            .init(name: "hide_title_bar", value: "1"),
            .init(name: "hide_border", value: "1"),
            .init(name: "target", value: "self"),
            .init(name: "s_url", value: jump),
            .init(name: "pt_3rd_aid", value: clientId),
            .init(name: "pt_feedback_link", value: feedback),
            .init(name: "theme", value: "2"),
            .init(name: "verify_theme", value: ""),
        ]
        return c.url
    }

    /// 从 show HTML 抠完整 xlogin；失败则按页内 client_id 拼装
    private static func xloginURL(fromShowHTML html: String, pageURL: URL) -> URL? {
        let cid = clientId(from: pageURL) ?? qqAppId
        // 完整绝对地址（少见，但有则直接用）
        let fullPat = #"https://xui\.ptlogin2\.qq\.com/cgi-bin/xlogin\?[^\s"'<>]+"#
        if let r = try? NSRegularExpression(pattern: fullPat, options: .caseInsensitive),
           let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(m.range, in: html) {
            var raw = String(html[range])
            // 页内常截断到 s_url=，需补全
            if raw.hasSuffix("s_url=") || raw.hasSuffix("s_url=''") || !raw.contains("pt_3rd_aid") {
                return assembleShowXloginURL(clientId: cid)
            }
            if let u = URL(string: raw), u.path.lowercased().contains("xlogin") {
                return u
            }
        }
        // 识别 show 页特征脚本后再拼装
        if html.contains("ptlogin_iframe"), html.contains("/cgi-bin/xlogin") {
            return assembleShowXloginURL(clientId: cid)
        }
        if (pageURL.host ?? "").lowercased().contains("graph.qq.com"),
           pageURL.path.lowercased().contains("show") {
            return assembleShowXloginURL(clientId: cid)
        }
        return nil
    }

    private static func clientId(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "client_id" })?
            .value
    }

    /// 扫码（大乐斗）· 桌面 UA
    static let scanLedou =
        "https://graph.qq.com/oauth2.0/show?which=Login&display=pc&response_type=code"
            + "&client_id=\(qqAppId)"
            + "&redirect_uri=https%3A%2F%2Fdld.qzapp.z.qq.com%2Findex.php"
            + "&scope=all"

    /// 饭点二进制字面量（勿加减字段）
    static let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36"

    /// 一键登录解析/壳内加载用：手机 UA 才会下发带新鲜 h5sig 的 style=35
    static let iphoneUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static let waitingHTML = """
    <!doctype html><html><head><meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>大乐斗</title>
    <style>
      body{font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;
      min-height:100vh;margin:0;background:#f5f5f7;color:#222}
      .box{text-align:center;padding:24px}
      h1{font-size:22px;margin:0 0 8px}
      p{color:#666;font-size:14px;line-height:1.5}
    </style></head><body><div class="box">
    <h1>大乐斗</h1>
    <p>请点右上角菜单<br/>「一键登录」/「扫码登陆」/「Cookie」</p>
    </div></body></html>
    """

    /// 扫码确认后 xlogin(pt_skey_valid=1) → jump
    static func continueAuthorizeUrl(xloginUrl: String) -> String? {
        guard xloginUrl.contains("xlogin"), xloginUrl.contains("pt_skey_valid=1") else { return nil }
        guard let comps = URLComponents(string: xloginUrl), let query = comps.query else { return nil }
        var jump = URLComponents(string: "https://ssl.ptlogin2.qq.com/jump")!
        jump.queryItems = [
            .init(name: "u1", value: "https://connect.qq.com"),
            .init(name: "pt_report", value: "1"),
            .init(name: "pt_aid", value: "716027609"),
            .init(name: "daid", value: "383"),
            .init(name: "style", value: "35"),
            .init(name: "pt_browser", value: "Chrome"),
            .init(name: "pt_3rd_aid", value: qqAppId),
            .init(name: "pt_openlogin_data", value: query),
        ]
        return jump.url?.absoluteString
    }

    static func isCallbackScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased() else { return false }
        return s == "daledouapp"
            || s == "daledoulogin"
            || s == "com.daledou.ioslogin"
            || s == tencentScheme.lowercased()
            || s.hasPrefix("tencent")
    }

    /// 从自定义 Scheme / https 回调里抠 code
    static func oauthCode(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return code
        }
        // implicit: #access_token=... 对大乐斗游戏 Cookie 帮助有限，仍记录
        if let frag = url.fragment, frag.contains("access_token=") {
            return nil
        }
        return nil
    }

    /// 拿到 code 后继续走已登记的 redirect，让大乐斗域写 Cookie
    static func finishWithCode(_ code: String) -> URL? {
        var c = URLComponents(string: oauthRedirect)!
        c.queryItems = [
            .init(name: "code", value: code),
            .init(name: "state", value: "daledou_ios"),
        ]
        return c.url
    }

    static func hasRealSkey(_ cookie: String?) -> Bool {
        guard let c = cookie, !c.isEmpty else { return false }
        // 对齐安卓：有 skey=；同时接受非空 p_skey（排除占位 @）
        if let r = try? NSRegularExpression(
            pattern: #"(?:^|[;\s])skey=([^\s;]+)"#,
            options: .caseInsensitive
        ) {
            for m in r.matches(in: c, range: NSRange(c.startIndex..., in: c)) where m.numberOfRanges > 1 {
                if let range = Range(m.range(at: 1), in: c) {
                    let v = String(c[range])
                    if !v.isEmpty, v != "@" { return true }
                }
            }
        }
        if let r = try? NSRegularExpression(
            pattern: #"(?:^|[;\s])p_skey=([^\s;]+)"#,
            options: .caseInsensitive
        ) {
            for m in r.matches(in: c, range: NSRange(c.startIndex..., in: c)) where m.numberOfRanges > 1 {
                if let range = Range(m.range(at: 1), in: c) {
                    let v = String(c[range])
                    if !v.isEmpty, v != "@" { return true }
                }
            }
        }
        return false
    }

    static func extractQq(_ cookie: String) -> String? {
        let patterns = [
            #"(?:^|[;&?\s])(?:p_)?uin=o?0*(\d{5,12})"#,
            #"(?:^|[;&?\s])luin=o?0*(\d{5,12})"#,
            #"(?:^|[;&?\s])pt2gguin=o?0*(\d{5,12})"#,
            #"(?:^|[;&?\s])newuin=o?0*(\d{5,12})"#,
        ]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = r.firstMatch(in: cookie, range: NSRange(cookie.startIndex..., in: cookie)),
               m.numberOfRanges > 1,
               let range = Range(m.range(at: 1), in: cookie) {
                return String(cookie[range])
            }
        }
        return nil
    }

    static func isGameHost(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(), !host.isEmpty else { return false }
        // about:blank / 本地等待页不算游戏域
        if url.scheme?.lowercased() == "about" { return false }
        return host.contains("dld.qzapp.z.qq.com") || host.contains("fight.pet.qq.com")
    }

    /// 真正进了手机端壳（phonepk），不是 index.php 回调页
    static func isInGameShell(_ url: URL?) -> Bool {
        guard let u = url, isGameHost(u) else { return false }
        let s = u.absoluteString.lowercased()
        return s.contains("phonepk") || s.contains("cgi-bin/phonepk")
    }

    /// 本体「查看乐斗过程」phonepk viewfight（非群侠 knightfight）
    static func isViewFightUrl(_ urlString: String?) -> Bool {
        guard let raw = urlString?.lowercased(), !raw.isEmpty else { return false }
        return raw.contains("cmd=viewfight") && !raw.contains("knightfight")
    }

    /// QQ「亿万用户已选择」一键登录页（扫码后常误停在这里）
    static let qqLoginProbeJS =
        "(function(){var t=(document.body&&document.body.innerText)||'';" +
        "if(t.indexOf('亿万用户已选择')>=0)return 'qq';" +
        "if(t.indexOf('【大乐斗】')>=0)return 'game';" +
        "if(t.length>80)return 'game';" +
        "return 'other';})()"

    static func isOauthLanding(_ url: URL?) -> Bool {
        guard let u = url, let host = u.host?.lowercased() else { return false }
        guard host.contains("dld.qzapp.z.qq.com") else { return false }
        let q = u.query ?? ""
        return u.path.contains("index.php") || q.contains("code=")
    }

    static func isConnectMarketing(_ url: URL?) -> Bool {
        guard let u = url else { return false }
        let host = (u.host ?? "").lowercased()
        return (host == "connect.qq.com" || host == "www.connect.qq.com")
            && !u.path.contains("oauth")
            && !(u.query?.contains("code=") == true)
    }

    static let cookieDomains = [
        "https://dld.qzapp.z.qq.com",
        "https://qzapp.z.qq.com",
        "https://fight.pet.qq.com",
        "https://qqgame.qq.com",
        "https://minigame.qq.com",
        "https://ssl.ptlogin2.qq.com",
        "https://ui.ptlogin2.qq.com",
        "https://xui.ptlogin2.qq.com",
        "https://ptlogin2.qq.com",
        "https://graph.qq.com",
        "https://qq.com",
    ]
}

enum LoginMode: String {
    case idle
    case scan
    /// QQ App 一键（饭点：phonepk → wtlogin p= → https 回跳）
    case oneKey
}
