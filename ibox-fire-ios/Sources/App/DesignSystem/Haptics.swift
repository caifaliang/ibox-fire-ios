import UIKit

/// 统一触觉反馈 — iOS 16 用 FeedbackGenerator；勿在热路径狂打。
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    static func prepare() {
        light.prepare()
        medium.prepare()
        notify.prepare()
        select.prepare()
    }

    /// 主按钮按下
    static func tap() {
        light.impactOccurred(intensity: 0.85)
    }

    /// 危险/停止
    static func warn() {
        medium.impactOccurred(intensity: 1.0)
    }

    /// Chip / Tab 切换
    static func selection() {
        select.selectionChanged()
    }

    /// 任务启动、关键确认
    static func commit() {
        medium.impactOccurred(intensity: 0.9)
    }

    /// 业务成功（锁单/抢合成功等）
    static func success() {
        notify.notificationOccurred(.success)
    }

    /// 业务失败 / 表单校验失败
    static func error() {
        notify.notificationOccurred(.error)
    }

    /// 轻提示（次要）
    static func softTap() {
        soft.impactOccurred(intensity: 0.6)
    }

    /// 根据日志 type / 文案映射（节流：同类型 450ms 内不重复）
    private static var lastLogHapticAt: [String: CFTimeInterval] = [:]
    private static let logLock = NSLock()

    static func fromLog(msg: String, type: String) {
        let t = type.lowercased()
        var key: String?
        switch t {
        case "error", "fail", "err": key = "error"
        case "success", "ok", "done": key = "success"
        default:
            // 引擎多数仍用 info，靠关键字识别关键成功
            if msg.contains("锁定OK") || msg.contains("批量锁定OK")
                || msg.contains("下单成功") || msg.contains("卖出成功")
                || msg.contains("批购成功") || msg.contains("confirm OK")
                || msg.contains("抢满") || msg.contains("支付成功") {
                key = "success"
            }
        }
        guard let key else { return }
        let now = CACurrentMediaTime()
        logLock.lock()
        let last = lastLogHapticAt[key] ?? 0
        if now - last < 0.45 {
            logLock.unlock()
            return
        }
        lastLogHapticAt[key] = now
        logLock.unlock()
        if key == "error" { error() } else { success() }
    }

    static func fromLogType(_ type: String) {
        fromLog(msg: "", type: type)
    }
}
