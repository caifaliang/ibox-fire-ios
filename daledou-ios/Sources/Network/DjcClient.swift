import Foundation

/// 真源：`DjcClient` — 掌上道聚城 IGW / 聚豆兑换。
enum DjcClient {
    struct Result {
        var code: Int
        var body: String
    }

    struct YxzjRole {
        var zoneId: String
        var roleCode: String
        var roleName: String
        var partition: Int
    }

    static func sessionOrNull(rawCookie: String?) -> DjcAuth.Session? {
        DjcAuth.buildSession(rawCookie: rawCookie)
    }

    static func getIgw(
        service: String,
        extra: [String: String] = [:],
        referer: String = "https://daoju.qq.com/index.shtml",
        pName: String = "gift_bag_info_liteapp",
        postBody: String? = nil,
        rawCookie: String?
    ) async -> Result {
        guard let session = sessionOrNull(rawCookie: rawCookie) else {
            return Result(code: 0, body: "未登录道聚城（请菜单→扫码→道聚城）")
        }
        let sign = DjcAuth.sDjcSign(openId: session.oauth.openId, deviceId: session.deviceId)
        if sign.isEmpty { return Result(code: 0, body: "道聚城签名失败（检查 sss.der）") }
        let pTk = DjcAuth.pTk(session.oauth.accessToken)
        let reqId = DjcAuth.requestId(session.deviceId)
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "djcapp.game.qq.com"
        comps.path = "/daoju/igw/main/"
        var items: [URLQueryItem] = [
            .init(name: "_service", value: service),
            .init(name: "iAppId", value: "1001"),
            .init(name: "_app_id", value: "1001"),
            .init(name: "djc_from", value: "liteApp"),
            .init(name: "pName", value: pName),
            .init(name: "_output_fmt", value: "1"),
            .init(name: "appSource", value: "android"),
            .init(name: "ch", value: "10000"),
            .init(name: "appVersion", value: DjcAuth.appVersion),
            .init(name: "sVersionName", value: DjcAuth.versionName),
            .init(name: "osVersion", value: "Android-34"),
            .init(name: "sDeviceID", value: session.deviceId),
            .init(name: "djcRequestId", value: reqId),
            .init(name: "p_tk", value: "\(pTk)"),
            .init(name: "sDjcSign", value: sign),
        ]
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) {
            items.append(.init(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else { return Result(code: -1, body: "") }
        return await execute(url: url, session: session, referer: referer, postBody: postBody)
    }

    static func buyJudou(goodsSeqId: String, roleId: String, rawCookie: String?) async -> Result {
        let seq = Int(goodsSeqId) ?? 0
        let actionId: String
        let actionType: String
        if seq > 460 { actionId = "2603"; actionType = "27" }
        else if seq > 400 { actionId = "2603"; actionType = "25" }
        else { actionId = "2598"; actionType = "26" }
        return await getIgw(
            service: "buy.plug.swoole.judou",
            extra: [
                "_plug_id": "9800",
                "_from": "app",
                "iGoodsSeqId": goodsSeqId,
                "iActionId": actionId,
                "iActionType": actionType,
                "_biz_code": "fight",
                "biz": "fight",
                "lRoleId": roleId,
                "rolename": roleId,
                "_cs": "2",
            ],
            referer: "https://app.daoju.qq.com/jd/dhList.html",
            rawCookie: rawCookie
        )
    }

    static func queryYxzjRole(daQu: Int, rawCookie: String?) async -> YxzjRole? {
        guard let session = sessionOrNull(rawCookie: rawCookie) else { return nil }
        let sign = DjcAuth.sDjcSign(openId: session.oauth.openId, deviceId: session.deviceId)
        if sign.isEmpty { return nil }
        let pTk = DjcAuth.pTk(session.oauth.accessToken)
        let partition = daQu + 1010
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "yxzj.aci.game.qq.com"
        comps.path = "/main"
        comps.queryItems = [
            .init(name: "sCloudApiName", value: "ams.gameattr.role"),
            .init(name: "game", value: "yxzj"),
            .init(name: "area", value: "1"),
            .init(name: "partition", value: "1146"),
            .init(name: "returnCodec", value: "utf8"),
            .init(name: "iAmsActivityId", value: "tencent-daojucheng-yxzj"),
            .init(name: "sAMSAcctype", value: "qq"),
            .init(name: "sAMSAccessToken", value: session.oauth.accessToken),
            .init(name: "sAMSAppOpenId", value: session.oauth.openId),
            .init(name: "sAMSSourceAppId", value: "1101958653"),
            .init(name: "sAMSTargetAppId", value: "1104466820"),
            .init(name: "callback", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            .init(name: "sDeviceID", value: session.deviceId),
            .init(name: "sDjcSign", value: sign),
            .init(name: "appVersion", value: DjcAuth.appVersion),
            .init(name: "p_tk", value: "\(pTk)"),
            .init(name: "partition", value: "\(partition)"),
            .init(name: "platid", value: "0"),
            .init(name: "osVersion", value: "Android-34"),
            .init(name: "ch", value: "10000"),
            .init(name: "sVersionName", value: DjcAuth.versionName),
            .init(name: "appSource", value: "android"),
        ]
        guard let url = comps.url else { return nil }
        let body = await execute(url: url, session: session, referer: "https://daoju.qq.com/index.shtml", postBody: "").body
        let ns = body as NSString
        guard let re = try? NSRegularExpression(pattern: #"_webplat_msg=([^&"']+)"#),
              let m = re.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        let encoded = ns.substring(with: m.range(at: 1))
        guard let msg = encoded.removingPercentEncoding else { return nil }
        let parts = msg.replacingOccurrences(of: "|", with: "&").split(separator: "&").map(String.init)
        guard parts.count >= 2 else { return nil }
        let zoneId = parts[0].trimmingCharacters(in: .whitespaces)
        let roleParts = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
        let roleCode = roleParts.first ?? ""
        let roleName = (roleParts.count > 1 ? roleParts[1] : roleCode)
        let roleNameFinal = roleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? roleCode : roleName
        guard !zoneId.isEmpty, !roleCode.isEmpty else { return nil }
        return YxzjRole(zoneId: zoneId, roleCode: roleCode, roleName: roleNameFinal, partition: partition)
    }

    private static func execute(
        url: URL,
        session: DjcAuth.Session,
        referer: String,
        postBody: String?
    ) async -> Result {
        guard LedouCGI.isAllowedHost(url.host) else {
            return Result(code: -2, body: "拒绝非腾讯域名")
        }
        var req = URLRequest(url: url)
        if let postBody {
            req.httpMethod = "POST"
            req.httpBody = Data(postBody.utf8)
        } else {
            req.httpMethod = "GET"
        }
        req.setValue(session.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
        req.setValue("zh-cn", forHTTPHeaderField: "Accept-Language")
        req.setValue("UTF-8", forHTTPHeaderField: "charset")
        req.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = LedouCGI.decodeBody(data, response: resp as? HTTPURLResponse)
            return Result(code: code, body: body)
        } catch {
            return Result(code: -3, body: error.localizedDescription)
        }
    }
}
