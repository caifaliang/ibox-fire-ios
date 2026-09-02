import Foundation

/// 对齐 Android `prestoredCaptchas`：每个活代理预解一条极验（服务端 presale-verify 降级）。
enum PresaleCaptchas {
    static func prestored(proxies: [String], iboxToken: String, onLog: @escaping (String) -> Void) async -> [CaptchaToken] {
        guard !proxies.isEmpty else {
            onLog("无活代理，无法预存极验")
            return []
        }
        let need = proxies.count
        let concurrency = min(32, max(16, (need + 2) / 3))
        onLog("极验预存 目标\(need)/\(proxies.count)代理 并发\(concurrency) …")
        let api = ApiRepository()
        var queue = proxies
        let lock = NSLock()
        var results: [CaptchaToken] = []
        var ok = 0
        var fail = 0

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrency {
                group.addTask {
                    while true {
                        let px: String? = lock.withLock {
                            queue.isEmpty ? nil : queue.removeFirst()
                        }
                        guard let proxy = px else { break }
                        do {
                            let cap = try await api.presaleVerify(iboxToken: iboxToken, preferredProxy: proxy)
                            lock.withLock {
                                results.append(cap)
                                ok += 1
                                if ok == 1 || ok % 5 == 0 || ok >= need {
                                    onLog("预存OK #\(ok)/\(need)")
                                }
                            }
                        } catch {
                            lock.withLock {
                                fail += 1
                                let n = fail
                                if n <= 3 || n % 5 == 0 {
                                    let tag = ProxyPool.normalizeProxyUrl(proxy)
                                        .replacingOccurrences(of: "http://", with: "")
                                        .replacingOccurrences(of: "https://", with: "")
                                    onLog("极验失败(\(String(tag.prefix(22)))): \(error.localizedDescription.prefix(50))")
                                }
                            }
                        }
                    }
                }
            }
        }
        onLog("极验预存成功 \(results.count)/\(need) 失败\(fail)")
        return results
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
