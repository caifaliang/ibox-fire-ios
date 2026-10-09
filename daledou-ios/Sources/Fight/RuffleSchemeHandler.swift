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

    /// 主动作包（action_gg/mm）已交给 Flash；gg2/mm2 表示解析完成
    var onActionPackEvent: ((String) -> Void)?
    /// 资源访问调试日志
    var onResourceLog: ((String) -> Void)?

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

        let lowRel = rel.lowercased()
        if lowRel.contains("action_") || lowRel.hasSuffix(".swf") || lowRel.hasSuffix(".wasm") {
            logRes("REQ \(rel)")
        }
        // gg2/mm2 ≈ 根动作包已解析完（对齐 Android）
        if (lowRel.contains("action_gg") || lowRel.contains("action_mm")),
           lowRel.contains("gg2") || lowRel.contains("mm2") {
            notifyPack("parsed")
        }

        // 对齐 Android：错性别主动作包回空 SWF，避免双包抢 Loader
        if lowRel.contains("action_gg") || lowRel.contains("action_mm") {
            let preferMm = ActionPackPrefetch.sessionPreferMm
            let wrong = preferMm ? lowRel.contains("action_gg") : lowRel.contains("action_mm")
            if wrong {
                logRes("STUB wrong-gender \(rel)")
                finish(urlSchemeTask, url: url, data: Self.emptySwf, mime: mime(for: rel))
                return
            }
        }
        // 主路径已切饭店助手 flashreplay；scheme 兜底不再 stub 大厅

        // 预下载缓存（Documents/ruffle_cdn）
        let cached = ActionPackPrefetch.localURL(for: rel.hasPrefix("gres/") ? rel : (path.contains("/gres/") ? "gres/" + (rel as NSString).lastPathComponent : rel))
        if (lowRel.contains("action_gg") || lowRel.contains("action_mm") || lowRel.hasPrefix("gres/")),
           FileManager.default.fileExists(atPath: cached.path) {
            if lowRel.hasSuffix(".swf") { _ = SwfPrefixStrip.stripFileIfNeeded(cached) }
            if let data = try? Data(contentsOf: cached), data.count > 1000 {
                logRes("CACHE \(rel) \(data.count)B sigOK=\(SwfPrefixStrip.hasValidSig(data))")
                finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
                if lowRel.contains("action_gg") || lowRel.contains("action_mm"),
                   !lowRel.contains("gg2"), !lowRel.contains("mm2") {
                    notifyPack("delivered")
                }
                return
            }
        }
        // 兼容 rel 已是 gres/xxx
        let cached2 = ActionPackPrefetch.localURL(for: rel)
        if FileManager.default.fileExists(atPath: cached2.path) {
            if lowRel.hasSuffix(".swf") { _ = SwfPrefixStrip.stripFileIfNeeded(cached2) }
            if let data = try? Data(contentsOf: cached2), data.count > 1000 {
                logRes("CACHE2 \(rel) \(data.count)B")
                finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
                if lowRel.contains("action_gg") || lowRel.contains("action_mm"),
                   !lowRel.contains("gg2"), !lowRel.contains("mm2") {
                    notifyPack("delivered")
                }
                return
            }
        }

        let local = root.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: local.path),
           let data = try? Data(contentsOf: local) {
            if lowRel.contains("action_") || lowRel.hasSuffix(".wasm") || lowRel.hasSuffix("PetFunFight.swf") {
                logRes("BUNDLE \(rel) \(data.count)B")
            }
            finish(urlSchemeTask, url: url, data: data, mime: mime(for: rel))
            return
        }

        if let cdn = cdnURL(for: rel, originalPath: path) {
            logRes("CDN \(rel) → \(cdn.lastPathComponent)")
            proxyAndCache(cdn, rel: rel, task: urlSchemeTask)
            return
        }

        logRes("MISS \(rel)")
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
        let rawQuery = url.query ?? ""
        let query = rawQuery.lowercased()
        var body = "{\"result\":\"0\",\"msg\":\"\",\"sn\":\"1\",\"list\":[]}"
        if query.contains("cmd=query") {
            body = Self.petpkQueryStub(root: root)
        } else if query.contains("weapon_specialize") {
            // 对齐 Android buildWeaponSpecializeStub：空 list 会导致专精/开战异常
            body = Self.weaponSpecializeStub(query: rawQuery)
            logRes("CGI weapon_specialize stub \(body.count)B")
        } else if query.contains("cmd=popup") {
            body = "{\"result\":\"0\",\"msg\":\"\",\"sn\":\"1\",\"list\":[],\"popupList\":[]}"
        } else if query.contains("skillenhance") {
            body = "{\"result\":\"0\",\"msg\":\"\",\"cmd\":\"skillEnhance\",\"op\":\"11\",\"sn\":\"1\",\"list\":[]}"
        } else if query.contains("cmd=hotspot") {
            body = "{\"result\":\"-1\",\"msg\":\"app_skip\",\"sn\":\"1\",\"list\":[],\"data\":[]}"
        }
        finish(task, url: url, data: Data(body.utf8), mime: "text/plain")
    }

    /// nowTimer 必须是有效 unix 秒，否则随机背景空列表会炸
    private static func petpkQueryStub(root: URL) -> String {
        let nowSec = String(Int(Date().timeIntervalSince1970))
        let stubURL = root.appendingPathComponent("petpk_query.json")
        if let data = try? Data(contentsOf: stubURL),
           var s = String(data: data, encoding: .utf8) {
            if let re = try? NSRegularExpression(pattern: #"("name"\s*:\s*"[^"]*\$)(\d+)(\$[^"]*")"#) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1\(nowSec)$3")
            }
            return s
        }
        let name = "2$16$123$10001$\(nowSec)$app"
        return "{\"result\":\"0\",\"msg\":\"\",\"name\":\"\(name)\",\"sn\":\"1\"}"
    }

    private static func weaponSpecializeStub(query: String) -> String {
        func qp(_ name: String) -> String {
            guard let re = try? NSRegularExpression(pattern: "(?:^|&)\(NSRegularExpression.escapedPattern(for: name))=([^&]*)"),
                  let m = re.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: query) else { return "" }
            return query[r].removingPercentEncoding ?? String(query[r])
        }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
        let w1 = qp("weaponspe1")
        let w2 = qp("weaponspe2")
        return """
        {"result":"0","msg":"","weapons_num":"1","src_weapons0":[],"dst_weapons0":[],"weaponspe1":"\(esc(w1))","weaponspe2":"\(esc(w2))","weaponspe":"\(esc(w1))"}
        """
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
                self.logRes("CDN FAIL \(remote.lastPathComponent) \(err.localizedDescription)")
                self.fail(task, err)
                return
            }
            var payload = data ?? Data()
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var mime = (resp as? HTTPURLResponse)?.mimeType
                ?? self.mime(for: remote.lastPathComponent)
            if remote.pathExtension.lowercased() == "swf" {
                let before = payload.count
                payload = SwfPrefixStrip.stripData(payload)
                if payload.count != before {
                    self.logRes("STRIP CDN \(remote.lastPathComponent) -\(before - payload.count)B")
                }
                mime = "application/x-shockwave-flash"
            }
            self.logRes("CDN OK \(code) \(remote.lastPathComponent) \(payload.count)B")
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
            if let rel, (rel.contains("action_gg") || rel.contains("action_mm")),
               !rel.contains("gg2"), !rel.contains("mm2"), payload.count > 1_000_000 {
                self.notifyPack("delivered")
            }
        }
        lock.lock()
        tasks[ObjectIdentifier(task)] = dataTask
        lock.unlock()
        dataTask.resume()
    }

    private func notifyPack(_ kind: String) {
        let cb = onActionPackEvent
        DispatchQueue.main.async { cb?(kind) }
    }

    private func logRes(_ msg: String) {
        let cb = onResourceLog
        DispatchQueue.main.async { cb?(msg) }
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
