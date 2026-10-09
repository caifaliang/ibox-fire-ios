import Foundation
import WebKit

/// 托管包内 `ruffle_fight`，并代理 CDN 动作包 / 头像（对齐 Android WebViewAssetLoader）
final class RuffleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "app-ruffle"

    private let root: URL
    private let session = URLSession(configuration: .ephemeral)
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private let lock = NSLock()

    override init() {
        let bundle = Bundle.main
        if let u = bundle.url(forResource: "index", withExtension: "html", subdirectory: "ruffle_fight") {
            root = u.deletingLastPathComponent()
        } else if let u = bundle.resourceURL?.appendingPathComponent("ruffle_fight") {
            root = u
        } else {
            root = bundle.bundleURL.appendingPathComponent("ruffle_fight")
        }
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path
        // /__cgi/petpk → stub
        if path.contains("/__cgi/petpk") || path.hasSuffix("/__cgi/petpk") {
            respondStubCGI(urlSchemeTask, url: url)
            return
        }
        // /__proxy/remote?u=
        if path.contains("/__proxy/remote"),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let remote = comps.queryItems?.first(where: { $0.name == "u" })?.value,
           let remoteURL = URL(string: remote) {
            proxy(remoteURL, task: urlSchemeTask)
            return
        }

        // Strip optional /ruffle_fight prefix for file lookup
        var rel = path
        if rel.hasPrefix("/ruffle_fight/") {
            rel = String(rel.dropFirst("/ruffle_fight/".count))
        } else if rel.hasPrefix("/") {
            rel = String(rel.dropFirst())
        }
        if rel.isEmpty { rel = "index.html" }

        // /gres/... may be under root/gres
        let local = root.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: local.path),
           let data = try? Data(contentsOf: local) {
            finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
            return
        }

        // CDN fallback for gres / img / images
        if let cdn = cdnURL(for: rel, originalPath: path) {
            proxy(cdn, task: urlSchemeTask)
            return
        }

        urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id]?.cancel()
        tasks[id] = nil
        lock.unlock()
    }

    private func respondStubCGI(_ task: WKURLSchemeTask, url: URL) {
        let query = url.query?.lowercased() ?? ""
        let stubURL = root.appendingPathComponent("petpk_query.json")
        var body = "{\"result\":\"0\",\"msg\":\"\"}"
        if query.contains("cmd=query"),
           let data = try? Data(contentsOf: stubURL),
           let s = String(data: data, encoding: .utf8) {
            body = s
        } else if query.contains("weapon_specialize") {
            body = "{\"result\":\"0\",\"msg\":\"\",\"list\":[]}"
        } else if query.contains("cmd=popup") || query.contains("skillenhance") || query.contains("cmd=hotspot") {
            body = "{\"result\":\"0\",\"msg\":\"\"}"
        }
        finish(task, url: url, data: Data(body.utf8), mime: "application/json")
    }

    private func cdnURL(for rel: String, originalPath: String) -> URL? {
        let low = rel.lowercased()
        let pathLow = originalPath.lowercased()
        if low.hasPrefix("gres/") || pathLow.contains("/gres/") {
            let name = rel.hasPrefix("gres/") ? String(rel.dropFirst(5)) : rel
            return URL(string: "https://fightimg.pet.qq.com/swf/gres/\(name)")
        }
        if low.hasPrefix("img/") || pathLow.contains("/img/") {
            return URL(string: "https://fightimg.pet.qq.com/\(rel)")
        }
        if low.hasPrefix("images/") || pathLow.contains("/images/") {
            return URL(string: "https://fightimg.pet.qq.com/\(rel)")
        }
        // action packs requested as bare gres name via rewrite
        if low.hasSuffix(".swf") && !low.contains("/") {
            return URL(string: "https://fightimg.pet.qq.com/swf/gres/\(rel)")
        }
        return nil
    }

    private func proxy(_ remote: URL, task: WKURLSchemeTask) {
        var req = URLRequest(url: remote)
        req.timeoutInterval = 120
        let dataTask = session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            self.lock.lock()
            self.tasks[ObjectIdentifier(task)] = nil
            self.lock.unlock()
            if let err {
                task.didFailWithError(err)
                return
            }
            let mime = (resp as? HTTPURLResponse)?.mimeType
                ?? self.mime(for: remote.lastPathComponent)
            let payload = data ?? Data()
            self.finish(task, url: task.request.url ?? remote, data: payload, mime: mime)
        }
        lock.lock()
        tasks[ObjectIdentifier(task)] = dataTask
        lock.unlock()
        dataTask.resume()
    }

    private func finish(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ]
        guard let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers
        ) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func mime(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "wasm": return "application/wasm"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "swf": return "application/x-shockwave-flash"
        case "ttf": return "font/ttf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "css": return "text/css"
        default: return "application/octet-stream"
        }
    }
}
