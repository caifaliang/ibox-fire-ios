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

        // 主动作包：错误性别直接 stub，避免再拉另一份 ~40MB
        let lowRel = rel.lowercased()
        if lowRel.contains("action_gg") || lowRel.contains("action_mm") {
            let wantMm = ActionPackPrefetch.sessionPreferMm
            let isMm = lowRel.contains("action_mm")
            let isGg = lowRel.contains("action_gg")
            let wrong = (wantMm && isGg) || (!wantMm && isMm)
            // gg2/mm2 是二包，放行；只 stub 根包错性别
            let isPack2 = lowRel.contains("gg2") || lowRel.contains("mm2")
            if wrong && !isPack2 {
                finish(urlSchemeTask, url: url, data: Self.emptySwf, mime: "application/x-shockwave-flash")
                return
            }
        }

        // 预下载缓存（Documents/ruffle_cdn）
        let cached = ActionPackPrefetch.localURL(for: rel.hasPrefix("gres/") ? rel : (path.contains("/gres/") ? "gres/" + (rel as NSString).lastPathComponent : rel))
        if (lowRel.contains("action_gg") || lowRel.contains("action_mm") || lowRel.hasPrefix("gres/")),
           FileManager.default.fileExists(atPath: cached.path),
           let data = try? Data(contentsOf: cached), data.count > 1000 {
            finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
            return
        }
        // 兼容 rel 已是 gres/xxx
        let cached2 = ActionPackPrefetch.localURL(for: rel)
        if FileManager.default.fileExists(atPath: cached2.path),
           let data = try? Data(contentsOf: cached2), data.count > 1000 {
            finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
            return
        }

        let local = root.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: local.path),
           let data = try? Data(contentsOf: local) {
            finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
            return
        }

        if let cdn = cdnURL(for: rel, originalPath: path) {
            proxyAndCache(cdn, rel: rel, task: urlSchemeTask)
            return
        }

        fail(urlSchemeTask, URLError(.fileDoesNotExist))
    }

    /// 最小合法 FWS，满足 Loader.complete（对齐 Android emptySwfResponse）
    private static let emptySwf = Data([
        0x46, 0x57, 0x53, 0x0A,
        0x18, 0x00, 0x00, 0x00,
        0x70, 0x00, 0x13, 0x88, 0x00, 0x00, 0xEA, 0x60,
        0x00, 0x0C, 0x01, 0x00, 0x40, 0x00, 0x00, 0x00,
    ])

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
        proxyAndCache(remote, rel: nil, task: task)
    }

    private func proxyAndCache(_ remote: URL, rel: String?, task: WKURLSchemeTask) {
        var req = URLRequest(url: remote)
        req.timeoutInterval = 180
        let dataTask = session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            self.lock.lock()
            self.tasks[ObjectIdentifier(task)] = nil
            self.lock.unlock()
            if let err {
                self.fail(task, err)
                return
            }
            let payload = data ?? Data()
            let mime = (resp as? HTTPURLResponse)?.mimeType
                ?? self.mime(for: remote.lastPathComponent)
            // 大动作包落盘，下次直接读缓存
            if let rel, payload.count > 1_000_000,
               rel.contains("action_gg") || rel.contains("action_mm") {
                let dest = ActionPackPrefetch.localURL(for: rel.hasPrefix("gres/") ? rel : "gres/\((rel as NSString).lastPathComponent)")
                try? FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? payload.write(to: dest, options: .atomic)
            }
            self.finish(task, url: task.request.url ?? remote, data: payload, mime: mime)
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
