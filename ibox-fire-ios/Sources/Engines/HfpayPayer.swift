import Foundation

struct PayOutcome {
    var ok: Bool
    var detail: String
    var passwordError: Bool = false
}

/// 汇付 HFPWALLET 自动支付（对齐 Android HfpayPayer）。
final class HfpayPayer: @unchecked Sendable {
    private let hfpayBase = "https://hfpay.cloudpnr.com"
    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15"
    private let rawToken: String
    private let deviceId = UUID().uuidString.lowercased()
    private let http: ProxyURLSession

    init(iboxToken: String, proxyLine: String? = nil) {
        rawToken = JwtUtil.normalize(iboxToken)
        http = ProxyURLSession(proxyLine: proxyLine, timeout: 12)
        Task { await warmSession() }
    }

    private func cookieHeader() -> String { "token=\(rawToken); deviceId=\(deviceId)" }

    private func warmSession() async {
        guard let url = URL(string: "\(hfpayBase)/h5/") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(cookieHeader(), forHTTPHeaderField: "Cookie")
        _ = try? await http.data(for: req)
    }

    func fetchPayUuid(ibox: IboxClient, orderId: String) async -> String {
        let data = await ibox.get("/payment-service/cashiers/gain?orderUUId=\(orderId)&paymentInitiatorType=0")
        let link = (JSONX.dataDict(data)["link"] as? String) ?? ""
        guard let url = URL(string: link),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let uuid = comps.queryItems?.first(where: { $0.name == "uuid" })?.value else { return "" }
        return uuid
    }

    func pay(ibox: IboxClient, orderId: String, payPassword: String) async -> PayOutcome {
        let pwd = payPassword.trimmingCharacters(in: .whitespaces)
        var lastErr = ""
        for attempt in 0..<3 {
            let uuid = await fetchPayUuid(ibox: ibox, orderId: orderId)
            if uuid.isEmpty { return PayOutcome(ok: false, detail: "收银台无支付链接") }
            if uuid.count < 25 { return PayOutcome(ok: false, detail: "支付uuid异常") }
            await transVerify(uuid: uuid)
            let encPwd = HfpayCrypto.encryptPassword(pwd, payUuid: uuid)
            let (body, cv) = HfpayCrypto.makeBalancePayBody(encPwd: encPwd, randomFactor: uuid)
            let merEnd = min(25, uuid.count)
            let mer = String(uuid[uuid.index(uuid.startIndex, offsetBy: 9)..<uuid.index(uuid.startIndex, offsetBy: merEnd)])
            let pageUrl = "\(hfpayBase)/h5/pages/cashier/index?uuid=\(uuid)"
            guard let url = URL(string: "\(hfpayBase)/api/hfpwalleth5/balancepay"),
                  let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                return PayOutcome(ok: false, detail: "构造请求失败")
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = httpBody
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(uuid, forHTTPHeaderField: "uuid")
            req.setValue(mer, forHTTPHeaderField: "mer_cust_id")
            req.setValue("0", forHTTPHeaderField: "hide_head")
            req.setValue(hfpayBase, forHTTPHeaderField: "Origin")
            req.setValue(pageUrl, forHTTPHeaderField: "Referer")
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            req.setValue("keep-alive", forHTTPHeaderField: "Connection")
            req.setValue(cv, forHTTPHeaderField: "check_value")
            req.setValue(cookieHeader(), forHTTPHeaderField: "Cookie")
            do {
                let (data, _) = try await http.data(for: req)
                let o = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                let code = (o["resp_code"] as? String) ?? "\(o["respCode"] ?? o["code"] ?? "")"
                let msg = (o["resp_msg"] as? String) ?? (o["respDesc"] as? String) ?? (o["message"] as? String) ?? ""
                let stat = o["trans_stat"] as? String
                if code == "C00000" || stat == "S" || code == "000000" || o["success"] as? Bool == true {
                    return PayOutcome(ok: true, detail: msg.isEmpty ? "ok" : msg)
                }
                if msg.contains("密码") { return PayOutcome(ok: false, detail: msg, passwordError: true) }
                lastErr = msg.isEmpty ? "支付失败 \(code)" : "\(code) \(msg)"
            } catch {
                lastErr = error.localizedDescription
            }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 400_000_000) }
        }
        return PayOutcome(ok: false, detail: lastErr.isEmpty ? "支付失败" : lastErr)
    }

    private func transVerify(uuid: String) async {
        let devJson = #"{"devType":"2","devSysType":"H5","mobileFlag":"Y"}"#
        let body: [String: Any] = ["dev_info_json": devJson, "trans_type": "30"]
        let cv = HfpayCrypto.hmacSha256("dev_info_json=\(devJson)&trans_type=30", key: "chinapnr")
        let merEnd = min(25, uuid.count)
        let mer = String(uuid[uuid.index(uuid.startIndex, offsetBy: 9)..<uuid.index(uuid.startIndex, offsetBy: merEnd)])
        let pageUrl = "\(hfpayBase)/h5/pages/cashier/index?uuid=\(uuid)"
        guard let url = URL(string: "\(hfpayBase)/api/hfpwalleth5/transverifyquery"),
              let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = httpBody
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(uuid, forHTTPHeaderField: "uuid")
        req.setValue(mer, forHTTPHeaderField: "mer_cust_id")
        req.setValue("0", forHTTPHeaderField: "hide_head")
        req.setValue(hfpayBase, forHTTPHeaderField: "Origin")
        req.setValue(pageUrl, forHTTPHeaderField: "Referer")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(cv, forHTTPHeaderField: "check_value")
        req.setValue(cookieHeader(), forHTTPHeaderField: "Cookie")
        _ = try? await http.data(for: req)
    }
}
