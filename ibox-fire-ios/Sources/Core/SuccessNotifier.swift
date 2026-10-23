import Foundation
import UserNotifications

/// 系统通知栏成功提醒 — 对齐 Android `SuccessNotifier`。
/// 从日志文案匹配关键成功事件（捡漏/公告锁/抢合等），弹高优先级本地通知。
enum SuccessNotifier {
    private static let prefsKey = "success_notify"
    private static let lock = NSLock()
    private static var lastKey = ""
    private static var lastAt: CFTimeInterval = 0

    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: prefsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: prefsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: prefsKey) }
    }

    /// 由 `AppViewModel.appendLog` 调用。
    static func onLog(kind: String, msg: String) {
        guard enabled else { return }
        guard let title = matchTitle(kind: kind, raw: msg) else { return }
        let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(kind)|\(title)|\(String(trimmed.prefix(48)))"
        let now = CACurrentMediaTime()
        lock.lock()
        if key == lastKey && now - lastAt < 0.8 {
            lock.unlock()
            return
        }
        lastKey = key
        lastAt = now
        lock.unlock()
        post(title: title, body: String(trimmed.prefix(160)))
    }

    /// 任务结束汇总：成功次数 > 0
    static func onDone(kind: String, n: Int) {
        guard enabled, n > 0 else { return }
        post(title: "\(kindLabel(kind))成功", body: "本轮成功 \(n) 次")
    }

    /// 暴露给单测：匹配成功标题；不匹配返回 nil。
    static func matchTitle(kind: String, raw: String) -> String? {
        let msg = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty { return nil }
        // 噪声
        if msg.contains("失败") || msg.contains("跳过") || msg.contains("首轮成功列表")
            || msg.contains("登录成功") || msg.contains("扣次成功") || msg.contains("未映射") {
            return nil
        }
        if msg.hasPrefix("结束") || msg.hasPrefix("捡漏结束") || msg.hasPrefix("公告锁定结束")
            || msg.hasPrefix("推荐锁定结束") || msg.hasPrefix("全盘捡漏结束")
            || msg.hasPrefix("完成:") || msg.hasPrefix("卖求购结束") {
            return nil
        }
        // 「完成 N/M」汇总不算单次成功弹窗（避免与 confirm OK 重复）
        if msg.hasPrefix("完成 ") { return nil }

        if msg.contains("批量锁定OK") || msg.hasPrefix("锁定OK") {
            return "公告锁定成功"
        }
        if msg.contains("批购成功") {
            return "推荐锁定成功"
        }
        if msg.contains("卖出成功") || msg.contains("精准卖出成功") {
            return "卖求购成功"
        }
        if msg.contains("支付直达") {
            switch kind {
            case "buy", "nb_snipe": return "捡漏待支付"
            case "seg_snipe": return "板块盯盘待支付"
            case "announce", "recommend_lock": return "公告锁待支付"
            default: return "待支付"
            }
        }
        if msg.contains("下单成功") {
            switch kind {
            case "buy", "nb_snipe": return "捡漏下单成功"
            case "seg_snipe": return "板块盯盘下单成功"
            case "presale", "nb_presale": return "抢购下单成功"
            case "sweep": return "点对点下单成功"
            default: return "下单成功"
            }
        }
        if msg.contains("自动支付成功") || msg.contains("支付成功") {
            switch kind {
            case "buy", "nb_snipe": return "捡漏支付成功"
            case "seg_snipe": return "板块盯盘支付成功"
            case "presale", "nb_presale": return "抢购支付成功"
            case "sweep": return "点对点支付成功"
            default: return "支付成功"
            }
        }
        if kind == "nb_snipe" && msg.contains("成功") && msg.contains("¥") {
            return "NB捡漏成功"
        }
        // Android: OK #；iOS FireEngine: confirm OK；NB: OK #
        if kind == "synth" && (msg.hasPrefix("OK #") || msg.contains("confirm OK")) {
            return "抢合成功"
        }
        if (kind == "nb_presale" || kind == "presale") && msg.hasPrefix("OK #") {
            return "抢购成功"
        }
        if msg.contains("锁定成功") && (kind == "seg_snipe" || kind == "announce") {
            return kind == "seg_snipe" ? "板块盯盘锁定成功" : "公告锁定成功"
        }
        return nil
    }

    private static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "synth": return "抢合"
        case "presale": return "抢购"
        case "nb_presale": return "NB抢购"
        case "nb_snipe": return "NB捡漏"
        case "announce": return "公告锁"
        case "recommend_lock": return "推荐锁定"
        case "buy": return "捡漏"
        case "seg_snipe": return "板块盯盘"
        case "sell", "precision": return "卖求购"
        case "sweep": return "点对点"
        case "batch": return "上下架"
        default: return kind
        }
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "success.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
