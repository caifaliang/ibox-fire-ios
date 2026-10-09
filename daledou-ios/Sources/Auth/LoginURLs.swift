import Foundation

/// 对齐 Android `LoginHelper`（仅保留一键 / 扫码相关）。
enum LoginURLs {
    static let ledouEntry =
        "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?cmd=index&channel=0"

    /// 扫码（大乐斗）· 需桌面 UA
    static let scanLedou =
        "https://graph.qq.com/oauth2.0/show?which=Login&display=pc&response_type=code" +
        "&client_id=102067279" +
        "&redirect_uri=https%3A%2F%2Fdld.qzapp.z.qq.com%2Findex.php" +
        "&scope=all"

    /// 一键唤 QQ（schemacallback 回本 App）
    static let oneClickWt =
        "wtloginmqq://ptlogin/qlogin?p=https%3A%2F%2Fssl.ptlogin2.qq.com%2Fjump%3Fu1%3Dhttps%253A%252F%252Fconnect.qq.com%26pt_report%3D1%26pt_aid%3D716027609%26daid%3D383%26style%3D35%26pt_ua%3D0D2AA61C2D48B97B53FFF65BB61E76F4%26pt_browser%3DChrome%26pt_3rd_aid%3D102067279%26pt_openlogin_data%3Dappid%253D716027609%2526pt_3rd_aid%253D102067279%2526daid%253D383%2526pt_skey_valid%253D0%2526style%253D35%2526s_url%253Dhttps%25253A%25252F%25252Fconnect.qq.com%2526refer_cgi%253Dauthorize%2526which%253D%2526sdkp%253Dpcweb%2526sdkv%253Dv1.0%2526time%253D1789995681%2526loginty%253D3%2526h5sig%253DiQmvZ8eG78Q1LOs5DoTzZ2CIxslpZAZ8SJomWZgzgh4%2526response_type%253Dcode%2526client_id%253D102067279%2526redirect_uri%253Dhttps%25253A%25252F%25252Fdld.qzapp.z.qq.com%25252Findex.php%2526scope%253Dall%2526pt_flex%253D1%2526loginfrom%253D&schemacallback=daledouapp%3A%2F%2F"

    /// 扫码用桌面 UA（对齐 Android LoginHelper.DESKTOP_UA）
    static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// 未登录占位（避免误进 xlogin/密码页）
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
    <p>请点右上角菜单<br/>使用「一键登陆」或「扫码登陆」</p>
    </div></body></html>
    """

    static func oneClickJumpUrl() -> String? {
        guard let comps = URLComponents(string: oneClickWt),
              let p = comps.queryItems?.first(where: { $0.name == "p" })?.value,
              p.hasPrefix("http") else { return nil }
        return p
    }

    /// 扫码确认后 xlogin(pt_skey_valid=1) → jump（对齐 Android continueAuthorizeUrl）
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
            .init(name: "pt_3rd_aid", value: "102067279"),
            .init(name: "pt_openlogin_data", value: query),
        ]
        return jump.url?.absoluteString
    }

    static func isQqWakeScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased() else { return false }
        return s.hasPrefix("wtlogin") || s.hasPrefix("mqq") || s == "tencent"
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

    static func isConnectMarketing(_ url: URL?) -> Bool {
        guard let u = url else { return false }
        let host = (u.host ?? "").lowercased()
        let path = u.path
        // 互联官网首页（无授权参数）——一键失败时常见落点
        return (host == "connect.qq.com" || host == "www.connect.qq.com")
            && !path.contains("oauth")
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
