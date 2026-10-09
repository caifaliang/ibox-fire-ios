import Foundation
import Network

/// 对齐饭店助手·动画版：同源托管 `/assets/flashreplay/*`，CDN 走 `/remote/{host}/…` 落盘流式供给。
final class RuffleLocalServer {
    static let shared = RuffleLocalServer()

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var flashRoot: URL?
    private let queue = DispatchQueue(label: "daledou.ruffle.http", qos: .userInitiated)
    private let session = URLSession(configuration: .ephemeral)
    var onLog: ((String) -> Void)?

    var baseURL: URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    private static let emptySwf = Data([
        0x46, 0x57, 0x53, 0x0A,
        0x18, 0x00, 0x00, 0x00,
        0x70, 0x00, 0x13, 0x88, 0x00, 0x00, 0xEA, 0x60,
        0x00, 0x0C, 0x01, 0x00, 0x40, 0x00, 0x00, 0x00,
    ])

    @discardableResult
    func start(flashRoot: URL) throws -> URL {
        if listener != nil, port > 0, self.flashRoot == flashRoot, let base = baseURL {
            return base
        }
        stop()
        self.flashRoot = flashRoot

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
        guard parts.count >= 2 else {
            respond(conn, status: 400, mime: "text/plain", body: Data("bad request".utf8))
            return
        }
        let method = String(parts[0])
        if method == "OPTIONS" {
            var head = "HTTP/1.1 204 No Content\r\n"
            head += "Access-Control-Allow-Origin: *\r\n"
            head += "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: *\r\n"
            head += "Content-Length: 0\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        guard method == "GET" || method == "HEAD" else {
            respond(conn, status: 405, mime: "text/plain", body: Data("method".utf8))
            return
        }
        let isHead = method == "HEAD"
        let rawTarget = String(parts[1])
        let pathPart = rawTarget.split(separator: "?", maxSplits: 1)
        let path = String(pathPart[0])
        let query = pathPart.count > 1 ? String(pathPart[1]) : ""

        // 饭店助手 CGI stub（query=-5 阻止大厅全量拉资源）
        if path.contains("/cgi-bin/petpk") || path.contains("/__cgi/petpk")
            || (path.contains("/remote/") && path.contains("/cgi-bin/petpk")) {
            let body = Self.stubCGI(query: query)
            log("CGI stub \(query.prefix(48))")
            respond(conn, status: 200, mime: "application/json", body: Data(body.utf8), headOnly: isHead)
            return
        }

        if path.hasPrefix("/remote/") {
            serveRemote(path: path, query: query, conn: conn, headOnly: isHead)
            return
        }

        if path.contains("crossdomain.xml") {
            let xml = #"<cross-domain-policy><allow-access-from domain="*" /></cross-domain-policy>"#
            respond(conn, status: 200, mime: "text/xml", body: Data(xml.utf8), headOnly: isHead)
            return
        }

        serveFlashAsset(path: path, conn: conn, headOnly: isHead)
    }

    private func serveFlashAsset(path rawPath: String, conn: NWConnection, headOnly: Bool) {
        guard let flashRoot else {
            respond(conn, status: 500, mime: "text/plain", body: Data("no root".utf8))
            return
        }
        var rel = rawPath
        if let decoded = rel.removingPercentEncoding { rel = decoded }
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        // /assets/flashreplay/xxx → xxx
        if rel.hasPrefix("assets/flashreplay/") {
            rel = String(rel.dropFirst("assets/flashreplay/".count))
        } else if rel.hasPrefix("flashreplay/") {
            rel = String(rel.dropFirst("flashreplay/".count))
        }
        if rel.isEmpty { rel = "index.html" }

        let local = flashRoot.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: local.path) else {
            log("MISS flash \(rel)")
            respond(conn, status: 404, mime: "text/plain", body: Data("missing".utf8))
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
        if rel.hasSuffix(".wasm") || rel.hasSuffix(".swf") {
            log("BUNDLE stream \(rel) \(size)B")
        }
        respondFile(conn, fileURL: local, mime: mime(rel), headOnly: headOnly)
    }

    /// `/remote/fightimg.pet.qq.com/swf/gres/...` → https://fightimg.pet.qq.com/swf/gres/...
    private func serveRemote(path: String, query: String, conn: NWConnection, headOnly: Bool) {
        var rest = path
        if rest.hasPrefix("/remote/") {
            rest = String(rest.dropFirst("/remote/".count))
        }
        guard !rest.isEmpty else {
            respond(conn, status: 400, mime: "text/plain", body: Data("bad remote".utf8))
            return
        }
        let remoteURLString = "https://\(rest)" + (query.isEmpty ? "" : "?\(query)")
        guard let remoteURL = URL(string: remoteURLString) else {
            respond(conn, status: 400, mime: "text/plain", body: Data("bad url".utf8))
            return
        }
        let host = remoteURL.host ?? ""
        let allowed = ["fightimg.pet.qq.com", "fight.pet.qq.com", "imgcache.qq.com", "qzonestyle.gtimg.cn"]
        guard allowed.contains(host) else {
            log("BLOCK remote \(host)")
            respond(conn, status: 403, mime: "text/plain", body: Data("forbidden".utf8))
            return
        }

        // 错性别 action stub（与大乐斗 APK 一致）
        let low = remoteURL.path.lowercased()
        if low.contains("action_gg") || low.contains("action_mm") {
            let preferMm = ActionPackPrefetch.sessionPreferMm
            let wrong = preferMm ? low.contains("action_gg") : low.contains("action_mm")
            if wrong, !low.contains("gg2"), !low.contains("mm2") {
                log("STUB wrong-gender \(remoteURL.lastPathComponent)")
                respond(conn, status: 200, mime: "application/x-shockwave-flash", body: Self.emptySwf, headOnly: headOnly)
                return
            }
        }

        let name = remoteURL.lastPathComponent
        // iOS：loadingSWC 嵌套 Loader 即使包内良品也 COMPLETE 不了 → 2s 死循环。
        // 回放模式用空 SWF 让 Load.COMPLETE 立刻成功，越过加载层进 FightReady。
        if name.lowercased().contains("loadingswc") {
            log("STUB loadingSWC → empty (break nested Loader loop)")
            respond(conn, status: 200, mime: "application/x-shockwave-flash", body: Self.emptySwf, headOnly: headOnly)
            return
        }
        // 复用 ActionPackPrefetch 已落盘的 action_gg/mm
        if low.contains("/swf/gres/action_") || low.contains("gres/action_") {
            let pref = ActionPackPrefetch.localURL(for: "gres/\(name)")
            if FileManager.default.fileExists(atPath: pref.path) {
                let size = (try? FileManager.default.attributesOfItem(atPath: pref.path)[.size] as? NSNumber)?.int64Value ?? 0
                if size > 1_000_000 {
                    _ = SwfPrefixStrip.stripFileIfNeeded(pref)
                    log("PACK prefetch-hit \(name) \(size)B")
                    respondFile(conn, fileURL: pref, mime: mime(remoteURL.path), headOnly: headOnly)
                    return
                }
            }
        }
        // 包内已知良品 gres（loadingSWC 等），避免 CDN 剥离/兼容问题导致 2s 死循环重试
        if let bundled = Self.bundledGresURL(name: name),
           FileManager.default.fileExists(atPath: bundled.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: bundled.path)[.size] as? NSNumber)?.int64Value ?? 0
            log("BUNDLE gres \(name) \(size)B")
            respondFile(conn, fileURL: bundled, mime: mime(remoteURL.path), headOnly: headOnly)
            return
        }

        let cacheKey = rest.replacingOccurrences(of: "/", with: "_")
        let dest = ActionPackPrefetch.cacheRoot().appendingPathComponent("remote_\(cacheKey)")
        if FileManager.default.fileExists(atPath: dest.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
            if size > 1000 {
                if low.hasSuffix(".swf") {
                    _ = SwfPrefixStrip.stripFileIfNeeded(dest)
                }
                if low.contains("action_gg") || low.contains("action_mm"), !low.contains("gg2"), !low.contains("mm2") {
                    log("PACK stream \(remoteURL.lastPathComponent) \(size)B")
                } else {
                    log("CACHE stream \(remoteURL.lastPathComponent) \(size)B")
                }
                respondFile(conn, fileURL: dest, mime: mime(remoteURL.path), headOnly: headOnly)
                return
            }
        }

        log("CDN \(remoteURL.host ?? "")\(remoteURL.path)")
        var req = URLRequest(url: remoteURL)
        req.timeoutInterval = 180
        req.setValue("https://fight.pet.qq.com/replay.html", forHTTPHeaderField: "Referer")
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err {
                self.log("CDN FAIL \(remoteURL.lastPathComponent) \(err.localizedDescription)")
                self.respond(conn, status: 502, mime: "text/plain", body: Data("cdn fail".utf8))
                return
            }
            var payload = data ?? Data()
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if remoteURL.pathExtension.lowercased() == "swf" {
                let before = payload.count
                payload = SwfPrefixStrip.stripData(payload)
                if payload.count != before {
                    self.log("STRIP CDN \(remoteURL.lastPathComponent) -\(before - payload.count)B")
                }
            }
            // 单文件上限 64MB（饭店助手）
            if payload.count > 67_108_864 {
                self.respond(conn, status: 502, mime: "text/plain", body: Data("too large".utf8))
                return
            }
            try? FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? payload.write(to: dest, options: .atomic)
            self.log("CDN OK \(code) \(remoteURL.lastPathComponent) \(payload.count)B")
            if low.contains("action_gg") || low.contains("action_mm"), !low.contains("gg2"), !low.contains("mm2") {
                self.log("PACK delivered via HTTP \(payload.count)B")
            }
            self.respond(
                conn,
                status: (200..<300).contains(code) ? 200 : code,
                mime: self.mime(remoteURL.path),
                body: payload,
                headOnly: headOnly
            )
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
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 502: reason = "Bad Gateway"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Cache-Control: no-store\r\n"
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

    /// 饭店助手 C0215j CGI：query=-5 阻止大厅；其余最小 JSON
    private static func stubCGI(query: String) -> String {
        let q = query.lowercased()
        if q.contains("cmd=query") {
            return #"{"result":"-5","msg":"正在加载战斗回放…"}"#
        }
        if q.contains("weapon_specialize") || q.contains("cmd=popup") {
            return #"{"result":"0","msg":""}"#
        }
        return #"{"result":"-1","msg":""}"#
    }

    /// 包内 ruffle_fight/gres 已知良品（优先于 CDN，防 loadingSWC 死循环）
    private static func bundledGresURL(name: String) -> URL? {
        let low = name.lowercased()
        // 只替换启动关键件，动作包仍走 CDN/prefetch
        let allow = ["loadingswc", "spchack", "leisure", "xmls", "ui-"]
        guard allow.contains(where: { low.contains($0) }) else { return nil }
        let bundle = Bundle.main
        if let u = bundle.resourceURL?
            .appendingPathComponent("ruffle_fight/gres/\(name)"),
           FileManager.default.fileExists(atPath: u.path) {
            return u
        }
        // 模糊：gres 下按前缀找
        if let gres = bundle.resourceURL?.appendingPathComponent("ruffle_fight/gres"),
           let files = try? FileManager.default.contentsOfDirectory(atPath: gres.path) {
            let prefix = String(low.prefix(while: { $0.isLetter || $0 == "-" || $0 == "_" }))
            if let hit = files.first(where: { $0.lowercased().hasPrefix(prefix) && $0.lowercased().hasSuffix(".swf") }) {
                return gres.appendingPathComponent(hit)
            }
        }
        return nil
    }
}
