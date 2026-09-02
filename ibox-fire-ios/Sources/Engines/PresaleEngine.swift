import Foundation

struct PresaleConfig {
    var token: String
    var saleId: Int64
    var saleName: String = ""
    var quantity: Int = 1
    var fireAtEpochSec: Int64
    var proxies: [String]
    var captchas: [CaptchaToken]
    var workers: Int = 6
    var earlyS: Double = 3.0
    var peakAfterS: Double = 4.0
    var durationS: Double = 60.0
    var autoPay: Bool = false
    var payPassword: String = ""
    var payProxy: String = ""
}

/// 对齐 Android PresaleEngine：本地极验预存码 + 代理风暴 encrypted sales 下单。
final class PresaleEngine: @unchecked Sendable {
    private let cfg: PresaleConfig
    private let onLog: (String) -> Void
    private var stop = false
    private let host = "https://sail-api.ibox.art"
    private let captchaId = "0d4b08eac1cbdcad36bbf607c5bf3e1b"

    init(cfg: PresaleConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async {
        let now0 = Date().timeIntervalSince1970
        if now0 - Double(cfg.fireAtEpochSec) > 10 {
            onLog("开火时间已过，已放弃")
            return
        }
        guard !cfg.proxies.isEmpty else { onLog("无代理"); return }
        guard !cfg.captchas.isEmpty else { onLog("无极验预存码，请重试"); return }

        var caps = cfg.captchas
        let nPx = cfg.proxies.count
        let workers = max(1, min(8, min(cfg.workers, nPx)))
        onLog("抢购引擎 \(cfg.saleName.isEmpty ? "#\(cfg.saleId)" : cfg.saleName)(#\(cfg.saleId)) x\(cfg.quantity) workers=\(workers) 码=\(caps.count) IP=\(nPx)")

        let plain = "{\"num\":1,\"paymentPlatformCode\":30}"
        let encBody: String
        do { encBody = try IboxCrypto.encryptBody(plain) } catch {
            onLog("加密失败 \(error.localizedDescription)"); return
        }

        let fireStart = Double(cfg.fireAtEpochSec) - cfg.earlyS
        let now = Date().timeIntervalSince1970
        if now < fireStart {
            onLog(String(format: "等待开火 T-%.1fs", fireStart - now))
            await waitUntil(fireStart)
        }
        let peakEnd = Double(cfg.fireAtEpochSec) + cfg.peakAfterS
        let deadline = Double(cfg.fireAtEpochSec) + cfg.durationS
        onLog("开火! 峰值至+\(cfg.peakAfterS)s 持续\(Int(cfg.durationS))s")

        let auth = JwtUtil.bearer(cfg.token)
        let lock = NSLock()
        let capLock = NSLock()
        var bought = 0
        var fired = 0
        var rr: Int64 = 0
        var cooldown = [Int64](repeating: 0, count: nPx)
        var firstLogged = false
        let payer: HfpayPayer? = (cfg.autoPay && !cfg.payPassword.isEmpty && !cfg.payProxy.isEmpty)
            ? HfpayPayer(iboxToken: cfg.token, proxyLine: cfg.payProxy) : nil

        await withTaskGroup(of: Void.self) { group in
            for wid in 0..<workers {
                group.addTask {
                    var local = Int64(wid)
                    while !self.stop {
                        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                        let nowSec = Double(nowMs) / 1000.0
                        if nowSec >= deadline { break }
                        lock.lock(); let b = bought; lock.unlock()
                        if b >= self.cfg.quantity { break }
                        let inPeak = nowSec < peakEnd

                        var idx: Int?
                        for _ in 0..<nPx {
                            let i: Int = lock.withLock {
                                let v = (rr + local) % Int64(nPx)
                                rr += 1
                                local += 1
                                return Int(v)
                            }
                            if cooldown[i] <= nowMs { idx = i; break }
                        }
                        guard let pxIdx = idx else {
                            try? await Task.sleep(nanoseconds: 5_000_000)
                            continue
                        }
                        let cap: CaptchaToken? = capLock.withLock {
                            caps.isEmpty ? nil : caps.removeFirst()
                        }
                        guard let cap else {
                            try? await Task.sleep(nanoseconds: 20_000_000)
                            continue
                        }
                        let qs = [
                            "captcha_id=\(self.captchaId)",
                            "gen_time=\(self.enc(cap.genTime))",
                            "captcha_output=\(self.enc(cap.captchaOutput))",
                            "pass_token=\(self.enc(cap.passToken))",
                            "lot_number=\(self.enc(cap.lotNumber))"
                        ].joined(separator: "&")
                        let path = "/order-create-service/sales/\(self.cfg.saleId)/orders?\(qs)"
                        let t0 = Date()
                        let (status, code, msg, oid) = await self.postOrder(
                            path: path, encBody: encBody, auth: auth, proxy: self.cfg.proxies[pxIdx]
                        )
                        let ms = Int(Date().timeIntervalSince(t0) * 1000)
                        lock.lock(); fired += 1; let nFire = fired; lock.unlock()

                        if status == 429 || status == 502 || status == 503 || status == 504 {
                            capLock.withLock { caps.append(cap) }
                            if !firstLogged || nFire <= 3 || nFire % 20 == 0 {
                                let left = capLock.withLock { caps.count }
                                self.onLog("HTTP\(status) #\(nFire) \(ms)ms 码剩\(left)")
                                firstLogged = true
                            }
                            if !inPeak && status == 429 {
                                cooldown[pxIdx] = nowMs + 1500
                            }
                            continue
                        }
                        if status < 200 || status >= 300 {
                            capLock.withLock { caps.append(cap) }
                            if !firstLogged || nFire <= 3 {
                                self.onLog("HTTP\(status) #\(nFire) \(ms)ms \(msg.prefix(60))")
                                firstLogged = true
                            }
                            if !inPeak { cooldown[pxIdx] = nowMs + 2000 }
                            continue
                        }
                        if code == 0 && !oid.isEmpty {
                            lock.lock(); bought += 1; let n = bought; lock.unlock()
                            self.onLog("下单成功 \(oid) (\(n)/\(self.cfg.quantity)) \(ms)ms")
                            if let payer {
                                let ibox = IboxClient(token: self.cfg.token, proxyLine: self.cfg.payProxy)
                                let pay = await payer.pay(ibox: ibox, orderId: oid, payPassword: self.cfg.payPassword)
                                self.onLog(pay.ok ? "自动支付成功 \(pay.detail)" : "支付失败: \(pay.detail)")
                            }
                            if n >= self.cfg.quantity { self.stop = true; return }
                        } else if msg.lowercased().contains("pass_token") || code == 406 || code == 400 {
                            self.onLog("验证码失效 [\(code)] \(msg.prefix(40))")
                        } else {
                            capLock.withLock { caps.append(cap) }
                            if nFire <= 5 || nFire % 25 == 0 {
                                let left = capLock.withLock { caps.count }
                                self.onLog("业务\(code) \(msg.prefix(40)) #\(nFire) 码剩\(left)")
                            }
                            if !inPeak { try? await Task.sleep(nanoseconds: 50_000_000) }
                        }
                        if !inPeak { try? await Task.sleep(nanoseconds: 80_000_000) }
                    }
                }
            }
        }
        lock.lock(); let final = bought; lock.unlock()
        let leftCaps = capLock.withLock { caps.count }
        onLog("抢购结束 成功 \(final)/\(cfg.quantity) 发\(fired) 码剩\(leftCaps)")
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func waitUntil(_ epochSec: Double) async {
        while !stop {
            let left = epochSec - Date().timeIntervalSince1970
            if left <= 0 { return }
            try? await Task.sleep(nanoseconds: UInt64(max(5, min(200, left * 1000))) * 1_000_000)
        }
    }

    private func postOrder(path: String, encBody: String, auth: String, proxy: String) async -> (status: Int, code: Int64, msg: String, oid: String) {
        guard let url = URL(string: host + path) else { return (-1, -1, "bad url", "") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(encBody.utf8)
        req.timeoutInterval = 2.5
        for (k, v) in [
            "Authorization": auth,
            "platform-type": "1",
            "channel": "website",
            "device-id": UUID().uuidString.lowercased(),
            "msg-id": UUID().uuidString.lowercased() + "_ios",
            "app-version-number": "30003",
            "app-version": "3.0.3",
            "verify-flag": "true",
            "User-Agent": "Dart/3.11 (dart:io)",
            "accept": "application/json",
            "Content-Type": "application/json"
        ] { req.setValue(v, forHTTPHeaderField: k) }

        let http = ProxyURLSession(proxyLine: proxy, timeout: 1.8)
        do {
            let (data, resp) = try await http.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return (status, -1, "empty", "") }
            var obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
            if obj["encryptKey"] != nil {
                let plain = try IboxCrypto.decryptResponse(text)
                obj = (try? JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any]) ?? obj
            }
            let code = JSONX.code(obj)
            let msg = JSONX.message(obj)
            let oid = (JSONX.dataDict(obj)["orderId"] as? String) ?? ""
            return (status, code, msg, oid)
        } catch {
            return (-1, -1, error.localizedDescription, "")
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
