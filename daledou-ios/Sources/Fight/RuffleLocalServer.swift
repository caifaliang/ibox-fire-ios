import Foundation
import Network

/// 本机 HTTP 同源托管 ruffle_fight（对齐 Android `https://appassets.androidplatform.net`）。
/// Flash/Ruffle Loader 拒绝 `app-ruffle://` / `blob:`，即使 fetch 已 200 仍会 `sal_base_err io`。
final class RuffleLocalServer {
    static let shared = RuffleLocalServer()

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var root: URL?
    private let queue = DispatchQueue(label: "daledou.ruffle.http", qos: .userInitiated)
    private let session = URLSession(configuration: .ephemeral)
    var onLog: ((String) -> Void)?

    var baseURL: URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    /// 最小合法 FWS（错性别 stub）
    private static let emptySwf = Data([
        0x46, 0x57, 0x53, 0x0A,
        0x18, 0x00, 0x00, 0x00,
        0x70, 0x00, 0x13, 0x88, 0x00, 0x00, 0xEA, 0x60,
        0x00, 0x0C, 0x01, 0x00, 0x40, 0x00, 0x00, 0x00,
    ])

    /// 与 APK `FlashRuffleReplayWebView` stubHeavy **完全一致**（勿自行加砍）。
    /// APK 不降分辨率；只 stub 这几个大厅装饰。错性别 action 另走 emptySwf。
    static func shouldStubReplayAsset(_ lowPath: String) -> Bool {
        let keys = [
            "worldmap",
            "fenxiang",
            "huangzuan",
            "choujiang",
        ]
        return keys.contains(where: { lowPath.contains($0) })
    }

    @discardableResult
    func start(root: URL) throws -> URL {
        if listener != nil, port > 0, self.root == root, let base = baseURL {
            return base
        }
        stop()
        self.root = root

        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: .any)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }

        let sem = DispatchSemaphore(value: 0)
        var startErr: Error?
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let p = listener.port?.rawValue {
                    self.port = p
                    self.log("HTTP ready :\(p)")
                }
                sem.signal()
            case .failed(let err):
                startErr = err
                self.log("HTTP fail \(err)")
                sem.signal()
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
        _ = sem.wait(timeout: .now() + 3)
        if let startErr { throw startErr }
        guard let base = baseURL else {
            throw URLError(.cannotConnectToHost)
        }
        return base
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(on: conn, buffer: Data())
    }

    private func receiveRequest(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                conn.cancel()
                return
            }
            if let error {
                self.log("recv \(error.localizedDescription)")
                conn.cancel()
                return
            }
            var buf = buffer
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = buf.subdata(in: buf.startIndex..<range.lowerBound)
                self.handle(head: head, conn: conn)
                return
            }
            if isComplete || buf.count > 1024 * 1024 {
                conn.cancel()
                return
            }
            self.receiveRequest(on: conn, buffer: buf)
        }
    }

    private func handle(head: Data, conn: NWConnection) {
        guard let text = String(data: head, encoding: .utf8),
              let first = text.split(separator: "\r\n", maxSplits: 1).first else {
            respond(conn, status: 400, mime: "text/plain", body: Data("bad request".utf8))
            return
        }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            respond(conn, status: 405, mime: "text/plain", body: Data("method".utf8))
            return
        }
        let isHead = parts[0] == "HEAD"
        let rawTarget = String(parts[1])
        let pathPart = rawTarget.split(separator: "?", maxSplits: 1)
        let path = String(pathPart[0])
        let query = pathPart.count > 1 ? String(pathPart[1]) : ""

        if path.contains("/__cgi/petpk") {
            let body = Self.stubCGI(query: query, root: root)
            respond(conn, status: 200, mime: "text/plain", body: Data(body.utf8), headOnly: isHead)
            return
        }
        if path.contains("/__proxy/remote"),
           let comps = URLComponents(string: "http://x\(path)?\(query)"),
           let remote = comps.queryItems?.first(where: { $0.name == "u" })?.value,
           let remoteURL = URL(string: remote) {
            proxy(remoteURL, conn: conn, headOnly: isHead)
            return
        }

        serveFile(path: path, conn: conn, headOnly: isHead)
    }

    private func serveFile(path rawPath: String, conn: NWConnection, headOnly: Bool) {
        guard let root else {
            respond(conn, status: 500, mime: "text/plain", body: Data("no root".utf8))
            return
        }
        var rel = rawPath
        if let decoded = rel.removingPercentEncoding { rel = decoded }
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        if rel.isEmpty { rel = "ruffle_fight/index.html" }

        // /ruffle_fight/foo → bundle/foo；/gres/foo → gres/foo
        var fileRel = rel
        if fileRel.hasPrefix("ruffle_fight/") {
            fileRel = String(fileRel.dropFirst("ruffle_fight/".count))
        }
        let low = fileRel.lowercased()
        if low.contains("action_") || low.hasSuffix(".swf") || low.hasSuffix(".wasm") {
            log("REQ \(fileRel)")
        }

        if low.contains("action_gg") || low.contains("action_mm") {
            if low.contains("gg2") || low.contains("mm2") {
                // parsed signal — JS/native may listen via logs
            }
            let preferMm = ActionPackPrefetch.sessionPreferMm
            let wrong = preferMm ? low.contains("action_gg") : low.contains("action_mm")
            if wrong {
                log("STUB wrong-gender \(fileRel)")
                respond(conn, status: 200, mime: mime(fileRel), body: Self.emptySwf, headOnly: headOnly)
                return
            }
        }

        // 与 APK stubHeavy 一致（非半分辨率降配）
        if Self.shouldStubReplayAsset(low) {
            log("STUB apk-heavy \(fileRel)")
            respond(conn, status: 200, mime: mime(fileRel), body: Self.emptySwf, headOnly: headOnly)
            return
        }

        let cacheCandidates: [URL] = {
            if fileRel.hasPrefix("gres/") {
                return [ActionPackPrefetch.localURL(for: fileRel)]
            }
            if rawPath.contains("/gres/") {
                let name = (fileRel as NSString).lastPathComponent
                return [ActionPackPrefetch.localURL(for: "gres/\(name)"), ActionPackPrefetch.localURL(for: fileRel)]
            }
            return [ActionPackPrefetch.localURL(for: fileRel)]
        }()
        for cached in cacheCandidates {
            if FileManager.default.fileExists(atPath: cached.path) {
                if low.hasSuffix(".swf"), SwfPrefixStrip.stripFileIfNeeded(cached) {
                    log("STRIP \(fileRel)")
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: cached.path)[.size] as? NSNumber)?.int64Value ?? 0
                if size > 1000 {
                    if low.contains("action_gg") || low.contains("action_mm") {
                        log("CACHE stream \(fileRel) \(size)B")
                        if !low.contains("gg2"), !low.contains("mm2") {
                            log("PACK delivered via HTTP \(size)B")
                        }
                    }
                    // 大文件流式读盘，避免 App 进程再吞一份 37MB
                    respondFile(conn, fileURL: cached, mime: mime(fileRel), headOnly: headOnly)
                    return
                }
            }
        }

        let local = root.appendingPathComponent(fileRel)
        if FileManager.default.fileExists(atPath: local.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
            if low.contains("action_") || low.hasSuffix(".wasm") || low.hasSuffix("petfunfight.swf") {
                log("BUNDLE stream \(fileRel) \(size)B")
            }
            respondFile(conn, fileURL: local, mime: mime(fileRel), headOnly: headOnly)
            return
        }

        // gres 未缓存 → CDN
        if let cdn = cdnURL(for: fileRel) {
            log("CDN \(fileRel) → \(cdn.lastPathComponent)")
            proxyAndCache(cdn, rel: fileRel, conn: conn, headOnly: headOnly)
            return
        }

        log("MISS \(fileRel)")
        respond(conn, status: 404, mime: "text/plain", body: Data("missing".utf8))
    }

    private func cdnURL(for rel: String) -> URL? {
        let low = rel.lowercased()
        if low.hasPrefix("gres/") {
            let name = String(rel.dropFirst(5))
            return URL(string: "https://fightimg.pet.qq.com/swf/gres/\(name)")
        }
        if low.hasPrefix("img/") || low.hasPrefix("images/") {
            return URL(string: "https://fightimg.pet.qq.com/\(rel)")
        }
        if low.hasSuffix(".swf"), !low.contains("/") {
            return URL(string: "https://fightimg.pet.qq.com/swf/gres/\(rel)")
        }
        return nil
    }

    private func proxy(_ remote: URL, conn: NWConnection, headOnly: Bool) {
        proxyAndCache(remote, rel: nil, conn: conn, headOnly: headOnly)
    }

    private func proxyAndCache(_ remote: URL, rel: String?, conn: NWConnection, headOnly: Bool) {
        var req = URLRequest(url: remote)
        req.timeoutInterval = 180
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err {
                self.log("CDN FAIL \(remote.lastPathComponent) \(err.localizedDescription)")
                self.respond(conn, status: 502, mime: "text/plain", body: Data("cdn fail".utf8))
                return
            }
            var payload = data ?? Data()
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var mime = (resp as? HTTPURLResponse)?.mimeType ?? self.mime(remote.lastPathComponent)
            if remote.pathExtension.lowercased() == "swf" {
                let before = payload.count
                payload = SwfPrefixStrip.stripData(payload)
                if payload.count != before {
                    self.log("STRIP CDN \(remote.lastPathComponent) -\(before - payload.count)B")
                }
                mime = "application/x-shockwave-flash"
            }
            self.log("CDN OK \(code) \(remote.lastPathComponent) \(payload.count)B")
            if let rel, payload.count > 1_000_000,
               rel.contains("action_gg") || rel.contains("action_mm") {
                let dest = ActionPackPrefetch.localURL(
                    for: rel.hasPrefix("gres/") ? rel : "gres/\((rel as NSString).lastPathComponent)"
                )
                try? FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? payload.write(to: dest, options: .atomic)
            }
            self.respond(conn, status: (200..<300).contains(code) ? 200 : code, mime: mime, body: payload, headOnly: headOnly)
        }.resume()
    }

    private func respond(
        _ conn: NWConnection,
        status: Int,
        mime: String,
        body: Data,
        headOnly: Bool = false
    ) {
        let headerData = httpHeader(status: status, mime: mime, length: body.count)
        if headOnly || body.isEmpty {
            conn.send(content: headerData, completion: .contentProcessed { _ in
                conn.cancel()
            })
            return
        }
        conn.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if error != nil {
                conn.cancel()
                return
            }
            self?.sendDataBody(body, on: conn, offset: 0)
        })
    }

    /// 从磁盘流式发送（wasm / action_gg），App 侧不整包进堆
    private func respondFile(_ conn: NWConnection, fileURL: URL, mime: String, headOnly: Bool) {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let headerData = httpHeader(status: 200, mime: mime, length: Int(size))
        if headOnly || size <= 0 {
            conn.send(content: headerData, completion: .contentProcessed { _ in
                conn.cancel()
            })
            return
        }
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else {
            respond(conn, status: 500, mime: "text/plain", body: Data("open fail".utf8))
            return
        }
        conn.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if error != nil {
                try? fh.close()
                conn.cancel()
                return
            }
            self?.sendFileBody(fh, on: conn)
        })
    }

    private func httpHeader(status: Int, mime: String, length: Int) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 502: reason = "Bad Gateway"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"
        return Data(head.utf8)
    }

    private func sendDataBody(_ body: Data, on conn: NWConnection, offset: Int) {
        let chunk = 256 * 1024
        if offset >= body.count {
            conn.cancel()
            return
        }
        let end = min(offset + chunk, body.count)
        let slice = body.subdata(in: offset..<end)
        conn.send(content: slice, completion: .contentProcessed { [weak self] error in
            if error != nil {
                conn.cancel()
                return
            }
            self?.sendDataBody(body, on: conn, offset: end)
        })
    }

    private func sendFileBody(_ fh: FileHandle, on conn: NWConnection) {
        let chunk = fh.readData(ofLength: 256 * 1024)
        if chunk.isEmpty {
            try? fh.close()
            conn.cancel()
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil {
                try? fh.close()
                conn.cancel()
                return
            }
            self?.sendFileBody(fh, on: conn)
        })
    }

    private func mime(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "text/javascript"
        case "wasm": return "application/wasm"
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

    private func log(_ msg: String) {
        let cb = onLog
        DispatchQueue.main.async { cb?(msg) }
    }

    // MARK: - CGI stubs（与 RuffleSchemeHandler 对齐）

    private static func stubCGI(query: String, root: URL?) -> String {
        let q = query.lowercased()
        if q.contains("cmd=query") {
            return petpkQueryStub(root: root)
        }
        if q.contains("weapon_specialize") {
            return weaponSpecializeStub(query: query)
        }
        if q.contains("cmd=popup") {
            return "{\"result\":\"0\",\"msg\":\"\",\"sn\":\"1\",\"list\":[],\"popupList\":[]}"
        }
        if q.contains("skillenhance") {
            return "{\"result\":\"0\",\"msg\":\"\",\"cmd\":\"skillEnhance\",\"op\":\"11\",\"sn\":\"1\",\"list\":[]}"
        }
        if q.contains("cmd=hotspot") {
            return "{\"result\":\"-1\",\"msg\":\"app_skip\",\"sn\":\"1\",\"list\":[],\"data\":[]}"
        }
        return "{\"result\":\"0\",\"msg\":\"\",\"sn\":\"1\",\"list\":[]}"
    }

    private static func petpkQueryStub(root: URL?) -> String {
        let nowSec = String(Int(Date().timeIntervalSince1970))
        if let root {
            let stubURL = root.appendingPathComponent("petpk_query.json")
            if let data = try? Data(contentsOf: stubURL),
               var s = String(data: data, encoding: .utf8) {
                if let re = try? NSRegularExpression(pattern: #"("name"\s*:\s*"[^"]*\$)(\d+)(\$[^"]*")"#) {
                    let range = NSRange(s.startIndex..., in: s)
                    s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1\(nowSec)$3")
                }
                return s
            }
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
}
