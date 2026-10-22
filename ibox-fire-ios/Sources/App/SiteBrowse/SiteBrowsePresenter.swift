import SafariServices
import UIKit

/// 打开线上站。**刻意不用 WKWebView**：此前 SwiftUI cover / UIKit+WK 均在真机闪退。
/// SFSafariViewController 由系统托管 WebContent，宿主进程不建 WK，稳定性优先。
/// 注意：Safari 与 App 不共享 localStorage，需在页内自行登录网站会员。
enum SiteBrowsePresenter {
    static let siteURL = URL(string: "https://ai.iboxai.top/")!

    static func present(siteToken: String, userCacheJSON: String, iboxToken: String) {
        // 参数保留以兼容调用方；SFSafari 无法注入 localStorage
        _ = siteToken
        _ = userCacheJSON
        _ = iboxToken

        let open: () -> Void = {
            guard let host = topViewController() else {
                UIApplication.shared.open(siteURL, options: [:], completionHandler: nil)
                return
            }
            if host is SFSafariViewController { return }
            if host.presentedViewController is SFSafariViewController { return }

            let safari = SFSafariViewController(url: siteURL)
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
