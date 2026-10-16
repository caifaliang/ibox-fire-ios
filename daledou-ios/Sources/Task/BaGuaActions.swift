import Foundation

/// 真源：`MoreExtraActions.farmBaGua` — spacerelic goosipview。
enum BaGuaActions {
    static let fid = "bagua"
    static let names = ["离", "坤", "兑", "乾", "坎", "艮", "震", "巽"]
    private static let gapNs: UInt64 = 80_000_000

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let auto = t.getBool(fid, "auto", default: true)
        let tipsRaw = t.getString(fid, "ed_tips")
        let tips = tipsRaw
            .split(whereSeparator: { "、,， ".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if !auto {
            let (_, page) = await LedouCGI.getPetPk(
                cmd: "spacerelic", extra: ["op": "goosipview"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = CombatLog.fromBody(page).ifBlankMe("已查询")
            onLog(msg)
            return msg
        }
        if tips.count < 4 {
            let tip = "请填写今日四层攻略，例如：离、坤、兑、乾"
            onLog(tip)
            return tip
        }
        onLog("八卦迷阵开始：\(tips.prefix(4).joined(separator: "、"))")
        var last = ""
        for _ in 0..<8 {
            let (_, page) = await LedouCGI.getPetPk(
                cmd: "spacerelic", extra: ["op": "goosipview"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            last = page
            let msg = field(page, "msg").ifBlankMe(CombatLog.fromBody(page))
            let status = jsonInt(page, "status") ?? 0
            let power = jsonInt(page, "power") ?? 0
            if !msg.isEmpty { onLog(msg) }
            if msg.contains("停留在了本层") || msg.contains("传送回了第一层") {
                return "八卦迷阵停止：\(msg)"
            }
            if status >= 5 {
                let (_, award) = await LedouCGI.getPetPk(
                    cmd: "spacerelic", extra: ["op": "goosipaward"], cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let am = CombatLog.fromBody(award).ifBlankMe("领奖已请求")
                onLog(am)
                return am
            }
            if power <= 0 {
                onLog("体力不足或未开启")
                return "体力不足"
            }
            let layer = min(3, max(0, status - 1))
            let name = tips.indices.contains(layer) ? tips[layer] : ""
            guard let idx = names.firstIndex(of: name) else {
                let tip = "第\(layer + 1)层攻略「\(name)」无法识别"
                onLog(tip)
                return tip
            }
            let id = "\(idx + 1)"
            onLog("第\(layer + 1)层走\(name)")
            let (_, go) = await LedouCGI.getPetPk(
                cmd: "spacerelic",
                extra: ["op": "goosipview", "id": id],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            last = go
            let gm = CombatLog.fromBody(go).ifBlankMe("已走\(name)")
            onLog(gm)
            if gm.contains("停留在了本层") || gm.contains("传送回了第一层") || gm.contains("系统繁忙") {
                return gm
            }
        }
        return CombatLog.fromBody(last).ifBlankMe("八卦迷阵本轮结束")
    }

    private static func field(_ body: String, _ key: String) -> String {
        let re = try? NSRegularExpression(
            pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"([^\"]*)\""
        )
        let ns = body as NSString
        if let m = re?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        return ""
    }

    private static func jsonInt(_ body: String, _ key: String) -> Int? {
        let re = try? NSRegularExpression(
            pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"?(-?\\d+)\"?"
        )
        let ns = body as NSString
        if let m = re?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return Int(ns.substring(with: m.range(at: 1)))
        }
        return nil
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
