import Foundation

/// 对齐 Android prestoredCaptchas：iOS 无本地 ONNX 时走网站 presale-verify（服务器代理池解极验）。
enum PresaleCaptchas {
    static func prestored(proxies: [String], iboxToken: String, onLog: @escaping (String) -> Void) async -> [CaptchaToken] {
        let need = max(1, proxies.count)
        let concurrency = min(16, need)
        onLog("极验预存 目标\(need) 并发\(concurrency)（网站代理池）…")
        let api = ApiRepository()
        var results: [CaptchaToken] = []
        let lock = NSLock()
        var ok = 0, fail = 0

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrency {
                group.addTask {
                    while true {
                        let shouldContinue: Bool = lock.withLock {
                            if results.count >= need { return false }
                            return true
                        }
                        guard shouldContinue else { break }
                        do {
                            // 不传用户代理：由服务器 rotating pool 访问极验三域名，避免代理无法连 gsensebot
                            let cap = try await api.presaleVerify(iboxToken: iboxToken, preferredProxy: "")
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
                                    onLog("极验失败: \(error.localizedDescription.prefix(60))")
                                }
                            }
                            try? await Task.sleep(nanoseconds: 200_000_000)
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
