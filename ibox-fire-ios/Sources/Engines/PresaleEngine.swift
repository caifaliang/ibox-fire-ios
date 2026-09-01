import Foundation

struct PresaleConfig {
    var token: String
    var saleId: Int64
    var quantity: Int = 1
    var fireAtEpochSec: Int64
    var proxies: [String]
    var workers: Int = 8
    var useServerGeetest: Bool = true
    var autoPay: Bool = false
    var payPassword: String = ""
    var earlyS: Double = 2.0
    var durationS: Double = 45
}

final class PresaleEngine: @unchecked Sendable {
    private let cfg: PresaleConfig
    private let onLog: (String) -> Void
    private var stop = false
    private let api = ApiRepository()

    init(cfg: PresaleConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async {
        guard JwtUtil.uid(cfg.token) != nil else { onLog("JWT 无 userId"); return }
        if cfg.proxies.isEmpty { onLog("无代理"); return }
        onLog("抢购启动 saleId=\(cfg.saleId) x\(cfg.quantity) proxies=\(cfg.proxies.count)")

        var captcha: CaptchaToken?
        if cfg.useServerGeetest {
            onLog("服务端极验中…")
            do {
                captcha = try await api.presaleVerify(iboxToken: cfg.token, preferredProxy: cfg.proxies.first ?? "")
                onLog("极验通过 lot=\(captcha!.lotNumber.prefix(8))…")
            } catch {
                onLog("极验失败: \(error.localizedDescription)（可后续换本地求解）")
            }
        }

        let fireStart = Double(cfg.fireAtEpochSec) - cfg.earlyS
        let now = Date().timeIntervalSince1970
        if now < fireStart {
            onLog(String(format: "等待开火 T-%.1fs", fireStart - now))
            while !stop && Date().timeIntervalSince1970 < fireStart {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        onLog("开火抢购!")
        let deadline = Double(cfg.fireAtEpochSec) + cfg.durationS
        var bought = 0
        let payer: HfpayPayer? = (cfg.autoPay && !cfg.payPassword.isEmpty) ? HfpayPayer(iboxToken: cfg.token, proxyLine: cfg.proxies.first) : nil

        await withTaskGroup(of: Void.self) { group in
            let n = min(cfg.workers, cfg.proxies.count)
            for i in 0..<n {
                let px = cfg.proxies[i]
                group.addTask {
                    let client = IboxClient(token: self.cfg.token, proxyLine: px, connectMs: 1200, readMs: 2500, deviceIdMode: .stableMD5)
                    while !self.stop && Date().timeIntervalSince1970 < deadline && bought < self.cfg.quantity {
                        var body: [String: Any] = [
                            "saleId": self.cfg.saleId,
                            "count": 1,
                            "paymentPlatformCode": 30
                        ]
                        if let c = captcha {
                            body["lotNumber"] = c.lotNumber
                            body["captchaOutput"] = c.captchaOutput
                            body["passToken"] = c.passToken
                            body["genTime"] = c.genTime
                        }
                        let r = await client.postJson("/order-create-service/presale-orders", body: body)
                        let code = JSONX.code(r)
                        let msg = JSONX.message(r)
                        if code == 0 {
                            bought += 1
                            let oid = (JSONX.dataDict(r)["orderUUId"] as? String) ?? ""
                            self.onLog("抢购成功 \(bought)/\(self.cfg.quantity) \(oid)")
                            if let payer, !oid.isEmpty {
                                let pay = await payer.pay(ibox: client, orderId: oid, payPassword: self.cfg.payPassword)
                                self.onLog(pay.ok ? "支付OK \(pay.detail)" : "支付失败 \(pay.detail)")
                            }
                            if bought >= self.cfg.quantity { self.stop = true; return }
                        } else {
                            self.onLog("抢购 c=\(code) \(msg.prefix(40))")
                        }
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                }
            }
        }
        onLog("抢购结束 成功\(bought)")
    }
}
