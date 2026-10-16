import Foundation

/// 真源：`MoreExtraActions.farmDouDouMall` — newAct subtype=109。
enum DouDouMallActions {
    static let fid = "doudou_mall"

    static func farm(
        cookie: String,
        onLog: @escaping (String) -> Void
    ) async -> String {
        let t = FeatureToggleStore.shared
        let name = t.getString(fid, "name").trimmingCharacters(in: .whitespacesAndNewlines)
        let qq = t.getString(fid, "song_qq").trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshCap = Int(t.getString(fid, "shua_xin", default: "10").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 10
        let buyCap = Int(t.getString(fid, "number", default: "1").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1

        if name.isEmpty {
            let tip = "请输入要购买的道具名称"
            onLog(tip)
            return tip
        }
        if buyCap <= 0 {
            let tip = "请输入要购买的道具次数"
            onLog(tip)
            return tip
        }
        if refreshCap <= 0 {
            let tip = "请输入每次的刷新上限"
            onLog(tip)
            return tip
        }

        let wanted = name.split(separator: "、").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let view = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=newAct&op=1&subtype=109"
        let refreshUrl = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=newAct&op=8&subtype=109"
        let checkout = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=newAct&op=6&subtype=109"
        var refreshLeft = refreshCap
        var buyLeft = buyCap
        var url = view
        var hops = 0

        while hops < 80, buyLeft > 0 {
            hops += 1
            if Task.isCancelled { return "已取消" }
            guard let req = URL(string: url) else { break }
            var body = await LedouCGI.get(url: req, cookie: cookie).1
            try? await Task.sleep(nanoseconds: 200_000_000)
            var msg = field(body, "msg")
            if msg.contains("系统繁忙") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                body = await LedouCGI.get(url: req, cookie: cookie).1
                try? await Task.sleep(nanoseconds: 200_000_000)
                msg = field(body, "msg").ifBlankMe(msg)
            }
            if msg.contains("斗豆不足") {
                onLog(msg)
                return msg
            }
            if url == checkout {
                buyLeft -= 1
                refreshLeft = refreshCap
                let giftUin = qq.isEmpty ? "786501434" : qq
                let giftURL =
                    "https://fight.pet.qq.com/cgi-bin/petpk?cmd=newAct&op=7&subtype=109&target_uin=\(giftUin)"
                let giftBody = await LedouCGI.get(url: URL(string: giftURL)!, cookie: cookie).1
                try? await Task.sleep(nanoseconds: 200_000_000)
                let gm = field(giftBody, "msg").ifBlankMe(CombatLog.fromBody(giftBody))
                onLog("结算赠送：\(gm.isEmpty ? "已请求" : gm)（剩余购买 \(buyLeft)）")
                if buyLeft <= 0 { return "购买完成" }
                url = view
                continue
            }

            let goods = jsonChunks(body, "goods_info").compactMap { chunk -> (String, String, String)? in
                let idx = field(chunk, "goods_index")
                let gname = field(chunk, "goods_name")
                let status = field(chunk, "goods_status")
                guard !idx.isEmpty else { return nil }
                return (idx, gname, status)
            }
            if goods.isEmpty {
                let tip = msg.isEmpty ? "数据异常" : msg
                onLog(tip)
                return tip
            }
            if url == refreshUrl { refreshLeft -= 1 }
            onLog("货架：" + goods.map { "\($0.1)*\($0.0)" }.joined(separator: "、"))

            if let hit = goods.first(where: { g in
                g.2 == "0" && wanted.contains(where: { g.1.contains($0) })
            }) {
                let idx = max(0, (Int(hit.0) ?? 1) - 1)
                onLog("加入购物车：\(hit.1)")
                url = "https://fight.pet.qq.com/cgi-bin/petpk?cmd=newAct&op=4&goods_index=\(idx)&subtype=109"
                continue
            }

            let trolley = jsonChunks(body, "trolley_info")
            if trolley.isEmpty {
                if refreshLeft > 0 {
                    onLog("刷新（剩余 \(refreshLeft)）")
                    url = refreshUrl
                    continue
                }
                let tip = "刷新次数已耗尽"
                onLog(tip)
                return tip
            }
            for item in trolley {
                let add = field(item, "add_index")
                guard let g = goods.first(where: { $0.0 == add }) else { continue }
                if wanted.contains(where: { g.1.contains($0) }) == false {
                    let tip = "数据异常，请手动处理"
                    onLog(tip)
                    return tip
                }
            }
            onLog("结算购物车")
            url = checkout
        }
        let tip = buyLeft <= 0 ? "购买完成" : "本轮已停止"
        onLog(tip)
        return tip
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
}

private extension String {
    func ifBlankMe(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
