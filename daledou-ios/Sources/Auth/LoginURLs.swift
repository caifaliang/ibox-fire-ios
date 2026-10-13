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

    /// 带「一键登录 / 切换账号」的 xlogin 页（对齐 Android `XLOGIN_HOME`；勿用 graph oauth）
    static let xloginHome =
        "https://xui.ptlogin2.qq.com/cgi-bin/xlogin?appid=716027609"
            + "&pt_3rd_aid=\(qqAppId)&daid=383&pt_skey_valid=0&style=35"
            + "&s_url=https%3A%2F%2Fconnect.qq.com&refer_cgi=authorize&which="
            + "&sdkp=pcweb&sdkv=v1.0&time=1789995681&loginty=3"
            + "&h5sig=iQmvZ8eG78Q1LOs5DoTzZ2CIxslpZAZ8SJomWZgzgh4"
            + "&response_type=code&client_id=\(qqAppId)"
            + "&redirect_uri=https%3A%2F%2Fdld.qzapp.z.qq.com%2Findex.php&scope=all"

    /// 壳内一键入口（= xlogin，保留旧名避免散落引用）
    static var oneClickAuthorize: String { xloginHome }

    /// 直接唤 QQ 的 wtlogin（h5sig/time 须与 xloginHome 成对；对齐 Android `ONE_CLICK_WT`）
    static let oneClickWtLaunch =
        "wtloginmqq3://ptlogin/qlogin?p=https%3A%2F%2Fssl.ptlogin2.qq.com%2Fjump%3Fu1%3Dhttps%253A%252F%252Fconnect.qq.com%26pt_report%3D1%26pt_aid%3D716027609%26daid%3D383%26style%3D35%26pt_ua%3D0D2AA61C2D48B97B53FFF65BB61E76F4%26pt_browser%3DChrome%26pt_3rd_aid%3D102067279%26pt_openlogin_data%3Dappid%253D716027609%2526pt_3rd_aid%253D102067279%2526daid%253D383%2526pt_skey_valid%253D0%2526style%253D35%2526s_url%253Dhttps%25253A%25252F%25252Fconnect.qq.com%2526refer_cgi%253Dauthorize%2526which%253D%2526sdkp%253Dpcweb%2526sdkv%253Dv1.0%2526time%253D1789995681%2526loginty%253D3%2526h5sig%253DiQmvZ8eG78Q1LOs5DoTzZ2CIxslpZAZ8SJomWZgzgh4%2526response_type%253Dcode%2526client_id%253D102067279%2526redirect_uri%253Dhttps%25253A%25252F%25252Fdld.qzapp.z.qq.com%25252Findex.php%2526scope%253Dall%2526pt_flex%253D1%2526loginfrom%253D&schemacallback=daledoulogin%3A%2F%2F"

    /// QQ 回壳后在 WebView 打开的 jump（Android `oneClickJumpUrl()`）
    static var oneClickJumpURL: URL? {
        guard let raw = URL(string: oneClickWtLaunch),
              let comps = URLComponents(url: raw, resolvingAgainstBaseURL: false),
              let p = comps.queryItems?.first(where: { $0.name == "p" })?.value?
                .removingPercentEncoding,
              p.hasPrefix("http") else { return nil }
        return URL(string: p)
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
        // 手机端常见 skey；部分链路只有 p_skey
        if c.range(of: #"(?:^|[;\s])skey="#, options: .regularExpression) != nil { return true }
        return c.range(of: #"(?:^|[;\s])p_skey="#, options: .regularExpression) != nil
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
    /// QQ App 一键（wtlogin + schemacallback 回壳）
    case oneKey
}
