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
    /// 道聚城扫码 Cookie（access_token/openid），不覆盖大乐斗会话
    @Published private(set) var daojuCookie: String = ""

    private let service = "com.daledou.app.session"
    private let account = "cookie_header"
    private let daojuAccount = "daoju_cookie"
    private let fileName = "session_cookie.txt"
    private let daojuFileName = "daoju_cookie.txt"

    private init() {
        let loaded = load() ?? ""
        cookieHeader = loaded
        qq = LoginURLs.extractQq(loaded) ?? ""
        // 若只从文件恢复到，立刻回写 Keychain，方便本会话其它路径
        if LoginURLs.hasGameSession(loaded) {
            persistKeychain(loaded)
        }
        daojuCookie = loadDaoju() ?? ""
    }

    /// skey 或一键 OpenID 会话均可
    var isLoggedIn: Bool { LoginURLs.hasGameSession(cookieHeader) }

    var hasDaojuSession: Bool { DjcAuth.parseOAuth(daojuCookie) != nil }

    func save(cookieHeader: String) {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cookieHeader = trimmed
        self.qq = LoginURLs.extractQq(trimmed) ?? ""
        persistKeychain(trimmed)
        persistFile(trimmed)
    }

    /// 手动覆盖 QQ（道聚城兑换等）；不改 Cookie。
    func setQq(_ value: String) {
        let q = value.filter(\.isNumber)
        guard !q.isEmpty else { return }
        qq = q
    }

    func saveDaoju(_ cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        daojuCookie = trimmed
        persistKeychainValue(trimmed, account: daojuAccount)
        persistNamedFile(trimmed, name: daojuFileName)
    }

    func clearDaoju() {
        daojuCookie = ""
        deleteKeychainAccount(daojuAccount)
        deleteNamedFile(daojuFileName)
    }

    func clear() {
        cookieHeader = ""
        qq = ""
        deleteKeychain()
        deleteFile()
        // 退出大乐斗不清道聚城，对齐 Android SessionStore.clear 会 clear 全部；
        // 这里跟「logout 只清游戏」一致：道聚城单独 clearDaoju。
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

    // MARK: - 道聚城

    private func loadDaoju() -> String? {
        if let k = loadKeychainAccount(daojuAccount), DjcAuth.parseOAuth(k) != nil {
            persistNamedFile(k, name: daojuFileName)
            return k
        }
        if let f = loadNamedFile(daojuFileName), DjcAuth.parseOAuth(f) != nil {
            persistKeychainValue(f, account: daojuAccount)
            return f
        }
        return loadNamedFile(daojuFileName) ?? loadKeychainAccount(daojuAccount)
    }

    private func persistKeychainValue(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadKeychainAccount(_ account: String) -> String? {
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

    private func deleteKeychainAccount(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func supportURL(name: String) -> URL? {
        let fm = FileManager.default
        guard let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = root.appendingPathComponent("DaLedou", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private func persistNamedFile(_ value: String, name: String) {
        guard let url = supportURL(name: name) else { return }
        if value.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadNamedFile(_ name: String) -> String? {
        guard let url = supportURL(name: name),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func deleteNamedFile(_ name: String) {
        guard let url = supportURL(name: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
