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
        return !SwfPrefixStrip.needsStrip(fileURL: f)
    }

    static func ensure(
        preferMm: Bool,
        onProgress: @MainActor @escaping (String) -> Void
    ) async throws {
        sessionPreferMm = preferMm
        let rel = preferMm ? mmRel : ggRel
        let dest = localURL(for: rel)
        if isDiskReady(preferMm: preferMm) {
            await onProgress("动作包已缓存")
            return
        }
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
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
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? size
        await onProgress("动作包就绪 \(max(1, finalSize / 1024 / 1024))MB")
    }
}
