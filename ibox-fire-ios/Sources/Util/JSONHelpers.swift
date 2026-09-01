import Foundation

public enum JSONHelpers {
    public static func asDict(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    public static func asArray(_ any: Any?) -> [Any]? {
        any as? [Any]
    }

    public static func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    public static func parseAny(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    public static func stringify(_ obj: Any, pretty: Bool = false) -> String? {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(
                withJSONObject: obj,
                options: pretty ? [.prettyPrinted, .sortedKeys] : []
              ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func code(of obj: [String: Any], default def: Int64 = -1) -> Int64 {
        if let n = obj["code"] as? NSNumber { return n.int64Value }
        if let s = obj["code"] as? String, let v = Int64(s) { return v }
        return def
    }

    public static func message(of obj: [String: Any], default def: String = "") -> String {
        if let s = obj["message"] as? String, !s.isEmpty { return s }
        if let s = obj["msg"] as? String, !s.isEmpty { return s }
        if let s = obj["detail"] as? String, !s.isEmpty { return s }
        return def
    }

    public static func dataValue(of obj: [String: Any]) -> Any? {
        obj["data"]
    }

    public static func dataDict(of obj: [String: Any]) -> [String: Any]? {
        obj["data"] as? [String: Any]
    }

    public static func dataArray(of obj: [String: Any]) -> [Any]? {
        obj["data"] as? [Any]
    }

    public static func string(_ obj: [String: Any], _ key: String, default def: String = "") -> String {
        if let s = obj[key] as? String { return s }
        if let n = obj[key] as? NSNumber { return n.stringValue }
        return def
    }

    public static func int64(_ obj: [String: Any], _ key: String, default def: Int64 = 0) -> Int64 {
        if let n = obj[key] as? NSNumber { return n.int64Value }
        if let s = obj[key] as? String, let v = Int64(s) { return v }
        return def
    }

    public static func int(_ obj: [String: Any], _ key: String, default def: Int = 0) -> Int {
        Int(int64(obj, key, default: Int64(def)))
    }

    public static func double(_ obj: [String: Any], _ key: String, default def: Double = 0) -> Double {
        if let n = obj[key] as? NSNumber { return n.doubleValue }
        if let s = obj[key] as? String, let v = Double(s) { return v }
        return def
    }

    public static func bool(_ obj: [String: Any], _ key: String, default def: Bool = false) -> Bool {
        if let b = obj[key] as? Bool { return b }
        if let n = obj[key] as? NSNumber { return n.boolValue }
        if let s = obj[key] as? String {
            let l = s.lowercased()
            if l == "true" || l == "1" { return true }
            if l == "false" || l == "0" { return false }
        }
        return def
    }

    public static func firstLong(_ obj: [String: Any], _ keys: String...) -> Int64? {
        firstLong(obj, Array(keys))
    }

    public static func firstLong(_ obj: [String: Any], _ keys: [String]) -> Int64? {
        for k in keys {
            guard let v = obj[k], !(v is NSNull) else { continue }
            if let n = v as? NSNumber { return n.int64Value }
            if let s = v as? String, let x = Int64(s) { return x }
        }
        return nil
    }

    public static func firstInt(_ obj: [String: Any], _ keys: String...) -> Int? {
        firstLong(obj, Array(keys)).map { Int($0) }
    }

    public static func firstDouble(_ obj: [String: Any], _ keys: String...) -> Double? {
        firstDouble(obj, Array(keys))
    }

    public static func firstDouble(_ obj: [String: Any], _ keys: [String]) -> Double? {
        for k in keys {
            guard let v = obj[k], !(v is NSNull) else { continue }
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String, let x = Double(s) { return x }
        }
        return nil
    }

    public static func firstStr(_ obj: [String: Any], _ keys: String...) -> String {
        firstStr(obj, Array(keys))
    }

    public static func firstStr(_ obj: [String: Any], _ keys: [String]) -> String {
        for k in keys {
            if let s = obj[k] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && t != "null" { return t }
            }
        }
        return ""
    }
}
