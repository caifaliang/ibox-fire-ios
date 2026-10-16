import Foundation
import Security
import CryptoKit
import CommonCrypto
import UIKit

/// 真源：`DjcAuth` — 掌上道聚城鉴权（access_token/openid + sDjcSign）。
enum DjcAuth {
    static let appVersion = "170"
    static let versionName = "v4.9.4.0"
    private static let aesKey = "se35d32s63r7m23m"

    struct OAuth: Equatable {
        let accessToken: String
        let openId: String
        let appId: String
    }

    struct Session {
        let oauth: OAuth
        let deviceId: String
        let cookieHeader: String
        let userAgent: String
    }

    static func parseOAuth(_ cookie: String?) -> OAuth? {
        guard let cookie, !cookie.isEmpty else { return nil }
        func pick(_ name: String) -> String? {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"(?:^|[;&?#\s])\#(escaped)=([^;&?#\s]+)"#,
                #""\#(escaped)"\s*:\s*"([^"]+)""#,
            ]
            for p in patterns {
                guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
                      let m = re.firstMatch(in: cookie, range: NSRange(cookie.startIndex..., in: cookie)),
                      m.numberOfRanges > 1,
                      let r = Range(m.range(at: 1), in: cookie)
                else { continue }
                var value = String(cookie[r])
                if value.contains("%"),
                   let decoded = value.removingPercentEncoding,
                   !decoded.isEmpty
                {
                    value = decoded
                }
                if !value.isEmpty { return value }
            }
            return nil
        }
        guard let access = pick("access_token"), access.count >= 16,
              let openId = pick("openid"), openId.count >= 8
        else { return nil }
        let appId = pick("appid") ?? pick("login_appid") ?? "101491592"
        return OAuth(accessToken: access, openId: openId, appId: appId)
    }

    static func compactCookie(from oauth: OAuth) -> String {
        "access_token=\(oauth.accessToken); openid=\(oauth.openId); appid=\(oauth.appId)"
    }

    static func deviceId() -> String {
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? "daledou"
        let once = md5Hex(raw)
        return once + md5Hex(once)
    }

    static func pTk(_ accessToken: String) -> Int {
        guard accessToken.count >= 32 else { return 0 }
        let start = accessToken.index(accessToken.startIndex, offsetBy: 22)
        let end = accessToken.index(accessToken.startIndex, offsetBy: 32)
        let chars = Array(accessToken[start..<end])
        var h: Int32 = 5381
        for ch in chars {
            let code = Int32(ch.unicodeScalars.first?.value ?? 0)
            let shifted = h &<< 5
            h &+= (shifted & Int32.max) &+ code
        }
        return Int(h & Int32.max)
    }

    static func requestId(_ deviceId: String) -> String {
        "\(deviceId)_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 0..<1000))"
    }

    static func sDjcSign(openId: String, deviceId: String) -> String {
        let plain = "\(openId)+\(deviceId)+\(Int(Date().timeIntervalSince1970 * 1000))+\(appVersion)"
        guard let aes = aesEcbEncrypt(Data(plain.utf8), key: aesKey),
              let rsa = rsaEncrypt(aes)
        else { return "" }
        return rsa.map { String(format: "%02x", $0) }.joined()
    }

    static func buildSession(rawCookie: String?) -> Session? {
        guard let oauth = parseOAuth(rawCookie) else { return nil }
        let did = deviceId()
        let cookie =
            "djc_appSource=android; djc_appVersion=\(appVersion); acctype=qc; appid=\(oauth.appId); "
            + "openid=\(oauth.openId); access_token=\(oauth.accessToken); login_appid=\(oauth.appId)"
        let ua =
            "TencentDaojucheng=\(versionName)&appSource=android&appVersion=\(appVersion)&ch=10000"
            + "&sDeviceID=\(did)&firmwareVersion=\(UIDevice.current.systemVersion)"
            + "&phoneBrand=Apple&phoneVersion=\(UIDevice.current.model)"
            + "&sVersionName=\(versionName)&plNo=181"
        return Session(oauth: oauth, deviceId: did, cookieHeader: cookie, userAgent: ua)
    }

    // MARK: - crypto

    private static func aesEcbEncrypt(_ data: Data, key: String) -> Data? {
        let keyData = Data(key.utf8)
        let block = kCCBlockSizeAES128
        var outLength = 0
        var out = Data(count: data.count + block)
        let outCap = out.count
        let status = out.withUnsafeMutableBytes { outBuf in
            data.withUnsafeBytes { inBuf in
                keyData.withUnsafeBytes { keyBuf in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBuf.baseAddress, keyData.count,
                        nil,
                        inBuf.baseAddress, data.count,
                        outBuf.baseAddress, outCap,
                        &outLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = outLength
        return out
    }

    private static func rsaEncrypt(_ data: Data) -> Data? {
        guard let key = loadPublicKey() else { return nil }
        var error: Unmanaged<CFError>?
        guard let sealed = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            data as CFData,
            &error
        ) as Data?
        else { return nil }
        return sealed
    }

    private static func loadPublicKey() -> SecKey? {
        guard let url = Bundle.main.url(forResource: "sss", withExtension: "der"),
              let der = try? Data(contentsOf: url)
        else { return nil }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error)
    }

    private static func md5Hex(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
