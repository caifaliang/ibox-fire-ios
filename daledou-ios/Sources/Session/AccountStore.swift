import Foundation

struct SavedAccount: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var qq: String?
    var cookie: String
}

/// 本机多账号 Cookie（对齐 Android AccountStore；不上传）。
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var accounts: [SavedAccount] = []

    private let fileName = "saved_accounts.json"

    private init() {
        accounts = load()
    }

    func refresh() {
        accounts = load()
    }

    @discardableResult
    func save(_ account: SavedAccount) -> SavedAccount {
        var next = accounts.filter { existing in
            if existing.id == account.id { return false }
            if let q = account.qq, !q.isEmpty, existing.qq == q { return false }
            return true
        }
        next.append(account)
        accounts = next
        persist(next)
        return account
    }

    func delete(id: String) {
        let next = accounts.filter { $0.id != id }
        accounts = next
        persist(next)
    }

    @discardableResult
    func saveCurrent(cookie: String, qq: String?, name: String?) -> SavedAccount? {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LoginURLs.hasGameSession(trimmed) else { return nil }
        let q = qq?.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "QQ\(q?.isEmpty == false ? q! : "?")"
        let account = SavedAccount(
            id: UUID().uuidString,
            name: display,
            qq: (q?.isEmpty == false) ? q : LoginURLs.extractQq(trimmed),
            cookie: trimmed
        )
        return save(account)
    }

    // MARK: - Persistence

    private var fileURL: URL? {
        let fm = FileManager.default
        guard let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = root.appendingPathComponent("DaLedou", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private func load() -> [SavedAccount] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SavedAccount].self, from: data) else {
            return []
        }
        return list
    }

    private func persist(_ list: [SavedAccount]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
