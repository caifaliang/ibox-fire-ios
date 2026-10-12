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

    /// CWS(zlib) → FWS。嵌套 Loader 在 iOS 上对 CWS 易卡 COMPLETE。
    static func cwsToFws(_ raw: Data) -> Data {
        let clean = stripData(raw)
        guard clean.count >= 8,
              clean[clean.startIndex] == 0x43,
              clean[clean.startIndex + 1] == 0x57,
              clean[clean.startIndex + 2] == 0x53 else { return clean }
        let body = clean.subdata(in: (clean.startIndex + 8)..<clean.endIndex)
        guard let inflated = try? (body as NSData).decompressed(using: .zlib) as Data else {
            return clean
        }
        var out = Data(capacity: 8 + inflated.count)
        out.append(0x46) // F
        out.append(0x57) // W
        out.append(0x53) // S
        out.append(clean[clean.startIndex + 3]) // version
        out.append(clean.subdata(in: (clean.startIndex + 4)..<(clean.startIndex + 8)))
        out.append(inflated)
        return out
    }

    /// NewLoader(isEncode) 在 URLStream COMPLETE 后 `position=9` 再 loadBytes。
    /// fd6 日志出现 POST name=angel → 走的是 stream 路径（非 native），必须带 CDN 式 9 NUL。
    /// 饭店 Android intercept 后剥前缀是因为那边走 native；iOS 见 POST 则补回前缀。
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

    /// gres 子 SWF：FWS + 9 NUL，供 NewLoader encode 路径一次 loadBytes 成功。
    static func prepareGresSwfForNewLoader(_ raw: Data) -> Data {
        encodePrefixForNewLoader(stripData(raw)) // CWS 即可；NewLoader 剥 9 后 loadBytes
    }

    /// 按文件名分流（BeginLoading）：
    /// - `xmls*` → URLLoader BINARY，必须干净签名（加 9NUL 会卡「配置文件 80%」，见 fd11）
    /// - `petfunfight*` → Ruffle 主 SWF，干净签名
    /// - 其余 gres → NewLoader(isEncode)，补 9 NUL
    static func prepareGresAsset(_ raw: Data, fileName: String) -> Data {
        let low = fileName.lowercased()
        if low.contains("xmls") || low.hasPrefix("petfunfight") {
            return stripData(raw)
        }
        return prepareGresSwfForNewLoader(raw)
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
