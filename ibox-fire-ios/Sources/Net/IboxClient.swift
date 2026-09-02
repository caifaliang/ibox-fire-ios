import Foundation

enum DeviceIdMode {
    case random
    case stableMD5
    case hash
}

/// 对齐 Android `IboxClient`。
final class IboxClient: @unchecked Sendable {
    private let host = "https://sail-api.ibox.art"
    private let auth: String
    let deviceId: String
    let modeLabel: String
    private let http: ProxyURLSession

    init(
        token: String,
        proxyLine: String? = nil,
        connectMs: Double = 6_000,
        readMs: Double = 8_000,
        deviceIdMode: DeviceIdMode = .random
    ) {
        let raw = JwtUtil.normalize(token)
        self.auth = JwtUtil.bearer(raw)
        switch deviceIdMode {
        case .random:
            deviceId = UUID().uuidString.lowercased()
            modeLabel = "随机UUID"
        case .stableMD5:
            deviceId = Self.makeDeviceId(raw)
            modeLabel = "稳定MD5"
        case .hash:
            deviceId = Self.hashDeviceId(raw)
            modeLabel = "Hash派生"
        }
        http = ProxyURLSession(proxyLine: proxyLine, timeout: readMs / 1000.0)
    }

    /// 对齐 backend `_make_device_id` / Android `makeDeviceId`
    static func makeDeviceId(_ token: String) -> String {
        let t = JwtUtil.normalize(token).isEmpty ? "ibox" : JwtUtil.normalize(token)
        let m = md5Hex(t)
        let a = String(m.prefix(12))
        let b = String(m.dropFirst(12).prefix(4))
        let c = String(m.dropFirst(16).prefix(4))
        let d = String(m.dropFirst(20).prefix(4))
        let e = String(m.dropFirst(24).prefix(8))
        return "\(a)-\(b)-5\(c)-8\(d)-\(e)"
    }

    static func hashDeviceId(_ token: String) -> String {
        let raw = JwtUtil.normalize(token)
        // Best-effort; Kotlin Int.hashCode ≠ Swift. Prefer STABLE_MD5 in production.
        var hasher = Hasher()
        hasher.combine(raw)
        let h1 = UInt32(bitPattern: Int32(truncatingIfNeeded: hasher.finalize()))
        let h2 = md5Hex(String(raw.prefix(16)))
        let h3 = md5Hex(String(raw.suffix(16)))
        let parts = [
            String(h1, radix: 16).leftPad(to: 8, with: "0"),
            String(raw.count, radix: 16).leftPad(to: 8, with: "0"),
            String(h2.prefix(8)),
            String(h3.prefix(8))
        ].joined()
        let p = parts.padding(toLength: 32, withPad: "0", startingAt: 0)
        return "\(p.prefix(8))-\(p.dropFirst(8).prefix(4))-\(p.dropFirst(12).prefix(4))-\(p.dropFirst(16).prefix(4))-\(p.dropFirst(20).prefix(12))"
    }

    private func headerMap() -> [String: String] {
        [
            "Authorization": auth,
            "platform-type": "1",
            "channel": "website",
            "device-id": deviceId,
            "msg-id": UUID().uuidString.lowercased() + "_android",
            "app-version-number": "30002",
            "app-version": "3.0.2",
            "Content-Type": "application/json;charset=UTF-8",
            "User-Agent": "Dart/3.11 (dart:io)",
            "accept": "application/json"
        ]
    }

    func get(_ path: String) async -> [String: Any] {
        let p = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: host + p) else { return ["code": -1, "message": "bad url"] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        headerMap().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        return await exec(req)
    }

    func postJson(_ path: String, body: [String: Any]) async -> [String: Any] {
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let plain = String(data: data, encoding: .utf8) ?? "{}"
            let enc = try IboxCrypto.encryptBody(plain)
            return await postRaw(path, encryptedBody: enc)
        } catch {
            return ["code": -1, "message": error.localizedDescription]
        }
    }

    func postRaw(_ path: String, encryptedBody: String) async -> [String: Any] {
        let p = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: host + p) else { return ["code": -1, "message": "bad url"] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(encryptedBody.utf8)
        headerMap().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        return await exec(req)
    }

    private func exec(_ req: URLRequest) async -> [String: Any] {
        do {
            let (data, resp) = try await http.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 || status == 429 {
                return ["code": status, "message": "HTTP \(status)"]
            }
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty { return ["code": -1, "message": "empty"] }
            if text.hasPrefix("<") { return ["code": status, "message": "HTML \(status)"] }
            guard var obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                return ["code": -1, "message": String(text.prefix(60))]
            }
            if obj["encryptKey"] != nil {
                let plain = try IboxCrypto.decryptResponse(text)
                obj = (try JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any]) ?? obj
            }
            return obj
        } catch {
            return ["code": -1, "message": error.localizedDescription]
        }
    }
}

extension String {
    func leftPad(to len: Int, with ch: Character) -> String {
        if count >= len { return self }
        return String(repeating: String(ch), count: len - count) + self
    }
}
