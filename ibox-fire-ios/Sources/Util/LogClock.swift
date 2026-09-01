import Foundation

/// 日志时间戳统一北京时间（Asia/Shanghai，UTC+8），精度到毫秒。
public enum LogClock {
    private static let tz = TimeZone(identifier: "Asia/Shanghai")!

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = tz
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public static func now() -> String {
        formatter.string(from: Date())
    }

    /// 若已带 `[HH:mm:ss...]` 前缀则原样返回，否则加北京时间戳。
    public static func stamp(_ msg: String) -> String {
        if msg.hasPrefix("["), msg.count > 10 {
            let chars = Array(msg)
            if chars.count > 6, chars[3] == ":", chars[6] == ":" {
                return msg
            }
        }
        return "[\(now())] \(msg)"
    }
}
