import Foundation
import WebKit

/// 托管包内 `ruffle_fight`，并代理 CDN 动作包 / 头像（对齐 Android WebViewAssetLoader）
final class RuffleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "app-ruffle"

    private let root: URL
    private let session = URLSession(configuration: .ephemeral)
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private let lock = NSLock()

    /// Bundle 内资源根是否可用（供 UI 报错）
    var rootExists: Bool { FileManager.default.fileExists(atPath: root.path) }
    var rootPath: String { root.path }

    override init() {
        let bundle = Bundle.main
        if let u = bundle.url(forResource: "index", withExtension: "html", subdirectory: "ruffle_fight") {
            root = u.deletingLastPathComponent()
        } else if let u = bundle.resourceURL?.appendingPathComponent("ruffle_fight"),
                  FileManager.default.fileExists(atPath: u.path) {
            root = u
        } else {
            root = bundle.bundleURL.appendingPathComponent("ruffle_fight")
        }
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, URLError(.badURL))
            return
        }
        let path = url.path

        if path.contains("/__cgi/petpk") {
            respondStubCGI(urlSchemeTask, url: url)
            return
        }
        if path.contains("/__proxy/remote"),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let remote = comps.queryItems?.first(where: { $0.name == "u" })?.value,
           let remoteURL = URL(string: remote) {
            proxy(remoteURL, task: urlSchemeTask)
            return
        }

        var rel = path
        if rel.hasPrefix("/ruffle_fight/") {
            rel = String(rel.dropFirst("/ruffle_fight/".count))
        } else if rel.hasPrefix("/") {
            rel = String(rel.dropFirst())
        }
        if rel.isEmpty { rel = "index.html" }

        let local = root.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: local.path),
           let data = try? Data(contentsOf: local) {
            finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
            return
        }

        if let cdn = cdnURL(for: rel, originalPath: path) {
            proxy(cdn, task: urlSchemeTask)
            return
        }

        fail(urlSchemeTask, URLError(.fileDoesNotExist))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id]?.cancel()
        tasks[id] = nil
        lock.unlock()
    }

    private func respondStubCGI(_ task: WKURLSchemeTask, url: URL) {
        let query = (url.query ?? "").lowercased()
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
                self.fail(task, err)
                return
            }
            let mime = (resp as? HTTPURLResponse)?.mimeType
                ?? self.mime(for: remote.lastPathComponent)
            self.finish(task, url: task.request.url ?? remote, data: data ?? Data(), mime: mime)
        }
        lock.lock()
        tasks[ObjectIdentifier(task)] = dataTask
        lock.unlock()
        dataTask.resume()
    }

    private func finish(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let work = {
            // iOS 18 + Ruffle fetch/WASM：必须用带 status=200 的 HTTPURLResponse。
            // 纯 URLResponse 的 status=0 → RangeError: Status must be between 200 and 599
            let headers: [String: String] = [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
            ]
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                task.didFailWithError(URLError(.cannotParseResponse))
                return
            }
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func fail(_ task: WKURLSchemeTask, _ error: Error) {
        let work = { task.didFailWithError(error) }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func mime(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "js": return "text/javascript"
        // WKWebView + 自定义 scheme：application/wasm 会走 instantiateStreaming 并失败；
        // octet-stream 迫使 Ruffle/wasm-bindgen 走 arrayBuffer + instantiate 回退路径。
        case "wasm": return "application/octet-stream"
        case "json": return "application/json"
        case "xml": return "text/xml"
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
