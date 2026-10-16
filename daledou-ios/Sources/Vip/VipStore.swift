import Foundation
import CryptoKit

/// 真源：`VipStore.kt` — 本地缓存到期时间 + 每设备每 QQ 一次 7 天试用。
@MainActor
final class VipStore: ObservableObject {
    static let shared = VipStore()

    @Published private(set) var expireAtMs: Int64 = 0
    @Published private(set) var isTrial: Bool = false

    private let defaults = UserDefaults.standard
    private let keyExpire = "daledou.vip.expire_at_ms"
    private let keyTrial = "daledou.vip.is_trial"
    private let keyUsed = "daledou.vip.trial_used_fp"
    private let trialMs: Int64 = 7 * 24 * 60 * 60 * 1000

    private init() {
        expireAtMs = Int64(defaults.integer(forKey: keyExpire))
        isTrial = defaults.bool(forKey: keyTrial)
    }

    var isActive: Bool {
        expireAtMs > Int64(Date().timeIntervalSince1970 * 1000)
    }

    func setExpire(_ ms: Int64, trial: Bool) {
        expireAtMs = ms
        isTrial = trial
        defaults.set(Int(ms), forKey: keyExpire)
        defaults.set(trial, forKey: keyTrial)
    }

    func clearTrialFlagIfPaid() {
        if isActive, isTrial {
            // keep trial until paid redeem clears it
        }
        objectWillChange.send()
    }

    func markPaid(expireMs: Int64) {
        setExpire(expireMs, trial: false)
    }

    /// 每个 QQ + 每台设备一次 7 天试用。付费有效期内不覆盖。
    func ensureDeviceUserTrial(deviceId: String, uin: String) {
        let qq = uin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qq.isEmpty, !deviceId.isEmpty else { return }
        if isActive, !isTrial { return }
        let fp = Self.fingerprint(deviceId: deviceId, uin: qq)
        var used = usedFingerprints()
        guard !used.contains(fp) else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        setExpire(now + trialMs, trial: true)
        used.insert(fp)
        defaults.set(used.sorted().joined(separator: ","), forKey: keyUsed)
    }

    private func usedFingerprints() -> Set<String> {
        let raw = defaults.string(forKey: keyUsed) ?? ""
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private static func fingerprint(deviceId: String, uin: String) -> String {
        let data = Data("\(deviceId)|\(uin)".utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
