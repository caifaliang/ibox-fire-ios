import Foundation

/// 本地极验占位：一期/二期走服务端 `presaleVerify`；三期可替换为 ONNX 求解。
enum Geetest4Solver {
    static let localEnabled = false

    static func solveOnce(preferredProxy: String = "") async throws -> CaptchaToken {
        if localEnabled {
            throw NSError(domain: "geetest", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地ONNX求解尚未接入"])
        }
        return try await ApiRepository().presaleVerify(iboxToken: "", preferredProxy: preferredProxy)
    }
}
