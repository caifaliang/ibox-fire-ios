import Foundation
import CommonCrypto

/// 对齐 Android `HfpayCrypto` / backend `_encrypt_pwd`。
enum HfpayCrypto {
    static func encryptPassword(_ pwd: String, payUuid: String) -> String {
        let keyBytes = Array(payUuid.utf8.prefix(24))
        var key = keyBytes
        while key.count < 24 { key.append(0) }
        let iv = Array("chinapnr".utf8)
        let raw = Array(pwd.utf8)
        let padLen = 8 - (raw.count % 8)
        let padded = raw + Array(repeating: UInt8(padLen), count: padLen)
        var out = [UInt8](repeating: 0, count: padded.count + 8)
        var moved: size_t = 0
        let st = key.withUnsafeBytes { kb in
            iv.withUnsafeBytes { ivb in
                padded.withUnsafeBytes { pb in
                    out.withUnsafeMutableBytes { ob in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithm3DES),
                            CCOptions(0),
                            kb.baseAddress, 24,
                            ivb.baseAddress,
                            pb.baseAddress, padded.count,
                            ob.baseAddress, out.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard st == kCCSuccess else { return Data(pwd.utf8).base64EncodedString() }
        return Data(out.prefix(moved)).base64EncodedString()
    }

    static func makeBalancePayBody(encPwd: String, randomFactor: String) -> ([String: Any], String) {
        let devInfo = #"{"devType":"2","devSysType":"H5","mobileFlag":"Y"}"#
        let sorted: [(String, String)] = [
            ("dev_info_json", devInfo),
            ("password", encPwd),
            ("random_factor", randomFactor),
        ]
        let signStr = sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        var body: [String: Any] = [:]
        for (k, v) in sorted { body[k] = v }
        return (body, hmacSha256(signStr, key: "chinapnr"))
    }

    static func hmacSha256(_ data: String, key: String) -> String {
        let keyData = Data(key.utf8)
        let msg = Data(data.utf8)
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { kb in
            msg.withUnsafeBytes { mb in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), kb.baseAddress, keyData.count, mb.baseAddress, msg.count, &out)
            }
        }
        return out.map { String(format: "%02x", $0) }.joined()
    }
}
