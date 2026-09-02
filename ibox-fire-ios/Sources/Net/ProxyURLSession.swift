import Foundation
import CFNetwork

/// 带代理账号密码的 URLSession，避免 iOS 弹出「需要代理鉴定」系统对话框。
final class ProxyURLSession: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let credentials: (user: String, pass: String)?
    private let configuration: URLSessionConfiguration
    private lazy var session: URLSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    init(proxyLine: String?, timeout: TimeInterval = 12) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 5
        cfg.waitsForConnectivity = false
        var creds: (String, String)?
        if let px = proxyLine?.trimmingCharacters(in: .whitespacesAndNewlines), !px.isEmpty,
           let ep = ProxyPool.parseEndpoint(ProxyPool.normalizeProxyUrl(px)) {
            var dict: [AnyHashable: Any] = [
                kCFProxyTypeKey as String: kCFProxyTypeHTTP,
                kCFProxyHostNameKey as String: ep.host,
                kCFProxyPortNumberKey as String: ep.port,
                "HTTPEnable": 1, "HTTPProxy": ep.host, "HTTPPort": ep.port,
                "HTTPSEnable": 1, "HTTPSProxy": ep.host, "HTTPSPort": ep.port,
            ]
            if let u = ep.user, let p = ep.pass {
                dict[kCFProxyUsernameKey as String] = u
                dict[kCFProxyPasswordKey as String] = p
                dict["HTTPProxyUsername"] = u
                dict["HTTPProxyPassword"] = p
                creds = (u, p)
            }
            cfg.connectionProxyDictionary = dict
        }
        credentials = creds
        configuration = cfg
        super.init()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        if let cred = credentials {
            let token = Data("\(cred.0):\(cred.1)".utf8).base64EncodedString()
            req.setValue("Basic \(token)", forHTTPHeaderField: "Proxy-Authorization")
        }
        return try await session.data(for: req)
    }

    private func answerChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        let isProxy = method == NSURLAuthenticationMethodHTTPProxy
            || method == NSURLAuthenticationMethodHTTPBasic
            || method == NSURLAuthenticationMethodHTTPDigest
        if isProxy, let cred = credentials {
            completionHandler(.useCredential, URLCredential(user: cred.0, password: cred.1, persistence: .forSession))
            return
        }
        if method == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.rejectProtectionSpace, nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        answerChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        answerChallenge(challenge, completionHandler: completionHandler)
    }
}
