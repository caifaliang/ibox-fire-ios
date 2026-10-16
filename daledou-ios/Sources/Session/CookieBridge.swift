import Foundation
import WebKit

/// WKWebView Cookie ↔ SessionStore
enum CookieBridge {
    /// 对齐安卓：按游戏/登录相关 host 汇总 Cookie（含 document.cookie 兜底）
    static func readCookieHeader(from webView: WKWebView) async -> String {
        var map: [String: String] = [:]

        let stores = [
            webView.configuration.websiteDataStore.httpCookieStore,
            WKWebsiteDataStore.default().httpCookieStore,
        ]
        for store in stores {
            let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
                store.getAllCookies { cont.resume(returning: $0) }
            }
            for c in cookies {
                let d = c.domain.lowercased()
                guard d.contains("qq.com") || d.contains("gtimg.cn") else { continue }
                merge(&map, name: c.name, value: c.value)
            }
        }

        // 非 HttpOnly 兜底
        if let jsCookie = await documentCookie(from: webView) {
            for pair in jsCookie.split(separator: ";") {
                let p = pair.trimmingCharacters(in: .whitespaces)
                guard let eq = p.firstIndex(of: "=") else { continue }
                let name = String(p[..<eq])
                let val = String(p[p.index(after: eq)...])
                merge(&map, name: name, value: val)
            }
        }

        return map
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }

    /// 脱敏：仅 name + domain
    static func cookieNameDomainLog(from webView: WKWebView) async -> String {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        let parts = cookies
            .filter {
                let d = $0.domain.lowercased()
                return d.contains("qq.com") || d.contains("gtimg.cn")
            }
            .map { "\($0.name)@\($0.domain)" }
            .sorted()
        return parts.joined(separator: ",")
    }

    private static func merge(_ map: inout [String: String], name: String, value: String) {
        let val = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !val.isEmpty else { return }
        let key = name
        let lower = key.lowercased()
        if lower.contains("skey") {
            // 非空、非 @ 的新值覆盖旧占位
            if let old = map[key], old != "@", !old.isEmpty, (val == "@" || val.isEmpty) {
                return
            }
            if val == "@" {
                if map[key] == nil { map[key] = val }
                return
            }
            map[key] = val
            return
        }
        if map[key] == nil || map[key]?.isEmpty == true {
            map[key] = val
        }
    }

    private static func documentCookie(from webView: WKWebView) async -> String? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript("document.cookie || ''") { result, _ in
                cont.resume(returning: result as? String)
            }
        }
    }

    /// 轮询直到有可用会话（skey 或 openId+accessToken）或超时
    static func waitForSkey(from webView: WKWebView, attempts: Int = 8, gapMs: UInt64 = 400) async -> String {
        for i in 0..<attempts {
            let header = await readCookieHeader(from: webView)
            if LoginURLs.hasGameSession(header) { return header }
            if i + 1 < attempts {
                try? await Task.sleep(nanoseconds: gapMs * 1_000_000)
            }
        }
        return await readCookieHeader(from: webView)
    }

    /// 道聚城：轮询直到 Cookie 含 access_token + openid
    static func waitForDaojuOAuth(
        from webView: WKWebView, attempts: Int = 6, gapMs: UInt64 = 800
    ) async -> String {
        for i in 0..<attempts {
            let header = await readCookieHeader(from: webView)
            if DjcAuth.parseOAuth(header) != nil { return header }
            // URL 查询串偶发带 token
            let pageUrl: String? = await MainActor.run { webView.url?.absoluteString }
            if let s = pageUrl, DjcAuth.parseOAuth(s) != nil {
                return s + "; " + header
            }
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

    static func snapshotQQCookies(from webView: WKWebView) async -> [HTTPCookie] {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        return cookies.filter {
            let d = $0.domain.lowercased()
            return d.contains("qq.com") || d.contains("gtimg.cn")
        }
    }

    static func restore(_ cookies: [HTTPCookie], into webView: WKWebView) async {
        guard !cookies.isEmpty else { return }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for c in cookies {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.setCookie(c) { cont.resume() }
            }
        }
    }

    static func clearAll(from webView: WKWebView) async {
        let dataStore = webView.configuration.websiteDataStore
        let store = dataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        for c in cookies {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.delete(c) { cont.resume() }
            }
        }
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
        ]
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { cont in
            dataStore.fetchDataRecords(ofTypes: types) { cont.resume(returning: $0) }
        }
        let qqRecords = records.filter { rec in
            let d = rec.displayName.lowercased()
            return d.contains("qq.com") || d.contains("gtimg.cn") || d.contains("qlogo.cn")
        }
        if !qqRecords.isEmpty {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                dataStore.removeData(ofTypes: types, for: qqRecords) { cont.resume() }
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: types,
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) { cont.resume() }
        }
    }
}
