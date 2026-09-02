import Foundation

struct FireConfig {
    var token: String
    var syntheticId: Int64
    var syntheticNum: Int
    var albumIds: [Int64]
    var fireAtEpochSec: Int64
    var workers: Int
    var proxies: [String]
    var earlyS: Double = 3.0
    var peakAfterS: Double = 4.0
    var durationS: Double = 60.0
    var peakReadMs: Double = 1800
}

final class FireEngine: @unchecked Sendable {
    private let cfg: FireConfig
    private let onLog: (String) -> Void
    private var stop = false
    private var success = 0
    private var sent = 0

    init(cfg: FireConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async throws -> Int {
        guard let uid = JwtUtil.uid(cfg.token) else { throw NSError(domain: "fire", code: 1, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"]) }
        let now0 = Date().timeIntervalSince1970
        let late = now0 - Double(cfg.fireAtEpochSec)
        if late > 10 { throw NSError(domain: "fire", code: 2, userInfo: [NSLocalizedDescriptionKey: "开火时间已过 \(Int(late))s"]) }
        if cfg.proxies.isEmpty { throw NSError(domain: "fire", code: 3, userInfo: [NSLocalizedDescriptionKey: "无存活代理"]) }

        let nPx = max(1, cfg.proxies.count)
        let workers = min(max(1, cfg.workers), min(20, nPx))
        onLog("引擎启动 uid=\(uid) 合成ID=\(cfg.syntheticId) x\(cfg.syntheticNum) workers=\(workers)")

        let plainObj: [String: Any] = [
            "syntheticId": cfg.syntheticId,
            "syntheticNum": cfg.syntheticNum,
            "preferentialAlbumIds": cfg.albumIds
        ]
        let plain = String(data: try JSONSerialization.data(withJSONObject: plainObj), encoding: .utf8) ?? "{}"
        let encBody = try IboxCrypto.encryptBody(plain)
        let urlStr = "https://sail-api.ibox.art/synthesis-service/synthetic/center/confirm?uid=\(uid)"
        onLog("请求体已预加密 | 纯代理 \(cfg.proxies.count) 条")

        let deviceId = IboxClient.makeDeviceId(cfg.token)
        let auth = JwtUtil.bearer(cfg.token)
        let fireStart = Double(cfg.fireAtEpochSec) - cfg.earlyS
        let warmStart = fireStart - 5
        var now = Date().timeIntervalSince1970
        if now < warmStart {
            onLog(String(format: "等待预热窗口 %.1fs", warmStart - now))
            await waitUntil(warmStart)
        }
        onLog("轻预热 \(nPx)×1/IP...")
        await withTaskGroup(of: Void.self) { group in
            for px in cfg.proxies {
                group.addTask {
                    let c = IboxClient(token: self.cfg.token, proxyLine: px, connectMs: 800, readMs: self.cfg.peakReadMs, deviceIdMode: .stableMD5)
                    _ = await c.get("/public-service/markets?pageNo=1&pageSize=1&segmentId=-1")
                }
            }
        }
        now = Date().timeIntervalSince1970
        if now < fireStart {
            onLog(String(format: "等待开火 T-%.1fs", fireStart - now))
            await waitUntil(fireStart)
        }

        let peakEnd = Double(cfg.fireAtEpochSec) + cfg.peakAfterS
        let deadline = Double(cfg.fireAtEpochSec) + cfg.durationS
        let drift = Date().timeIntervalSince1970 - Double(cfg.fireAtEpochSec)
        onLog(String(format: "开火! 相对定点%+.3fs | 峰值至+%.0fs", drift, cfg.peakAfterS))

        let lock = NSLock()
        var cooldownUntil = Array(repeating: 0.0, count: nPx)
        var rr = 0

        await withTaskGroup(of: Void.self) { group in
            for wid in 0..<workers {
                group.addTask {
                    var first = false
                    var localRr = wid
                    while !self.stop {
                        let nowSec = Date().timeIntervalSince1970
                        if nowSec >= deadline { break }
                        lock.lock(); let sc = self.success; lock.unlock()
                        if sc >= self.cfg.syntheticNum { break }
                        let inPeak = nowSec < peakEnd
                        let nowMs = nowSec * 1000
                        var idx: Int?
                        lock.lock()
                        for _ in 0..<nPx {
                            let i = abs(rr + localRr) % nPx
                            rr += 1; localRr += 1
                            if cooldownUntil[i] <= nowMs { idx = i; break }
                        }
                        lock.unlock()
                        guard let pxI = idx else {
                            try? await Task.sleep(nanoseconds: 20_000_000)
                            continue
                        }
                        let t0 = Date().timeIntervalSince1970 * 1000
                        let client = IboxClient(token: self.cfg.token, proxyLine: self.cfg.proxies[pxI], connectMs: 800, readMs: self.cfg.peakReadMs, deviceIdMode: .stableMD5)
                        // post raw with stable headers already in client; force device via stable mode
                        _ = deviceId; _ = auth; _ = urlStr
                        let r = await client.postRaw("/synthesis-service/synthetic/center/confirm?uid=\(uid)", encryptedBody: encBody)
                        let ms = Int(Date().timeIntervalSince1970 * 1000 - t0)
                        lock.lock(); self.sent += 1; let n = self.sent; lock.unlock()
                        let code = JSONX.code(r)
                        let msg = JSONX.message(r)
                        if code == 429 || msg.contains("过于频繁") {
                            if !inPeak {
                                lock.lock(); cooldownUntil[pxI] = nowMs + 1500; lock.unlock()
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                            }
                        }
                        if !first {
                            first = true
                            let d = Date().timeIntervalSince1970 - Double(self.cfg.fireAtEpochSec)
                            self.onLog("首包 \(ms)ms code=\(code) \(msg.prefix(40)) 相对定点\(String(format: "%+.3f", d))s")
                        }
                        if code == 0 && !msg.contains("超过") {
                            lock.lock(); self.success += 1; let sc2 = self.success; lock.unlock()
                            self.onLog("OK #\(sc2) \(ms)ms \(msg)")
                            self.stop = true
                            return
                        }
                        self.onLog("#\(n) \(ms)ms code=\(code) \(msg.prefix(60))")
                        if !inPeak { try? await Task.sleep(nanoseconds: 100_000_000) }
                    }
                }
            }
        }
        onLog("结束: 成功\(success) 总发\(sent)")
        return success
    }

    private func waitUntil(_ targetUnix: Double) async {
        while !stop {
            let rem = targetUnix - Date().timeIntervalSince1970
            if rem <= 0 { break }
            if rem > 0.05 {
                try? await Task.sleep(nanoseconds: UInt64(max(10, (rem - 0.03) * 1000)) * 1_000_000)
            } else { break }
        }
    }
}
