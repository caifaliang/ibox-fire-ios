import Foundation

/// 预拉主动作包到磁盘（对齐 Android `RuffleActionPrefetch`）
enum ActionPackPrefetch {
    static let ggRel = "gres/action_gg-v10.1300.swf"
    static let mmRel = "gres/action_mm-v10.1300.swf"

    /// 当前会话偏好（scheme handler stub 另一性别）
    static var sessionPreferMm = false

    /// `&Player1:1;` = 女号 → action_mm；否则 action_gg
    static func preferMm(from act: String) -> Bool {
        if let r = try? NSRegularExpression(pattern: #"&Player1:(\d+);"#),
           let m = r.firstMatch(in: act, range: NSRange(act.startIndex..., in: act)),
           m.numberOfRanges > 1,
           let range = Range(m.range(at: 1), in: act) {
            return String(act[range]) == "1"
        }
        return false
    }

    static func cacheRoot() -> URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ruffle_cdn", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func localURL(for rel: String) -> URL {
        cacheRoot().appendingPathComponent(rel)
    }

    static func isDiskReady(preferMm: Bool) -> Bool {
        let rel = preferMm ? mmRel : ggRel
        let f = localURL(for: rel)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
              let size = attrs[.size] as? NSNumber else { return false }
        guard size.int64Value > 1_000_000 else { return false }
        // 已缓存但仍带 CDN 前缀时当场剥掉，避免开战 sal_base_err io
        _ = SwfPrefixStrip.stripFileIfNeeded(f)
        guard !SwfPrefixStrip.needsStrip(fileURL: f) else { return false }
        // ZWS 未预解压 → 视为未就绪，ensure 里会 inflate（省 WebContent LZMA 峰）
        if isZws(f) { return false }
        return true
    }

    private static func isZws(_ fileURL: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? fh.close() }
        let head = fh.readData(ofLength: 3)
        guard head.count == 3 else { return false }
        return head[0] == 0x5A && head[1] == 0x57 && head[2] == 0x53
    }

    static func ensure(
        preferMm: Bool,
        onProgress: @MainActor @escaping (String) -> Void
    ) async throws {
        sessionPreferMm = preferMm
        let rel = preferMm ? mmRel : ggRel
        let dest = localURL(for: rel)
        if isDiskReady(preferMm: preferMm) {
            await onProgress("动作包已缓存(FWS/CWS)")
            return
        }
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 磁盘已有 ZWS：只做 App 侧预解压，不再重下
        let existingSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
        if existingSize > 1_000_000 {
            _ = SwfPrefixStrip.stripFileIfNeeded(dest)
            if isZws(dest) {
                await onProgress("预解压已缓存动作包…")
                let ok = SwfZwsInflate.inflateFileIfNeeded(dest) { msg in
                    Task { @MainActor in onProgress(msg) }
                }
                if ok || !isZws(dest) {
                    let sz = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
                    await onProgress("动作包就绪 \(max(1, sz / 1024 / 1024))MB FWS")
                    return
                }
            } else if !SwfPrefixStrip.needsStrip(fileURL: dest) {
                await onProgress("动作包已缓存")
                return
            }
        }

        let url = URL(string: "https://fightimg.pet.qq.com/swf/\(rel)")!
        await onProgress("下载动作包…约 40MB，请稍候")

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 180
        cfg.timeoutIntervalForResource = 300
        let session = URLSession(configuration: cfg)
        let (tmpURL, resp) = try await session.download(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw URLError(.badServerResponse)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: tmpURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        // CDN 可能带 NUL 前缀；不剥则 Flash Loader 立刻 sal_base_err io
        if SwfPrefixStrip.stripFileIfNeeded(dest) {
            await onProgress("已剥离 CDN 前缀")
        }
        // 路线 A：App 进程 ZWS→FWS，WebContent 不再做 LZMA（~38MB+69MB 叠峰）
        await onProgress("预解压动作包（省播放器内存）…")
        let inflated = SwfZwsInflate.inflateFileIfNeeded(dest) { msg in
            Task { @MainActor in onProgress(msg) }
        }
        if !inflated, isZws(dest) {
            await onProgress("预解压失败，仍用 ZWS（可能 OOM）")
        }
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? size
        await onProgress("动作包就绪 \(max(1, finalSize / 1024 / 1024))MB\(inflated ? " FWS" : "")")
    }
}
