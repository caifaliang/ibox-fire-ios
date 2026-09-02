import Foundation

/// 带代理账号密码的 URLSession，避免 iOS 弹出「需要代理鉴定」系统对话框。
final class ProxyURLSession: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let credentials: (user: String, pass: String)?
    private let session: URLSession

    init(proxyLine: String?, timeout: TimeInterval = 12) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 5
        var creds: (String, String)?
        if let px = proxyLine?.trimmingCharacters(in: .whitespacesAndNewlines), !px.isEmpty,
           let ep = ProxyPool.parseEndpoint(ProxyPool.normalizeProxyUrl(px)) {
            var dict: [AnyHashable: Any] = [
                "HTTPEnable": 1, "HTTPProxy": ep.host, "HTTPPort": ep.port,
                "HTTPSEnable": 1, "HTTPSProxy": ep.host, "HTTPSPort": ep.port,
            ]
            if let u = ep.user, let p = ep.pass {
                dict["HTTPProxyUsername"] = u
                dict["HTTPProxyPassword"] = p
                creds = (u, p)
            }
            cfg.connectionProxyDictionary = dict
        }
        credentials = creds
        super.init()
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest,
           let cred = credentials {
            completionHandler(.useCredential, URLCredential(user: cred.0, password: cred.1, persistence: .forSession))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
