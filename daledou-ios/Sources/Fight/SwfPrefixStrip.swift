import Foundation
import zlib

/// CDN 下发的 SWF 常带若干 NUL 前缀；未剥离时 Loader 立刻 IO_ERROR（对齐 Android `stripSwfPrefix`）。
enum SwfPrefixStrip {
    private static let sigs: [[UInt8]] = [
        [0x43, 0x57, 0x53], // CWS
        [0x46, 0x57, 0x53], // FWS
        [0x5A, 0x57, 0x53], // ZWS
    ]

    static func needsStrip(fileURL: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? fh.close() }
        let head = fh.readData(ofLength: 16)
        guard head.count >= 3 else { return false }
        return !hasValidSig(head)
    }

    static func hasValidSig(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        let b0 = data[data.startIndex]
        let b1 = data[data.startIndex + 1]
        let b2 = data[data.startIndex + 2]
        return (b0 == 0x43 || b0 == 0x46 || b0 == 0x5A) && b1 == 0x57 && b2 == 0x53
    }

    /// 若需要则原地剥离；大文件流式处理，避免整包进内存。
    @discardableResult
    static func stripFileIfNeeded(_ fileURL: URL) -> Bool {
        guard needsStrip(fileURL: fileURL) else { return false }
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return false }
        let head = fh.readData(ofLength: 64)
        try? fh.close()
        guard let skip = prefixSkip(in: head), skip > 0 else { return false }

        let tmp = fileURL.appendingPathExtension("strip")
        guard let inp = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? inp.close() }
        do {
            try inp.seek(toOffset: UInt64(skip))
        } catch {
            return false
        }
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let out = try? FileHandle(forWritingTo: tmp) else { return false }
        defer { try? out.close() }
        while true {
            let chunk = inp.readData(ofLength: 256 * 1024)
            if chunk.isEmpty { break }
            out.write(chunk)
        }
        try? FileManager.default.removeItem(at: fileURL)
        do {
            try FileManager.default.moveItem(at: tmp, to: fileURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

    /// 内存数据剥离（小文件 / 刚下完的缓冲）。
    static func stripData(_ raw: Data) -> Data {
        guard !hasValidSig(raw) else { return raw }
        guard let skip = prefixSkip(in: raw), skip > 0, skip < raw.count else { return raw }
        return raw.subdata(in: skip..<raw.count)
    }

    /// CWS(zlib) → FWS。`NSData.decompressed(.zlib)` 对 SWF CWS 常失败；改用 zlib。
    static func cwsToFws(_ raw: Data) -> Data {
        let clean = stripData(raw)
        guard clean.count >= 8,
              clean[clean.startIndex] == 0x43,
              clean[clean.startIndex + 1] == 0x57,
              clean[clean.startIndex + 2] == 0x53 else { return clean }
        let ulen = Int(clean.subdata(in: (clean.startIndex + 4)..<(clean.startIndex + 8)).withUnsafeBytes {
            $0.load(as: UInt32.self)
        })
        let body = clean.subdata(in: (clean.startIndex + 8)..<clean.endIndex)
        let expect = max(ulen - 8, 1)
        guard let inflated = inflateZlib(body, expectedSize: expect) else { return clean }
        let slice = inflated.count > expect ? inflated.prefix(expect) : inflated[...]
        var out = Data(capacity: 8 + slice.count)
        out.append(0x46) // F
        out.append(0x57) // W
        out.append(0x53) // S
        out.append(clean[clean.startIndex + 3]) // version
        var le = UInt32(ulen).littleEndian
        withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        out.append(contentsOf: slice)
        return out
    }

    private static func inflateZlib(_ input: Data, expectedSize: Int) -> Data? {
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var output = [UInt8](repeating: 0, count: max(expectedSize, 64 * 1024))
        var total = 0
        var failed = false
        input.withUnsafeBytes { srcBuf in
            guard let src = srcBuf.bindMemory(to: Bytef.self).baseAddress else {
                failed = true
                return
            }
            stream.next_in = UnsafeMutablePointer(mutating: src)
            stream.avail_in = uInt(input.count)
            while true {
                if total >= output.count {
                    output.append(contentsOf: repeatElement(0, count: max(output.count, 64 * 1024)))
                }
                let room = output.count - total
                let rc: Int32 = output.withUnsafeMutableBufferPointer { buf in
                    stream.next_out = buf.baseAddress!.advanced(by: total)
                    stream.avail_out = uInt(room)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let wrote = room - Int(stream.avail_out)
                total += wrote
                if rc == Z_STREAM_END { break }
                if rc != Z_OK {
                    failed = true
                    break
                }
                if wrote == 0 && stream.avail_in == 0 { break }
            }
        }
        if failed || total <= 0 { return nil }
        return Data(output.prefix(total))
    }

    /// NewLoader(isEncode) 在 URLStream COMPLETE 后 `position=9` 再 loadBytes。
    static func encodePrefixForNewLoader(_ raw: Data) -> Data {
        let body: Data
        if hasValidSig(raw) {
            body = raw
        } else if raw.count > 12, hasValidSig(raw.subdata(in: 9..<raw.count)) {
            return raw // 已是 NUL×9 + sig
        } else {
            body = stripData(raw)
        }
        var out = Data(repeating: 0, count: 9)
        out.append(body)
        return out
    }

    /// gres 子 SWF：尽量 FWS + 9 NUL（npc 等 CWS 在 iOS 上易卡「加载中」100%）。
    static func prepareGresSwfForNewLoader(_ raw: Data) -> Data {
        encodePrefixForNewLoader(cwsToFws(raw))
    }

    /// 按路径分流（对齐 NewLoader.onStreamComplete）：
    /// - `xmls*` → URLLoader BINARY，必须干净
    /// - URL 含 `bg` → 不剥 9，必须干净
    /// - `petfunfight*` → Ruffle 主 SWF，干净
    /// - 其余 gres → NewLoader(isEncode) 补 9 NUL，并尽量 FWS
    static func prepareGresAsset(_ raw: Data, fileName: String) -> Data {
        let low = fileName.lowercased()
        if low.contains("xmls") || low.contains("bg") || low.hasPrefix("petfunfight") {
            return stripData(raw)
        }
        return prepareGresSwfForNewLoader(raw)
    }

    /// 大文件流式发送时是否需要额外加 9 NUL（文件本身已是干净签名）。
    static func needsNewLoaderNul9Prefix(fileName: String) -> Bool {
        let low = fileName.lowercased()
        if low.contains("xmls") || low.contains("bg") || low.hasPrefix("petfunfight") { return false }
        if !low.hasSuffix(".swf") { return false }
        return true
    }

    private static func prefixSkip(in data: Data) -> Int? {
        var best: Int?
        let bytes = [UInt8](data.prefix(64))
        for sig in sigs {
            if let i = indexOf(bytes, sig), i > 0 {
                if best == nil || i < best! { best = i }
            }
        }
        return best
    }

    private static func indexOf(_ data: [UInt8], _ pat: [UInt8]) -> Int? {
        guard data.count >= pat.count else { return nil }
        outer: for i in 0...(data.count - pat.count) {
            for j in pat.indices where data[i + j] != pat[j] {
                continue outer
            }
            return i
        }
        return nil
    }
}
