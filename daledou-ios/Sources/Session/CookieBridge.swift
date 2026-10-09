import Foundation
import WebKit

/// WKWebView Cookie ↔ SessionStore
enum CookieBridge {
    static func readCookieHeader(from webView: WKWebView) async -> String {
        // 与 WebView 同一 dataStore；再兜底 default（防止配置不一致）
        let stores = [
            webView.configuration.websiteDataStore.httpCookieStore,
            WKWebsiteDataStore.default().httpCookieStore,
        ]
        var map: [String: String] = [:]
        for store in stores {
            let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
                store.getAllCookies { cont.resume(returning: $0) }
            }
            for c in cookies {
                let d = c.domain.lowercased()
                guard d.contains("qq.com") || d.contains("gtimg.cn") else { continue }
                let name = c.name
                let val = c.value
                if val.isEmpty { continue }
                // skey / p_skey：非空覆盖空值
                if let old = map[name], !old.isEmpty, name.lowercased().contains("skey") {
                    continue
                }
                map[name] = val
            }
        }
        return map
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }

    /// 轮询直到有 skey 或超时（扫码落地后 Set-Cookie 有时略晚）
    static func waitForSkey(from webView: WKWebView, attempts: Int = 8, gapMs: UInt64 = 400) async -> String {
        for i in 0..<attempts {
            let header = await readCookieHeader(from: webView)
            if LoginURLs.hasRealSkey(header) { return header }
            if i + 1 < attempts {
                try? await Task.sleep(nanoseconds: gapMs * 1_000_000)
            }
        }
        return await readCookieHeader(from: webView)
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
