import Foundation

/// 登录常量：一键 = 壳内 QQ 互联 authorize；扫码 = graph show。
enum LoginURLs {
    static let qqAppId = "102067279"
    /// QQ 互联 iOS 惯例：tencent + AppID
    static let tencentScheme = "tencent102067279"

    static let ledouEntry =
        "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?cmd=index&channel=0"

    /// 已在腾讯侧登记的回调（与安卓扫码/一键同源），用于落地写 Cookie
    static let oauthRedirect = "https://dld.qzapp.z.qq.com/index.php"

    /// 壳内一键：WebView 加载授权页，禁止唤起系统 QQ / Safari
    static var oneClickAuthorize: String {
        let redirect = oauthRedirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? oauthRedirect
        return "https://graph.qq.com/oauth2.0/authorize"
            + "?response_type=code"
            + "&client_id=\(qqAppId)"
            + "&redirect_uri=\(redirect)"
            + "&state=daledou_ios"
            + "&scope=all"
            + "&display=mobile"
    }

    /// 扫码（大乐斗）· 桌面 UA
    static let scanLedou =
        "https://graph.qq.com/oauth2.0/show?which=Login&display=pc&response_type=code"
            + "&client_id=\(qqAppId)"
            + "&redirect_uri=https%3A%2F%2Fdld.qzapp.z.qq.com%2Findex.php"
            + "&scope=all"

    static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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
    <p>请点右上角菜单<br/>「一键登陆」或「扫码登陆」</p>
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
        return s == "daledouapp" || s == tencentScheme.lowercased() || s.hasPrefix("tencent")
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
        return c.range(of: #"(?:^|[;\s])skey="#, options: .regularExpression) != nil
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
        guard let host = url?.host?.lowercased() else { return false }
        return host.contains("dld.qzapp.z.qq.com") || host.contains("fight.pet.qq.com")
    }

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
    case oneClick
    case scan
}
