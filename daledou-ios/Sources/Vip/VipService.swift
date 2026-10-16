import Foundation
import UIKit

/// 真源：`VipService.kt` / `VipConfig` — ai.iboxai.top 兑换 DLDOU- 卡密。
enum VipConfig {
    static let baseURL = "https://ai.iboxai.top/api"
    static let shopDay = "https://wzyp.cn/item/32dktb"
    static let shopWeek = "https://wzyp.cn/item/exx4hy"
    static let shopMonth = "https://wzyp.cn/item/12zo57"
    static let shopYear = "https://wzyp.cn/item/6k6iyp"

    static var deviceId: String {
        get {
            if let s = UserDefaults.standard.string(forKey: "daledou.vip.device_id"), !s.isEmpty {
                return s
            }
            let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            UserDefaults.standard.set(id, forKey: "daledou.vip.device_id")
            return id
        }
        set { UserDefaults.standard.set(newValue, forKey: "daledou.vip.device_id") }
    }
}

struct VipStatus {
    var active: Bool
    var expireAtMs: Int64?
    var trial: Bool
}

struct VipRedeemResult {
    var ok: Bool
    var message: String
    var expireAtMs: Int64?
}

enum VipService {
    @MainActor
    static func localStatus() -> VipStatus {
        let s = VipStore.shared
        return VipStatus(
            active: s.isActive,
            expireAtMs: s.expireAtMs > 0 ? s.expireAtMs : nil,
            trial: s.isTrial && s.isActive
        )
    }

    static func redeem(cardCode: String) async -> VipRedeemResult {
        let code = cardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { return VipRedeemResult(ok: false, message: "请输入卡密") }
        let device = VipConfig.deviceId
        if device.isEmpty { return VipRedeemResult(ok: false, message: "设备标识未就绪，请重启应用") }
        let upper = code.uppercased()
        if upper.hasPrefix("IBOX-") {
            return VipRedeemResult(ok: false, message: "此为 iBox 卡密，无法在大乐斗激活")
        }
        if !upper.hasPrefix("DLDOU-") {
            return VipRedeemResult(ok: false, message: "请使用大乐斗卡密（DLDOU-开头）")
        }
        guard let url = URL(string: "\(VipConfig.baseURL)/daledou/vip/redeem") else {
            return VipRedeemResult(ok: false, message: "VIP 地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "code=\(urlEncode(code))&device=\(urlEncode(device))"
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let codeHttp = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = (json?["detail"] as? String)?.trimmingCharacters(in: .whitespaces)
            let ok = json?["ok"] as? Bool == true
                || (json?["code"] as? Int) == 0
                || (json?["status"] as? String) == "ok"
            let expire = (json?["expireAtMs"] as? NSNumber).map(\.int64Value).flatMap { $0 > 0 ? $0 : nil }
                ?? parseExpireMs(json?["vip_expires_at"] as? String)
            let msg = detail?.nilIfBlank
                ?? (json?["message"] as? String)?.nilIfBlank
                ?? (json?["msg"] as? String)?.nilIfBlank
                ?? (ok ? "兑换成功" : "兑换失败(\(codeHttp))")
            if ok, let expire, expire > 0 {
                await MainActor.run { VipStore.shared.markPaid(expireMs: expire) }
            }
            return VipRedeemResult(ok: ok, message: msg, expireAtMs: expire)
        } catch {
            return VipRedeemResult(ok: false, message: "网络错误: \(error.localizedDescription)")
        }
    }

    static func queryStatus(uin: String) async -> VipStatus {
        let device = VipConfig.deviceId
        if device.isEmpty {
            return await MainActor.run { localStatus() }
        }
        var q = "\(VipConfig.baseURL)/daledou/vip/status?device=\(urlEncode(device))"
        if !uin.isEmpty { q += "&uin=\(urlEncode(uin))" }
        if let url = URL(string: q) {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let active = json["active"] as? Bool ?? false
                    let trial = json["trial"] as? Bool ?? false
                    let expire = (json["expireAtMs"] as? NSNumber).map(\.int64Value).flatMap { $0 > 0 ? $0 : nil }
                        ?? parseExpireMs(json["vip_expires_at"] as? String)
                    await MainActor.run {
                        if let expire, expire > 0 {
                            VipStore.shared.setExpire(expire, trial: trial && expire > Int64(Date().timeIntervalSince1970 * 1000))
                        } else if active, !trial, VipStore.shared.isTrial {
                            VipStore.shared.setExpire(VipStore.shared.expireAtMs, trial: false)
                        }
                    }
                }
            } catch {
                // fall through to local + trial
            }
        }
        return await MainActor.run {
            let store = VipStore.shared
            if !(store.isActive && !store.isTrial) {
                store.ensureDeviceUserTrial(deviceId: device, uin: uin)
            }
            return localStatus()
        }
    }

    private static func parseExpireMs(_ raw: String?) -> Int64? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "T", with: " ")
        if s.count > 19 { s = String(s.prefix(19)) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let d = fmt.date(from: s) else { return nil }
        return Int64(d.timeIntervalSince1970 * 1000)
    }

    private static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// 真源：`VipAccess.kt` — 免费入口白名单，其余需有效会员。
enum VipAccess {
    static let expiredMsg = "会员已过期，请开通大乐斗会员"

    private static let freeFeatureIds: Set<String> = [
        "one_login", "scan_login", "logout", "exit_app",
        "about", "join_qq_group", "note_settings", "account_switch",
    ]

    static func isFreeFeature(_ id: String?) -> Bool {
        guard let id else { return false }
        return freeFeatureIds.contains(id)
    }

    @MainActor
    static func isActive() -> Bool { VipStore.shared.isActive }

    /// true=可继续；false=应提示开通。
    @MainActor
    static func requireOrToast(_ featureId: String? = nil) -> Bool {
        if isFreeFeature(featureId) { return true }
        return isActive()
    }
}
