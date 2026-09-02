import Foundation

enum Geetest4Solver {
    static let localEnabled = false

    static func solveOnce(iboxToken: String, preferredProxy: String = "") async throws -> CaptchaToken {
        if localEnabled {
            throw NSError(domain: "geetest", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地ONNX求解尚未接入"])
        }
        guard !JwtUtil.normalize(iboxToken).isEmpty else {
            throw NSError(domain: "geetest", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少 iBox token"])
        }
        return try await ApiRepository().presaleVerify(iboxToken: iboxToken, preferredProxy: preferredProxy)
    }
}
