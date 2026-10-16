import Foundation

/// 真源：`MoreExtraActions.farmXingYunDuoBao` — christmaslottery。
enum XingYunDuoBaoActions {
    static let fid = "xydb"
    private static let gapNs: UInt64 = 80_000_000

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let auto = t.getBool(fid, "auto", default: true)
        let names = t.getString(fid, "ed_names")
            .split(whereSeparator: { "、,，\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let want = min(20, max(1, Int(t.getString(fid, "ed_count", default: "1").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1))

        let (_, page) = await LedouCGI.getPetPk(
            cmd: "christmaslottery", extra: ["op": "0"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)

        if !auto {
            let msg = CombatLog.fromBody(page).ifBlankMe("已查询")
            onLog(msg)
            return msg
        }
        if names.isEmpty {
            let tip = "请填写要夺的道具名（逗号分隔）"
            onLog(tip)
            return tip
        }

        let re = try? NSRegularExpression(pattern: #"\{[^{}]*"goodsId"\s*:\s*"(\d+)"[^{}]*\}"#)
        let ns = page as NSString
        var blocks: [String] = []
        re?.enumerateMatches(in: page, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            blocks.append(ns.substring(with: m.range))
        }
        if blocks.isEmpty {
            let tip = CombatLog.fromBody(page).ifBlankMe("夺宝列表为空")
            onLog(tip)
            return tip
        }

        var bought = 0
        for block in blocks {
            guard let id = match1(block, #""goodsId"\s*:\s*"(\d+)""#) else { continue }
            let name = match1(block, #""name"\s*:\s*"((?:\\.|[^"\\])*)""#) ?? ""
            let remain = Int(match1(block, #""remainNum"\s*:\s*(\d+)""#) ?? "0") ?? 0
            let lottered = match1(block, #""isLottered"\s*:\s*"?(\d+)""#)
            if names.contains(where: { name.contains($0) }) == false { continue }
            if lottered == "1" || remain <= 0 {
                onLog("\(name) 已结束或无剩余")
                continue
            }
            let times = min(want, max(1, remain))
            for _ in 0..<times {
                let (_, buy) = await LedouCGI.getPetPk(
                    cmd: "christmaslottery",
                    extra: ["op": "1", "goodsId": id],
                    cookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                let bm = CombatLog.fromBody(buy).ifBlankMe("已请求")
                onLog("\(name)：\(bm)")
                bought += 1
                if bm.contains("不足") || bm.contains("结束") || bm.contains("繁忙") || bm.contains("上限") {
                    break
                }
            }
        }
        let tip = bought == 0 ? "未匹配到可夺道具" : "幸运夺宝 \(bought) 次"
        onLog(tip)
        return tip
    }

    private static func match1(_ s: String, _ pattern: String) -> String? {
        let re = try? NSRegularExpression(pattern: pattern)
        let ns = s as NSString
        guard let m = re?.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
