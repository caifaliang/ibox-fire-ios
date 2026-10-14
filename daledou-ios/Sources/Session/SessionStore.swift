import Foundation
import Security

/// Cookie 会话持久化。
/// Keychain 在免费重签换证书后常读不到；同时写入 Application Support，
/// 同 bundle 覆盖安装后可自动恢复登录（无需再扫码）。
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var cookieHeader: String = ""
    @Published private(set) var qq: String = ""

    private let service = "com.daledou.app.session"
    private let account = "cookie_header"
    private let fileName = "session_cookie.txt"

    private init() {
        let loaded = load() ?? ""
        cookieHeader = loaded
        qq = LoginURLs.extractQq(loaded) ?? ""
        // 若只从文件恢复到，立刻回写 Keychain，方便本会话其它路径
        if LoginURLs.hasGameSession(loaded) {
            persistKeychain(loaded)
        }
    }

    /// skey 或一键 OpenID 会话均可
    var isLoggedIn: Bool { LoginURLs.hasGameSession(cookieHeader) }

    func save(cookieHeader: String) {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cookieHeader = trimmed
        self.qq = LoginURLs.extractQq(trimmed) ?? ""
        persistKeychain(trimmed)
        persistFile(trimmed)
    }

    func clear() {
        cookieHeader = ""
        qq = ""
        deleteKeychain()
        deleteFile()
    }

    // MARK: - Load (Keychain → file)

    private func load() -> String? {
        if let k = loadKeychain(), LoginURLs.hasGameSession(k) {
            persistFile(k)
            return k
        }
        if let f = loadFile(), LoginURLs.hasGameSession(f) {
            return f
        }
        return loadFile() ?? loadKeychain()
    }

    // MARK: - Keychain

    private func persistKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Application Support file (survives same-bundle upgrade)

    private var fileURL: URL? {
        let fm = FileManager.default
        guard let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = root.appendingPathComponent("DaLedou", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private func persistFile(_ value: String) {
        guard let url = fileURL else { return }
        if value.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadFile() -> String? {
        guard let url = fileURL,
              let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func deleteFile() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
