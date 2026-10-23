import SafariServices
import UIKit

/// 打开线上站（SFSafariViewController，避免 WKWebView 真机闪退）。
/// 登录态通过 URL hash `#iboxfire=<base64url(json)>` 交给前端在 Pinia 启动前写入 localStorage。
enum SiteBrowsePresenter {
    static let siteURL = URL(string: "https://ai.iboxai.top/")!

    static func present(siteToken: String, userCacheJSON: String, iboxToken: String) {
        let url = authURL(siteToken: siteToken, userCacheJSON: userCacheJSON, iboxToken: iboxToken)
        let open: () -> Void = {
            guard let host = topViewController() else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
            if host is SFSafariViewController { return }
            if host.presentedViewController is SFSafariViewController { return }

            let safari = SFSafariViewController(url: url)
            safari.dismissButtonStyle = .close
            safari.preferredControlTintColor = UIColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1)
            host.present(safari, animated: true)
        }

        if Thread.isMainThread {
            open()
        } else {
            DispatchQueue.main.async(execute: open)
        }
    }

    /// 组装带一次性登录态的 URL；无凭证时退回干净首页。
    static func authURL(siteToken: String, userCacheJSON: String, iboxToken: String) -> URL {
        var payload: [String: Any] = [:]
        let st = siteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let ib = iboxToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !st.isEmpty { payload["token"] = st }
        if !ib.isEmpty { payload["snipeToken"] = ib }
        if userCacheJSON != "null", !userCacheJSON.isEmpty,
           let data = userCacheJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           obj is [String: Any] {
            payload["userCache"] = obj
        }
        guard !payload.isEmpty,
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return siteURL
        }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard var comps = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) else {
            return siteURL
        }
        comps.fragment = "iboxfire=\(b64)"
        return comps.url ?? siteURL
    }

    static func userCacheJSON(from user: SiteUser?) -> String {
        guard let u = user else { return "null" }
        let obj: [String: Any] = [
            "token": u.token,
            "username": u.username,
            "is_vip": u.isVip,
            "is_admin": u.isAdmin,
            "is_year_vip": u.isYearVip,
            "is_month_vip": u.isMonthVip,
            "vip_expires_at": u.vipExpiresAt,
        ]
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController? = {
            if let base { return base }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? scenes.first?.windows.first
            return window?.rootViewController
        }()
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}
