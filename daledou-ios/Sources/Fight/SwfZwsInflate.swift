import Foundation

/// 在 App 进程把 ZWS(LZMA) 预解压成 FWS，避免 WebContent 内
/// 压缩输入(~38MB) + 解压缓冲(~69MB) + LZMA 字典叠峰。
/// LZMA：vendored SWCompression（MIT）+ BitByteData（MIT）。
enum SwfZwsInflate {
    /// - Returns: true 若本函数写出了新的 FWS；已是 FWS/CWS 返回 false（不算失败）。
    @discardableResult
    static func inflateFileIfNeeded(_ fileURL: URL, log: ((String) -> Void)? = nil) -> Bool {
        guard let head = readHead(fileURL, 17), head.count >= 8 else {
            log?("SWF inflate: cannot read head")
            return false
        }
        let b0 = head[0], b1 = head[1], b2 = head[2]
        if b0 == 0x46, b1 == 0x57, b2 == 0x53 {
            let ulen = u32LE(head, 4)
            log?("SWF already FWS ulen=\(ulen) size=\(fileSize(fileURL))")
            return false
        }
        if b0 == 0x43, b1 == 0x57, b2 == 0x53 {
            let ulen = u32LE(head, 4)
            log?("SWF CWS keep zlib ulen=\(ulen) size=\(fileSize(fileURL))")
            return false
        }
        guard b0 == 0x5A, b1 == 0x57, b2 == 0x53, head.count >= 17 else {
            log?("SWF inflate skip bad sig \(b0)-\(b1)-\(b2)")
            return false
        }

        let version = head[3]
        let ulen = u32LE(head, 4)
        let needBody = Int(ulen) &- 8
        guard needBody > 1_000_000 else {
            log?("SWF ZWS ulen weird \(ulen)")
            return false
        }
        log?("SWF ZWS→FWS start size=\(fileSize(fileURL)) ulen=\(ulen)")

        do {
            let raw = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard raw.count > 17 else {
                log?("SWF ZWS too small \(raw.count)")
                return false
            }
            // 与 Python 已验证配方一致：LZMA alone = props(5) + size=0xFF..FF + payload
            // （SWF ZWS：12..17=props，17..=compressed+EOS）
            var alone = Data()
            alone.append(raw.subdata(in: 12..<17))
            alone.append(contentsOf: [UInt8](repeating: 0xFF, count: 8))
            alone.append(raw.subdata(in: 17..<raw.count))

            let body = try LZMA.decompress(data: alone)
            guard body.count >= needBody - 8 else {
                log?("SWF ZWS→FWS short body=\(body.count) need=\(needBody)")
                return false
            }
            let slice = body.count >= needBody ? body.prefix(needBody) : body[...]

            var out = Data(capacity: 8 + slice.count)
            out.append(contentsOf: [0x46, 0x57, 0x53, version])
            var le = ulen.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
            out.append(contentsOf: slice)

            let tmp = fileURL.appendingPathExtension("fws.tmp")
            try out.write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: tmp, to: fileURL)
            log?("SWF ZWS→FWS OK size=\(fileSize(fileURL)) (App inflate)")
            return true
        } catch {
            log?("SWF ZWS→FWS FAIL \(String(describing: error))")
            return false
        }
    }

    static func signature(of fileURL: URL) -> String {
        guard let h = readHead(fileURL, 3), h.count == 3,
              let s = String(bytes: h, encoding: .ascii) else { return "?" }
        return s
    }

    private static func readHead(_ url: URL, _ n: Int) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        return fh.readData(ofLength: n)
    }

    private static func u32LE(_ data: Data, _ off: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self) }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
