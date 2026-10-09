import Foundation
import Security

/// Cookie 会话持久化（Keychain），对齐 Android EncryptedSharedPreferences SessionStore。
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var cookieHeader: String = ""
    @Published private(set) var qq: String = ""

    private let service = "com.daledou.app.session"
    private let account = "cookie_header"

    private init() {
        cookieHeader = load() ?? ""
        qq = LoginURLs.extractQq(cookieHeader) ?? ""
    }

    var isLoggedIn: Bool { LoginURLs.hasRealSkey(cookieHeader) }

    func save(cookieHeader: String) {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cookieHeader = trimmed
        self.qq = LoginURLs.extractQq(trimmed) ?? ""
        persist(trimmed)
    }

    func clear() {
        cookieHeader = ""
        qq = ""
        delete()
    }

    // MARK: - Keychain

    private func persist(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func load() -> String? {
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

    private func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
