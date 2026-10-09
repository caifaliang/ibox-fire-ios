import Foundation

/// 在 App 进程把 ZWS(LZMA) 预解压成 FWS，避免 WebContent 内同时持有
/// 压缩输入(~38MB) + 解压缓冲(~69MB) + LZMA 字典。
/// LZMA 实现：vendored SWCompression（MIT）/ BitByteData（MIT）。
enum SwfZwsInflate {
    /// 若已是 FWS/CWS 则跳过；ZWS 则原地换成 FWS。
    @discardableResult
    static func inflateFileIfNeeded(_ fileURL: URL, log: ((String) -> Void)? = nil) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return false }
        let head = fh.readData(ofLength: 17)
        try? fh.close()
        guard head.count >= 17 else { return false }
        let b0 = head[head.startIndex]
        let b1 = head[head.startIndex + 1]
        let b2 = head[head.startIndex + 2]
        // 已是 FWS：无需再解压
        if b0 == 0x46, b1 == 0x57, b2 == 0x53 {
            let ulen = head.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
            log?("SWF already FWS ulen=\(ulen)")
            return false
        }
        // CWS：留给 Ruffle zlib（峰值低于 ZWS+LZMA）
        if b0 == 0x43, b1 == 0x57, b2 == 0x53 {
            let ulen = head.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
            log?("SWF CWS keep zlib ulen=\(ulen)")
            return false
        }
        guard b0 == 0x5A, b1 == 0x57, b2 == 0x53 else {
            log?("SWF skip inflate bad sig")
            return false
        }

        let version = head[head.startIndex + 3]
        let ulen = head.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        let needBody = Int(ulen) &- 8
        guard needBody > 0, ulen > 1_000_000 else {
            log?("SWF ZWS ulen weird \(ulen)")
            return false
        }
        log?("SWF ZWS→FWS start file=\(fileSize(fileURL)) ulen=\(ulen)")

        do {
            let raw = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard raw.count > 17 else { return false }
            let propsByte = raw[12]
            let dictSize = raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 13, as: UInt32.self) }
            let props = try LZMAProperties(lzmaByte: propsByte, Int(dictSize))
            // FORMAT_RAW：payload 从 offset 17 开始；限制输出长度 = ulen-8
            let compressed = raw.subdata(in: 17..<raw.count)
            let body = try LZMA.decompress(
                data: compressed,
                properties: props,
                uncompressedSize: needBody
            )
            guard body.count == needBody || body.count + 8 == Int(ulen) else {
                // 允许差几个字节的 EOS 边界
                if body.count < needBody - 16 {
                    log?("SWF ZWS inflate size mismatch got=\(body.count) need=\(needBody)")
                    return false
                }
            }

            var out = Data(capacity: 8 + body.count)
            out.append(contentsOf: [0x46, 0x57, 0x53, version]) // FWS
            var le = ulen.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
            // 截到官方声明长度
            if body.count >= needBody {
                out.append(body.prefix(needBody))
            } else {
                out.append(body)
                // 补齐极少见短读
                out.append(Data(count: needBody - body.count))
            }

            let tmp = fileURL.appendingPathExtension("fws.tmp")
            try out.write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: tmp, to: fileURL)
            log?("SWF ZWS→FWS ok \(fileSize(fileURL))B (was ZWS, App-side inflate)")
            return true
        } catch {
            log?("SWF ZWS→FWS FAIL \(error.localizedDescription)")
            return false
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
