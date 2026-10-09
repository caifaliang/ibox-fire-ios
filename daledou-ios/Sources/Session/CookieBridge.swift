import Foundation
import WebKit

/// WKWebView Cookie ↔ SessionStore
enum CookieBridge {
    static func readCookieHeader(from webView: WKWebView) async -> String {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        // 优先大乐斗相关域
        let relevant = cookies.filter { c in
            let d = c.domain.lowercased()
            return d.contains("qq.com") || d.contains("gtimg.cn")
        }
        var map: [String: String] = [:]
        for c in relevant {
            // 同名以后写的为准（常见 skey 刷新）
            map[c.name] = c.value
        }
        return map
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }

    static func inject(cookieHeader: String, into webView: WKWebView) async {
        guard !cookieHeader.isEmpty else { return }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let pairs = cookieHeader
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("=") }
        for domainURL in LoginURLs.cookieDomains {
            guard let host = URL(string: domainURL)?.host else { continue }
            for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                var props: [HTTPCookiePropertyKey: Any] = [
                    .name: parts[0],
                    .value: parts[1],
                    .domain: host.hasPrefix(".") ? host : ".\(host)",
                    .path: "/",
                    .secure: "TRUE",
                ]
                // 根域 qq.com
                if host.hasSuffix("qq.com") {
                    props[.domain] = ".qq.com"
                }
                if let cookie = HTTPCookie(properties: props) {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        store.setCookie(cookie) { cont.resume() }
                    }
                }
            }
        }
    }

    static func clearAll(from webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        for c in cookies {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.delete(c) { cont.resume() }
            }
        }
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: types,
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) { cont.resume() }
        }
    }
}
