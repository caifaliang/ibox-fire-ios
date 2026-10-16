import Foundation

/// 真源：`MoreExtraActions.farmChaQu` — rank kind=6 扫区服落名册。
enum ChaQuActions {
    private static let fid = "chaqu"
    private static let gapNs: UInt64 = 200_000_000

    @MainActor
    static func farm(force: Bool = false, onLog: @escaping (String) -> Void) async -> String {
        let t = FeatureToggleStore.shared
        let auto = t.getBool(fid, "cb_start")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let hour = cal.component(.hour, from: Date())
        if !force && !auto {
            let tip = "未勾选自动更新报名数据"
            onLog(tip)
            return tip
        }
        if !force && !(1...4).contains(hour) {
            let tip = "不在 1:00–5:00，跳过查区更新"
            onLog(tip)
            return tip
        }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            let tip = "尚未登录"
            onLog(tip)
            return tip
        }
        let minDj = Int(t.getString(fid, "min_dj").trimmingCharacters(in: .whitespaces))
        let maxDj = Int(t.getString(fid, "max_dj").trimmingCharacters(in: .whitespaces))
        let rankId: Int = {
            if let maxDj, maxDj < 60 { return 2 }
            if let minDj, minDj >= 80 { return 4 }
            if let maxDj, maxDj < 80 { return 3 }
            if let minDj, minDj >= 60 { return 3 }
            if let minDj, minDj < 60 { return 2 }
            return 4
        }()
        let zhanli = Int(t.getString(fid, "zhanli", default: "5000").trimmingCharacters(in: .whitespaces)) ?? 5000
        var sev = t.getInt(fid, "rank_sev", default: 1).clamped(to: 1...7)
        var page = max(1, t.getInt(fid, "rank_page", default: 1))
        if force && !t.getBool(fid, "force_resume") {
            sev = 1
            page = 1
        }
        var kept = 0
        var batch: [ChaQuStore.Entry] = []
        let deadline = Date().addingTimeInterval(force ? 180 : 45)
        while sev <= 7 && Date() < deadline {
            if Task.isCancelled { break }
            let (_, body) = await LedouCGI.getPetPk(
                cmd: "rank",
                extra: [
                    "kind": "6",
                    "id": "\(rankId)",
                    "page": "\(page)",
                    "sev": "\(sev)",
                ],
                cookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            if body.contains("登陆校验失败") || body.contains("登录校验失败") {
                let tip = "尚未登录"
                onLog(tip)
                return tip
            }
            let rows = jsonChunks(body, key: "list")
            if rows.isEmpty {
                let result = CombatLog.jsonInt(body, "result")
                if result != nil && result != 0 {
                    let tip = (CombatLog.jsonField(body, "msg") ?? "").ifBlankChaQu("查区无数据")
                    onLog(tip)
                    return tip
                }
            }
            var below = false
            for row in rows {
                let value = Int(field(row, "value")) ?? 0
                if value < zhanli {
                    below = true
                    break
                }
                let lv = Int(field(row, "level")) ?? 0
                if let minDj, lv < minDj { continue }
                if let maxDj, lv > maxDj { continue }
                let uin = field(row, "uin")
                if uin.isEmpty { continue }
                kept += 1
                batch.append(ChaQuStore.Entry(
                    uin: uin,
                    name: field(row, "name"),
                    level: lv,
                    value: value,
                    saiqu: sev,
                    lzn: sev == 7 ? 1 : 0
                ))
            }
            page += 1
            if below || page > 200 || rows.isEmpty {
                page = 1
                sev += 1
            }
        }
        ChaQuStore.shared.upsertAll(batch)
        if sev > 7 {
            t.setInt(fid, "rank_sev", 1)
            t.setInt(fid, "rank_page", 1)
            t.setBool(fid, "force_resume", false)
            let total = ChaQuStore.shared.size()
            let tip = "查区更新完毕，本轮写入 \(kept)，名册共 \(total)"
            onLog(tip)
            let sample = ChaQuStore.shared.sample(8)
            if !sample.isEmpty { onLog(sample.joined(separator: "；")) }
            return tip
        }
        t.setInt(fid, "rank_sev", sev)
        t.setInt(fid, "rank_page", page)
        if force { t.setBool(fid, "force_resume", true) }
        let total = ChaQuStore.shared.size()
        let tip = "查区进行中 区服\(sev) 第\(page)页，本轮写入 \(kept)，名册共 \(total)"
        onLog(tip)
        return tip
    }

    private static func field(_ row: String, _ key: String) -> String {
        let p = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"?([^\",}\\s]+)\"?"
        guard let re = try? NSRegularExpression(pattern: p),
              let m = re.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: row)
        else { return "" }
        return String(row[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func jsonChunks(_ body: String, key: String) -> [String] {
        let needle = "\"\(key)\""
        guard let keyRange = body.range(of: needle),
              let open = body[keyRange.upperBound...].firstIndex(of: "[")
        else {
            return blockObjects(body)
        }
        let from = body.index(after: open)
        var depth = 1
        var i = from
        while i < body.endIndex && depth > 0 {
            let c = body[i]
            if c == "[" { depth += 1 }
            if c == "]" { depth -= 1 }
            i = body.index(after: i)
        }
        guard depth == 0, i > from else { return blockObjects(body) }
        let end = body.index(before: i)
        return blockObjects(String(body[from..<end]))
    }

    private static func blockObjects(_ text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\{[^{}]*"uin"[^{}]*\}"#) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    func ifBlankChaQu(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
