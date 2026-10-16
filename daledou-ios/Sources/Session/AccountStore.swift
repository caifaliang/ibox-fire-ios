import Foundation

/// 真源：`AccountStore.kt` — 本机多账号 Cookie 令牌。
struct SavedAccount: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var qq: String?
    var cookie: String
    var daojuCookie: String?
}

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var accounts: [SavedAccount] = []

    private let fileName = "saved_accounts.json"

    private init() {
        accounts = load()
    }

    func list() -> [SavedAccount] { accounts }

    @discardableResult
    func saveCurrent(name: String?) -> SavedAccount? {
        let session = SessionStore.shared
        let cookie = session.cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LoginURLs.hasGameSession(cookie) else { return nil }
        let qq = session.qq.isEmpty ? LoginURLs.extractQq(cookie) : session.qq
        let account = SavedAccount(
            id: UUID().uuidString,
            name: {
                let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return n.isEmpty ? "QQ\(qq ?? "?")" : n
            }(),
            qq: qq,
            cookie: cookie,
            daojuCookie: session.daojuCookie.isEmpty ? nil : session.daojuCookie
        )
        save(account)
        return account
    }

    func save(_ account: SavedAccount) {
        var next = accounts.filter {
            $0.id != account.id && !($0.qq != nil && $0.qq == account.qq)
        }
        next.append(account)
        write(next)
    }

    func delete(id: String) {
        write(accounts.filter { $0.id != id })
    }

    func apply(_ account: SavedAccount) {
        let session = SessionStore.shared
        session.save(cookieHeader: account.cookie)
        if let d = account.daojuCookie, !d.isEmpty {
            session.saveDaoju(d)
        } else {
            session.clearDaoju()
        }
        if let qq = account.qq, !qq.isEmpty {
            session.setQq(qq)
        }
    }

    private func write(_ list: [SavedAccount]) {
        accounts = list
        guard let url = supportURL(),
              let data = try? JSONEncoder().encode(list)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func load() -> [SavedAccount] {
        guard let url = supportURL(),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SavedAccount].self, from: data)
        else { return [] }
        return list
    }

    private func supportURL() -> URL? {
        let fm = FileManager.default
        guard let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = root.appendingPathComponent("DaLedou", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
