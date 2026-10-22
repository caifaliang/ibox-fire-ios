import Foundation

/** 对齐 announce_lock._norm_col_name — 统一中间点/全角空格等。 */
enum AnnounceNameNorm {
    private static let dotChars: Set<Character> = ["·", "•", "･", "‧", "・", "．", "∙", "⋅"]

    static func norm(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
        for ch in dotChars {
            t = t.replacingOccurrences(of: String(ch), with: "·")
        }
        t = t.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
        return t
    }
}
