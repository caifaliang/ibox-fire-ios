import Foundation
import Security

/// 与 Android `IboxCrypto` / backend ibox3 兼容：RSA-PKCS1 + AES-ECB。
enum IboxCrypto {
    private static let rsaPkcs8B64 =
        "MIICdAIBADANBgkqhkiG9w0BAQEFAASCAl4wggJaAgEAAoGBAJhMIGvHAhhO8qa+DcLb8U+b4ziyZ14pciIE40JfM47F8d06AZG95rUu2gFH+Qng6l4+wX/YI3Le9Ln3VeFjeKlQBqk0mpNQcZ/TUvhjr40p2LJQLZVysusQSMAa4KxYfzKJxxDpsER0UkNfRv5VdFE9VCaRqBKdW7lMqrdcacxxAgEDAoGAGWIFZ0vVrrfTG8pXoHn9jUSl3shmj7GTBat7NbqIl8uoT4mq7Z+mc4fPADapgaV8ZQp1lU6wkyUoyak4+uXpcUtqqX3LbBRScLv3LcCePLYNtsGldoiqqDywtzzkVZDtqyyE0nZ+Bs10/o+OF7Ye8U0a3jvJYjzObb7xppbCrlMCQQDQ0CVT6jdi1LqNC44+E6cey6+HULLl7HFAN1TBfXUEjsIm3xVUDTkXV9vWqXy6UmOe7HXP4HwBIR6nptHKfLiFAkEAuraK7evTc65A3nxXoeZ5xrq6PvwbWMaIY+0f7Ak17l5tV8sMzq7ijDxwK0jzVmhFz8Z7Ww9JL2QIK1n+CVz9/QJBAIs1bjfxekHjJwiyXtQNGhSHylo1zJlIS4Ak4yuo+K20gW8/Y41eJg+P5+Rw/dGMQmny+TVAUqtracUZ4TGoewMCQHx5sfPyjPfJgJRS5RaZpoR8fCn9Z5CEWu1Iv/Kwzp7pnjqHXd8fQbLS9XIwojma2TUu/Odfhh+YBXI7/rDoqVMCQBUYFJvc5M8WnN3uOqxP11WwUSTKZpDugMiD63/bDcdESAcutglx5RMhszXFyfMr7K22Zc7F8BpY2HCzcRWp65o="

    private static var privateKey: SecKey = {
        guard let der = Data(base64Encoded: rsaPkcs8B64) else {
            fatalError("RSA key decode failed")
        }
        // PKCS8 → strip to PKCS1 if needed
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 1024
        ]
        var error: Unmanaged<CFError>?
        if let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error) {
            return key
        }
        // Fallback: try extracting PKCS1 from PKCS8 (skip 26-byte typical header for this key)
        let pkcs1 = extractPKCS1(fromPKCS8: der)
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            fatalError("SecKeyCreate failed: \(error!.takeRetainedValue())")
        }
        return key
    }()

    private static var publicKey: SecKey {
        guard let pub = SecKeyCopyPublicKey(privateKey) else {
            fatalError("public key missing")
        }
        return pub
    }

    private static func extractPKCS1(fromPKCS8 data: Data) -> Data {
        // Simple DER walk: find OCTET STRING containing RSAPrivateKey
        var i = 0
        let bytes = [UInt8](data)
        while i + 2 < bytes.count {
            if bytes[i] == 0x04 { // OCTET STRING
                var len = 0
                var hdr = 1
                if bytes[i + 1] & 0x80 == 0 {
                    len = Int(bytes[i + 1]); hdr = 2
                } else {
                    let n = Int(bytes[i + 1] & 0x7f)
                    hdr = 2 + n
                    for j in 0..<n { len = (len << 8) | Int(bytes[i + 2 + j]) }
                }
                let start = i + hdr
                if start + len <= bytes.count, bytes[start] == 0x30 {
                    return Data(bytes[start..<(start + len)])
                }
            }
            i += 1
        }
        return data
    }

    private static func genAesKey() -> String {
        var buf = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return buf.map { String(format: "%02x", $0) }.joined()
    }

    private static func aesECB(_ data: Data, key: String, encrypt: Bool) -> Data {
        let keyData = Data(key.utf8)
        let outLength = data.count + kCCBlockSizeAES128
        var out = Data(count: outLength)
        var moved: size_t = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes.baseAddress, keyData.count,
                        nil,
                        inBytes.baseAddress, data.count,
                        outBytes.baseAddress, outLength,
                        &moved
                    )
                }
            }
        }
        precondition(status == kCCSuccess, "AES failed \(status)")
        return out.prefix(moved)
    }

    private static func rsaEncrypt(_ plain: String) -> String {
        let data = Data(plain.utf8)
        var error: Unmanaged<CFError>?
        guard let enc = SecKeyCreateEncryptedData(
            publicKey, .pkcs1, data as CFData, &error
        ) as Data? else {
            fatalError("rsa encrypt: \(String(describing: error?.takeRetainedValue()))")
        }
        return enc.base64EncodedString()
    }

    private static func rsaDecrypt(_ b64: String) -> String {
        guard let raw = Data(base64Encoded: b64) else { return "" }
        var error: Unmanaged<CFError>?
        guard let dec = SecKeyCreateDecryptedData(
            privateKey, .pkcs1, raw as CFData, &error
        ) as Data? else {
            return ""
        }
        return String(data: dec, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func encryptBody(_ plainJson: String) throws -> String {
        guard let _ = try? JSONSerialization.jsonObject(with: Data(plainJson.utf8)) else {
            throw NSError(domain: "IboxCrypto", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid json"])
        }
        let aesKey = genAesKey()
        let data = aesECB(Data(plainJson.utf8), key: aesKey, encrypt: true).base64EncodedString()
        let encryptKey = rsaEncrypt(aesKey)
        let obj: [String: String] = ["encryptKey": encryptKey, "data": data]
        let out = try JSONSerialization.data(withJSONObject: obj)
        return String(data: out, encoding: .utf8) ?? "{}"
    }

    static func decryptResponse(_ encryptedJson: String) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: Data(encryptedJson.utf8)) as? [String: Any],
              let ek = root["encryptKey"] as? String,
              let data = root["data"] as? String,
              let raw = Data(base64Encoded: data) else {
            throw NSError(domain: "IboxCrypto", code: 2, userInfo: [NSLocalizedDescriptionKey: "bad envelope"])
        }
        let aesKey = rsaDecrypt(ek)
        let plain = aesECB(raw, key: aesKey, encrypt: false)
        return String(data: plain, encoding: .utf8) ?? ""
    }
}
