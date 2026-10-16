import CryptoKit
import Foundation

/// 真源：`MoreExtraActions.farmXianShiQiangGou` — 18:00 窗口 buy type=8。
enum XianShiQiangGouActions {
    static let fid = "xianshi_qianggou"

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let savedId = t.getString(fid, "id").trimmingCharacters(in: .whitespacesAndNewlines)
        let early = Int(t.getString(fid, "time", default: "1").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        let groups = max(0, Int(t.getString(fid, "count_zong", default: "1").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)
        let each = max(0, Int(t.getString(fid, "count_dan", default: "1").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)

        if savedId.isEmpty {
            let tip = "请输入商品 id"
            onLog(tip)
            return tip
        }
        if groups == 0 || each == 0 {
            let tip = "总购买组数/单组购买数量不能为空"
            onLog(tip)
            return tip
        }
        if each > 100 {
            let tip = "单组购买数量不能大于100"
            onLog(tip)
            return tip
        }

        let waitDeadline = Date().addingTimeInterval(180)
        while !inBuyWindow(earlyMinutes: early), Date() < waitDeadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return "已取消" }
        }
        if !inBuyWindow(earlyMinutes: early) {
            let tip = "等待 18:00 开抢，提前 \(early) 分钟"
            onLog(tip)
            return tip
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let now = Date()
        let y = cal.component(.year, from: now)
        let mo = cal.component(.month, from: now)
        let d = cal.component(.day, from: now)
        let day = String(format: "%04d%02d%02d", y, mo, d)
        var done = t.getString(fid, "buy_day") == day ? t.getInt(fid, "buy_done") : 0
        if done >= groups {
            let tip = "今日 \(groups) 组已买完"
            onLog(tip)
            return tip
        }

        onLog("开始抢购！！！")
        let (_, list) = await LedouCGI.getPetPk(
            cmd: "newAct", extra: ["subtype": "140", "id": "1"], cookie: cookie
        )
        try? await Task.sleep(nanoseconds: 80_000_000)
        let dayMark = "\(d)日"
        var slot = 0
        for (i, chunk) in jsonChunks(list, "allTime").enumerated() {
            if slot == 0, field(chunk, "time").contains(dayMark) {
                slot = i + 1
            }
        }
        if slot > 0 {
            let (_, detail) = await LedouCGI.getPetPk(
                cmd: "newAct", extra: ["subtype": "140", "id": "\(slot)"], cookie: cookie
            )
            try? await Task.sleep(nanoseconds: 80_000_000)
            let desc = field(detail, "goodsDesc")
            let price = field(detail, "price")
            let packet = field(detail, "packetId")
            let limit = jsonInt(detail, "myLimitNum")
            onLog("今日：\(desc.isEmpty ? "已查询" : desc) 鹅币\(price) id=\(packet)")
            if let limit, groups * each > limit {
                let tip = "购买数量不能大于\(limit)"
                onLog(tip)
                return tip
            }
            if !packet.isEmpty, packet != savedId {
                onLog("今日商品 id=\(packet)（页面填写 \(savedId)）")
            }
        }

        let uin = LoginURLs.extractQq(cookie) ?? ""
        let token = fightBuyToken(cookie)
        if uin.isEmpty || token.isEmpty {
            let tip = "缺少 selfuin 或 accessToken，无法签名购买"
            onLog(tip)
            return tip
        }

        let buyURL =
            "https://fight.pet.qq.com/cgi-bin/petpk?cmd=buy&selfuin=\(uin)&id=\(savedId)&type=8&num=\(each)&token=\(token)"
        let referer = "https://fight.pet.qq.com/buy.html?id=\(savedId)"
        let buyDeadline = Date().addingTimeInterval(180)
        var fails = 0
        while done < groups, Date() < buyDeadline {
            if Task.isCancelled { return "已取消" }
            guard let url = URL(string: buyURL) else { break }
            let (_, buy) = await LedouCGI.get(url: url, cookie: cookie, referer: referer)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let msg = field(buy, "msg").ifBlankMe(CombatLog.fromBody(buy))
            let result = jsonInt(buy, "result")
            if result == 0 {
                done += 1
                fails = 0
                t.setString(fid, "buy_day", day)
                t.setInt(fid, "buy_done", done)
                onLog("成功 \(done)/\(groups)：\(msg.isEmpty ? "ok" : msg)")
            } else {
                fails += 1
                if fails <= 3 || fails % 10 == 0 {
                    onLog(msg.isEmpty ? "购买失败" : msg)
                }
                if msg.contains("不足") || msg.contains("售罄") || msg.contains("达上限")
                    || msg.contains("已结束") || msg.contains("校验")
                {
                    return msg.isEmpty ? "购买停止" : msg
                }
            }
        }
        let tip = done >= groups
            ? "抢购任务已完成！！！"
            : "已成功 \(done)/\(groups) 组（本轮超时，下轮继续）"
        onLog(tip)
        return tip
    }

    // MARK: - helpers

    private static func inBuyWindow(earlyMinutes: Int) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let now = Date()
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        return h >= 18 || h + (m + earlyMinutes) / 60 >= 18
    }

    private static func fightBuyToken(_ cookie: String) -> String {
        let salt = LoginURLs.cookieValue(cookie, names: ["accessToken", "access_token", "openkey"]) ?? ""
        if salt.isEmpty { return "" }
        return md5Hex(salt + "fight")
    }

    private static func md5Hex(_ raw: String) -> String {
        Insecure.MD5.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func jsonChunks(_ body: String, _ arrayName: String) -> [String] {
        guard let keyAt = body.range(of: "\"\(arrayName)\"")?.lowerBound,
              let openRel = body[keyAt...].firstIndex(of: "[")
        else { return [] }
        var depth = 0
        var end = openRel
        var i = openRel
        while i < body.endIndex {
            let c = body[i]
            if c == "[" { depth += 1 }
            if c == "]" {
                depth -= 1
                if depth == 0 {
                    end = i
                    break
                }
            }
            i = body.index(after: i)
        }
        let arr = String(body[openRel...end])
        var out: [String] = []
        let re = try? NSRegularExpression(pattern: #"\{[^{}]*\}"#)
        let ns = arr as NSString
        re?.enumerateMatches(in: arr, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            out.append(ns.substring(with: m.range))
        }
        return out
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
