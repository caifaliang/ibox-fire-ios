import Foundation

/// 对齐 Android `LoginHelper` 登录相关常量。
enum LoginURLs {
    /// 大乐斗手机端入口（已登录首页）
    static let ledouEntry =
        "https://dld.qzapp.z.qq.com/qpet/cgi-bin/phonepk?cmd=index&channel=0"

    /// 未登录：带「一键登录」的 QQ 互联页（壳内打开）
    static let xloginHome =
        "https://xui.ptlogin2.qq.com/cgi-bin/xlogin?appid=716027609" +
        "&pt_3rd_aid=102067279&daid=383&pt_skey_valid=0&style=35" +
        "&s_url=https%3A%2F%2Fconnect.qq.com&refer_cgi=authorize&which=" +
        "&sdkp=pcweb&sdkv=v1.0&time=1789995681&loginty=3" +
        "&h5sig=iQmvZ8eG78Q1LOs5DoTzZ2CIxslpZAZ8SJomWZgzgh4" +
        "&response_type=code&client_id=102067279" +
        "&redirect_uri=https%3A%2F%2Fdld.qzapp.z.qq.com%2Findex.php&scope=all"

    /// 密码/备选 ptlogin
    static let ledouPtlogin =
        "https://ui.ptlogin2.qq.com/cgi-bin/login?appid=614038002&style=9" +
        "&s_url=https%3A%2F%2Fdld.qzapp.z.qq.com%2Fqpet%2Fcgi-bin%2Fphonepk%3Fcmd%3Dindex%26channel%3D0"

    /// 扫码（大乐斗）
    static let scanLedou =
        "https://graph.qq.com/oauth2.0/show?which=Login&display=pc&response_type=code" +
        "&client_id=102067279" +
        "&redirect_uri=https%3A%2F%2Fdld.qzapp.z.qq.com%2Findex.php" +
        "&scope=all"

    /// 一键唤 QQ（schemacallback 回本 App）
    static let oneClickWt =
        "wtloginmqq://ptlogin/qlogin?p=https%3A%2F%2Fssl.ptlogin2.qq.com%2Fjump%3Fu1%3Dhttps%253A%252F%252Fconnect.qq.com%26pt_report%3D1%26pt_aid%3D716027609%26daid%3D383%26style%3D35%26pt_ua%3D0D2AA61C2D48B97B53FFF65BB61E76F4%26pt_browser%3DChrome%26pt_3rd_aid%3D102067279%26pt_openlogin_data%3Dappid%253D716027609%2526pt_3rd_aid%253D102067279%2526daid%253D383%2526pt_skey_valid%253D0%2526style%253D35%2526s_url%253Dhttps%25253A%25252F%25252Fconnect.qq.com%2526refer_cgi%253Dauthorize%2526which%253D%2526sdkp%253Dpcweb%2526sdkv%253Dv1.0%2526time%253D1789995681%2526loginty%253D3%2526h5sig%253DiQmvZ8eG78Q1LOs5DoTzZ2CIxslpZAZ8SJomWZgzgh4%2526response_type%253Dcode%2526client_id%253D102067279%2526redirect_uri%253Dhttps%25253A%25252F%25252Fdld.qzapp.z.qq.com%25252Findex.php%2526scope%253Dall%2526pt_flex%253D1%2526loginfrom%253D&schemacallback=daledouapp%3A%2F%2F"

    static func oneClickJumpUrl() -> String? {
        guard let comps = URLComponents(string: oneClickWt),
              let p = comps.queryItems?.first(where: { $0.name == "p" })?.value,
              p.hasPrefix("http") else { return nil }
        return p
    }

    /// 从 wtloginmqq / mqq 链接里抠出 https，便于留在 WKWebView。
    static func httpsPayload(fromQqScheme url: URL) -> URL? {
        let s = url.absoluteString
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let p = comps.queryItems?.first(where: { $0.name == "p" || $0.name == "url" })?.value,
           let u = URL(string: p), u.scheme?.hasPrefix("http") == true {
            return u
        }
        // 兜底：字符串里找第一个 https
        if let r = s.range(of: #"https?://[^\s&]+"#, options: .regularExpression) {
            var raw = String(s[r])
            raw = raw.removingPercentEncoding ?? raw
            if let u = URL(string: raw), u.scheme?.hasPrefix("http") == true { return u }
        }
        return nil
    }

    static func isQqWakeScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased() else { return false }
        return s.hasPrefix("wtlogin") || s.hasPrefix("mqq") || s == "tencent"
    }

    static func hasRealSkey(_ cookie: String?) -> Bool {
        guard let c = cookie, !c.isEmpty else { return false }
        return c.range(of: #"(?:^|[;\s])skey="#, options: .regularExpression) != nil
    }

    static func shellStartUrl(cookie: String?) -> String {
        hasRealSkey(cookie) ? ledouEntry : xloginHome
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

    static func isLoginHost(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host.contains("ptlogin2.qq.com")
            || host.contains("graph.qq.com")
            || host.contains("connect.qq.com")
            || host.contains("xui.ptlogin2")
            || host.contains("ui.ptlogin2")
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
        "https://qq.com",
    ]
}
