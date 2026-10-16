import Foundation

/// 从当前游戏页 URL 取出正在查看的鹅 QQ（B_UID / puin 等）。
/// B_UID=0 是首页占位，不算。
enum QueryPageUin {
    private static let uinPattern = try! NSRegularExpression(pattern: #"^\d{5,12}$"#)
    private static let paramPattern = try! NSRegularExpression(
        pattern: #"(?:^|[?&#])(B_UID|puin|oppuin|target_uin|other)=([^&#]*)"#,
        options: [.caseInsensitive]
    )

    static func fromUrl(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        let src = url.replacingOccurrences(of: "&amp;", with: "&")
        let range = NSRange(src.startIndex..<src.endIndex, in: src)
        var matches: [(String, String)] = []
        paramPattern.enumerateMatches(in: src, range: range) { m, _, _ in
            guard let m, m.numberOfRanges >= 3,
                  let kR = Range(m.range(at: 1), in: src),
                  let vR = Range(m.range(at: 2), in: src) else { return }
            matches.append((String(src[kR]), String(src[vR]).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let keys = ["B_UID", "puin", "oppuin", "target_uin", "other"]
        for key in keys {
            guard let raw = matches.first(where: { $0.0.caseInsensitiveCompare(key) == .orderedSame })?.1 else { continue }
            if isValidUin(raw) { return raw }
        }
        return nil
    }

    private static func isValidUin(_ raw: String) -> Bool {
        guard raw != "0" else { return false }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return uinPattern.firstMatch(in: raw, range: range) != nil
    }
}
