import Foundation

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
