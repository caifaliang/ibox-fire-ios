import Foundation

/// 真源：`DaoJuActions` — 签到浏览 / 累计 / 许愿清理 / 聚豆兑换。
enum DaoJuActions {
    private static let fid = "more_settings"
    private static let gapNs: UInt64 = 120_000_000

    private static let goods: [(String, String, String)] = [
        ("cb_jdc_hl", "123", "活力药水"),
        ("cb_jdc_ts", "122", "无字天书"),
        ("cb_jdc_wxd", "121", "悟性丹"),
        ("cb_jdc_tzs", "120", "挑战书"),
        ("cb_jdc_cgf", "119", "传功符"),
        ("cb_jdc_khbd", "452", "葵花宝典"),
        ("cb_jdc_jj30", "458", "剑君30天"),
        ("cb_jdc_cc30", "455", "菜菜30天"),
        ("cb_jdc_ztl", "446", "真体力"),
        ("cb_jdc_jyys", "449", "经验药水"),
        ("cb_jdc_yxhz", "468", "月炫魂珠"),
        ("cb_jdc_yyhz", "463", "月影魂珠"),
    ]

    @MainActor
    static func farm(onLog: @escaping (String) -> Void) async -> String {
        let store = SessionStore.shared
        var cookie = store.daojuCookie
        var session = DjcClient.sessionOrNull(rawCookie: cookie)
        if session == nil {
            // 尝试从当前 WK 汇总 Cookie 里再解析一次（调用方已尽量落盘）
            if let oauth = DjcAuth.parseOAuth(cookie) {
                cookie = DjcAuth.compactCookie(from: oauth)
                store.saveDaoju(cookie)
                session = DjcClient.sessionOrNull(rawCookie: cookie)
            }
        }
        if session == nil {
            if cookie.isEmpty {
                onLog("请先菜单→扫码→道聚城登录")
                return "未登录道聚城"
            }
            onLog("道聚城 Cookie 无效（缺 access_token/openid）")
            return "Cookie无效"
        }
        var qq = store.qq.filter(\.isNumber)
        if qq.isEmpty {
            qq = LoginURLs.extractQq(store.cookieHeader) ?? ""
        }
        if qq.isEmpty {
            onLog("未记录大乐斗 QQ，无法兑换（lRoleId）。请先完成一键/扫码登录大乐斗")
            return "无QQ"
        }
        onLog("掌上道聚城开始 QQ=\(qq)")
        let t = FeatureToggleStore.shared
        var ok = 0

        let bind = await DjcClient.getIgw(
            service: "app.role.bind_action",
            extra: ["_biz_code": "fight", "output_format": "json"],
            postBody: "",
            rawCookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let bindMsg = jsonMsg(bind.body)
        if !bindMsg.isEmpty { onLog("绑定:\(bindMsg)") }

        if t.getBool(fid, "cb_jdc_qiandao") || t.getBool(fid, "cb_jdc_renwu") {
            ok += await doBrowseTasks(cookie: cookie, onLog: onLog)
            ok += await doRushTasks(cookie: cookie, onLog: onLog)
        }
        if t.getBool(fid, "cb_jdc_leiji") || t.getBool(fid, "cb_jdc_xy") {
            let daQu = Int(t.getString(fid, "ed_jdc_xy").trimmingCharacters(in: .whitespaces))
            if daQu == nil || (daQu ?? 0) <= 0 {
                onLog("请填写更多设置「王者大区号」(ed_jdc_xy)，累计/许愿需要")
            } else if let role = await DjcClient.queryYxzjRole(daQu: daQu!, rawCookie: cookie) {
                onLog("王者角色:\(role.roleName)(\(role.roleCode)) 区\(role.partition)")
                if t.getBool(fid, "cb_jdc_leiji") {
                    ok += await doLeiJi(cookie: cookie, role: role, onLog: onLog)
                }
                if t.getBool(fid, "cb_jdc_xy") {
                    ok += await doXuYuan(cookie: cookie, role: role, onLog: onLog)
                }
            } else {
                onLog("查不到王者角色（大区\(daQu!)），请确认区服号")
            }
        }

        let picked = goods.filter { t.getBool(fid, $0.0) }
        if picked.isEmpty && ok == 0 {
            onLog("请在更多设置勾选签到/任务/累计/许愿或兑换道具")
            return "未勾选"
        }
        for (_, seq, name) in picked {
            let r = await DjcClient.buyJudou(goodsSeqId: seq, roleId: qq, rawCookie: cookie)
            try? await Task.sleep(nanoseconds: gapNs)
            let raw = r.body.replacingOccurrences(of: "var i_buy=", with: "").trimmingCharacters(in: .whitespaces)
            var msg = jsonMsg(raw)
            if msg.isEmpty {
                msg = raw.localizedCaseInsensitiveContains("success") ? "兑换成功" : "空响应"
            }
            onLog("兑换-\(name):\(msg)")
            ok += 1
            if msg.contains("信用分") || msg.contains("登录") || msg.contains("未登录")
                || msg.contains("失效") || r.code == 401
            {
                onLog("道聚城登录失效，请重新扫码")
                break
            }
        }
        if t.getBool(fid, "cb_jdc_open") {
            onLog("兑换结束：可手动打开掌上道聚城 App 核对")
        }
        onLog("掌上道聚城结束")
        return "道聚城\(ok)"
    }

    private static func jsonMsg(_ body: String) -> String {
        let from = CombatLog.fromBody(body)
        if !from.isEmpty { return from }
        if let re = try? NSRegularExpression(pattern: #""msg"\s*:\s*"([^"]+)""#),
           let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: body)
        {
            return String(body[r])
        }
        return String(body.prefix(48))
    }

    private static func weekdayMon1() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d = cal.component(.weekday, from: Date()) // 周日=1
        return d == 1 ? 7 : d - 1
    }

    private static func doBrowseTasks(cookie: String, onLog: @escaping (String) -> Void) async -> Int {
        onLog("每日任务：浏览活动")
        let list = await DjcClient.getIgw(
            service: "app.activity.list",
            extra: [
                "act_type": "38466",
                "origin_page": "fullPage",
                "page_size": "10",
                "djc_from": "kuikly",
            ],
            pName: "activity_home",
            postBody: "",
            rawCookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let titles = matches(list.body, #""sTitle"\s*:\s*"([^"]+)""#)
        let ids = matches(list.body, #""iInfoId"\s*:\s*"?(\d+)"#)
        let pics = matches(list.body, #""djImageBigAddr"\s*:\s*"([^"]*)""#)
        var n = 0
        let count = min(3, ids.count)
        for i in 0..<count {
            let id = ids[i]
            let title = i < titles.count ? titles[i] : "活动\(id)"
            let pic = i < pics.count ? pics[i] : ""
            onLog("浏览-\(title)")
            _ = await DjcClient.getIgw(
                service: "app.activity.detail",
                extra: ["actId": id, "w_id": "172"],
                pName: "activity_detail",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            _ = await DjcClient.getIgw(
                service: "app.activity.comment_list",
                extra: [
                    "docid": id, "page": "1", "_biz_code": "actdaoju",
                    "sort": "ai_djc_release_score_int",
                ],
                pName: "activity_detail",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            _ = await DjcClient.getIgw(
                service: "app.feeds.userrecordV2",
                extra: [
                    "id": id, "title": title, "pic": pic, "_biz_code": "actdaoju",
                    "record_type": "activity", "comment_num": "100",
                ],
                pName: "activity_detail",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            _ = await DjcClient.getIgw(
                service: "app.task.report",
                extra: ["djc_from": "kuikly", "task_type": "activity_card"],
                pName: "activity_home",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            n += 1
        }
        if n == 0 { onLog("无可浏览活动") }
        return n
    }

    private static func doRushTasks(cookie: String, onLog: @escaping (String) -> Void) async -> Int {
        let page = await DjcClient.getIgw(
            service: "welink.usertask.swoole",
            extra: ["optype": "get_usertask_list"],
            pName: "bean_view_liteapp",
            rawCookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let ruleIds = Array(Set(matches(page.body, #""iruleId"\s*:\s*"?(\d+)"#))).prefix(5)
        var n = 0
        for rid in ruleIds {
            let r = await DjcClient.getIgw(
                service: "welink.usertask.swoole",
                extra: ["optype": "report_usertask_rushtime", "ruleid": rid],
                pName: "bean_view_liteapp",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let msg = jsonMsg(r.body)
            if !msg.isEmpty { onLog("冲刺任务\(rid):\(msg)") }
            n += 1
        }
        return n
    }

    private static func doLeiJi(
        cookie: String, role: DjcClient.YxzjRole, onLog: @escaping (String) -> Void
    ) async -> Int {
        onLog("累计奖励开始")
        let list = await DjcClient.getIgw(
            service: "app.package.list",
            extra: [
                "output_format": "json",
                "optype": "get_user_package_list",
                "bizcode": "yxzj",
                "_biz_code": "yxzj",
                "showType": "qq",
            ],
            postBody: "",
            rawCookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        let day = "\(weekdayMon1())"
        let blocks = blockMatches(list.body, key: "iruleId")
        var n = 0
        for b in blocks {
            guard let irule = firstMatch(b, #""iruleId"\s*:\s*"?(\d+)"#),
                  let status = Int(firstMatch(b, #""iStatus"\s*:\s*"?(\d+)"#) ?? ""),
                  let recv = Int(firstMatch(b, #""iReceive"\s*:\s*"?(\d+)"#) ?? "")
            else { continue }
            let task = firstMatch(b, #""sTask"\s*:\s*"([^"]*)""#) ?? ""
            if status != 1 || recv != 0 { continue }
            if !task.isEmpty && !task.contains(day) { continue }
            let r = await DjcClient.getIgw(
                service: "app.package.receive",
                extra: [
                    "output_format": "json",
                    "optype": "receive_usertask_game",
                    "iruleId": irule,
                    "bizcode": "yxzj",
                    "_biz_code": "yxzj",
                    "roleCode": role.roleCode,
                    "systemID": "1",
                    "channelID": "1",
                    "sRoleName": role.roleName,
                    "sPartition": "\(role.partition)",
                    "channelKey": "qq",
                    "area": "1",
                    "partition": "\(role.partition)",
                    "version": "4",
                ],
                postBody: "",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("累计领:\(irule) \(jsonMsg(r.body))")
            n += 1
            break
        }
        if n == 0 { onLog("累计无可领包") }
        return n
    }

    private static func doXuYuan(
        cookie: String, role: DjcClient.YxzjRole, onLog: @escaping (String) -> Void
    ) async -> Int {
        onLog("许愿池清理（\(role.roleName)）")
        var deleted = 0
        for _ in 0..<5 {
            let page = await DjcClient.getIgw(
                service: "app.demand.user.demand",
                extra: [
                    "biz_set": "cf,cfm,yxzj,lol,nz",
                    "pn": "1",
                    "ps": "5",
                    "appUid": "",
                ],
                pName: "wishing_my_wish_liteapp",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            let total = Int(firstMatch(page.body, #""total"\s*:\s*"?(\d+)"#) ?? "0") ?? 0
            let keys = matches(page.body, #""sKeyId"\s*:\s*"([^"]+)""#)
            let names = matches(page.body, #""sGoodsName"\s*:\s*"([^"]*)""#)
            if total == 0 || keys.isEmpty { break }
            onLog("许愿池共\(total)，删除中")
            for (i, key) in keys.enumerated() {
                _ = await DjcClient.getIgw(
                    service: "app.demand.delete",
                    extra: ["output_format": "jsonp", "sKeyId": key],
                    pName: "wishing_my_wish_liteapp",
                    rawCookie: cookie
                )
                try? await Task.sleep(nanoseconds: gapNs)
                onLog("删除许愿-\(i < names.count ? names[i] : key)")
                deleted += 1
            }
        }
        onLog("删除许愿道具结束（共\(deleted)）")
        let goods = await DjcClient.getIgw(
            service: "app.goods.list",
            extra: [
                "sBizCode": "yxzj",
                "iPartition": "\(role.partition)",
                "iZoneId": role.zoneId,
                "sRoleId": role.roleCode,
            ],
            pName: "wishing_my_wish_liteapp",
            rawCookie: cookie
        )
        try? await Task.sleep(nanoseconds: gapNs)
        if let propId = firstMatch(goods.body, #""propId"\s*:\s*"?(\d+)"#),
           let actId = firstMatch(goods.body, #""actId"\s*:\s*"?(\d+)"#)
        {
            let create = await DjcClient.getIgw(
                service: "app.demand.create",
                extra: [
                    "iActionId": actId,
                    "iGoodsId": propId,
                    "sBizCode": "yxzj",
                    "partition": "\(role.partition)",
                    "iZoneId": role.zoneId,
                    "platid": "0",
                    "sZoneDesc": "手Q-安卓(android)",
                    "sRoleId": role.roleCode,
                    "sRoleName": role.roleName,
                    "sGetterDream": "不要888！不要488！9.98带回家",
                ],
                pName: "wishing_my_wish_liteapp",
                postBody: "",
                rawCookie: cookie
            )
            try? await Task.sleep(nanoseconds: gapNs)
            onLog("新建许愿:\(jsonMsg(create.body))")
            deleted += 1
        } else {
            onLog("无可许愿商品（已完成清理）")
        }
        return max(deleted, 1)
    }

    private static func matches(_ text: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        matches(text, pattern).first
    }

    private static func blockMatches(_ text: String, key: String) -> [String] {
        let p = "\\{[^{}]*\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"?\\d+[^{}]*\\}"
        guard let re = try? NSRegularExpression(pattern: p) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }
}
