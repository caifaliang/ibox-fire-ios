import Foundation

/// 书签：对齐 Android DiyUrlFeatureScreen（urls 多行）
@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()
    private let key = "daledou.feature.shuqian.urls"

    @Published var urlsText: String {
        didSet { UserDefaults.standard.set(urlsText, forKey: key) }
    }

    var lines: [String] {
        urlsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private init() {
        urlsText = UserDefaults.standard.string(forKey: key) ?? ""
    }
}
