import Foundation

struct SiteUser: Equatable {
    var token: String
    var username: String
    var isVip: Bool
    var isAdmin: Bool
    var isYearVip: Bool
    var isMonthVip: Bool = false
    var vipExpiresAt: String = ""
}

struct QuotaInfo: Equatable {
    var used: Int = 0
    var limit: Int = 0
    var remaining: Int = 0
    var unlimited: Bool = false
    var openNow: Bool = true
    var openHours: String = ""
}

struct CollHit: Identifiable, Equatable {
    var id: Int64
    var name: String
}

struct SynthActivity: Identifiable {
    var id: Int64
    var name: String
    var startTime: String = ""
    var maxSyntheticNum: Int64 = 0
}

struct SynthChannel: Identifiable {
    var id: Int64
    var name: String
}

struct SynthMaterial {
    var gid: Int64
    var name: String
    var albumId: Int64
}

struct ActivityDetail {
    var id: Int64
    var name: String
    var channels: [SynthChannel]
    var materials: [SynthMaterial]
}

struct PresaleItem: Identifiable {
    var id: Int64 { saleId }
    var saleId: Int64
    var name: String
    var price: Double
    var startTime: String = ""
}

struct AnnounceFeedItem: Identifiable {
    var id: String { noticeId }
    var noticeId: String
    var seq: Int64
    var title: String
    var content: String
    var gids: [String: Int64]
}

struct CaptchaToken {
    var lotNumber: String
    var captchaOutput: String
    var passToken: String
    var genTime: String
}

final class ApiRepository {
    var siteBase: String = "https://ai.iboxai.top/api"

    private func base() -> String { siteBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    private func siteSession(timeout: TimeInterval = 12) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        return URLSession(configuration: c)
    }

    private func jsonObject(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func parseQuota(_ o: [String: Any]) -> QuotaInfo {
        QuotaInfo(
            used: o["used"] as? Int ?? (o["used"] as? NSNumber)?.intValue ?? 0,
            limit: o["limit"] as? Int ?? (o["limit"] as? NSNumber)?.intValue ?? 0,
            remaining: o["remaining"] as? Int ?? (o["remaining"] as? NSNumber)?.intValue ?? 0,
            unlimited: o["unlimited"] as? Bool ?? false,
            openNow: o["open_now"] as? Bool ?? true,
            openHours: o["open_hours"] as? String ?? ""
        )
    }

    func siteLogin(username: String, password: String) async throws -> SiteUser {
        let body = try JSONSerialization.data(withJSONObject: [
            "username": username.trimmingCharacters(in: .whitespaces),
            "password": password
        ])
        var req = URLRequest(url: URL(string: "\(base())/auth/login")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await siteSession().data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let o = jsonObject(data)
        if code == 401 { throw NSError(domain: "site", code: 401, userInfo: [NSLocalizedDescriptionKey: "用户名或密码错误"]) }
        guard let token = o["token"] as? String, !token.isEmpty else {
            throw NSError(domain: "site", code: code, userInfo: [NSLocalizedDescriptionKey: (o["detail"] as? String) ?? "登录失败"])
        }
        return SiteUser(
            token: token,
            username: (o["username"] as? String) ?? username,
            isVip: o["is_vip"] as? Bool ?? false,
            isAdmin: o["is_admin"] as? Bool ?? false,
            isYearVip: o["is_year_vip"] as? Bool ?? false,
            isMonthVip: o["is_month_vip"] as? Bool ?? false,
            vipExpiresAt: "\(o["vip_expires_at"] ?? "")".replacingOccurrences(of: "null", with: "")
        )
    }

    func siteMe(platformToken: String) async throws -> SiteUser {
        var req = URLRequest(url: URL(string: "\(base())/auth/me")!)
        req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
        let (data, resp) = try await siteSession().data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            throw NSError(domain: "site", code: 401, userInfo: [NSLocalizedDescriptionKey: "登录已失效"])
        }
        let o = jsonObject(data)
        return SiteUser(
            token: platformToken,
            username: o["username"] as? String ?? "",
            isVip: o["is_vip"] as? Bool ?? false,
            isAdmin: o["is_admin"] as? Bool ?? false,
            isYearVip: o["is_year_vip"] as? Bool ?? false,
            isMonthVip: o["is_month_vip"] as? Bool ?? false,
            vipExpiresAt: "\(o["vip_expires_at"] ?? "")".replacingOccurrences(of: "null", with: "")
        )
    }

    func fetchUserProxy(platformToken: String) async throws -> String {
        // 对齐 Android：优先 /auth/user/proxy，兼容旧 /auth/proxy
        for path in ["/auth/user/proxy", "/auth/proxy"] {
            var req = URLRequest(url: URL(string: "\(base())\(path)")!)
            req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await siteSession().data(for: req),
                  ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 400 else { continue }
            let o = jsonObject(data)
            let url = (o["xiequ_url"] as? String) ?? (o["extract_url"] as? String) ?? (o["proxy"] as? String) ?? ""
            if !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return url }
        }
        return ""
    }

    func consumeLocal(platformToken: String, kind: String) async throws -> QuotaInfo {
        let body = try JSONSerialization.data(withJSONObject: [
            "platform_token": platformToken,
            "kind": kind
        ])
        var req = URLRequest(url: URL(string: "\(base())/snipe/local/consume")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 30
        let (data, resp) = try await siteSession(timeout: 30).data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let o = jsonObject(data)
        if code == 401 || code == 403 {
            throw NSError(domain: "quota", code: code, userInfo: [NSLocalizedDescriptionKey: (o["detail"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "无权限或登录过期"])
        }
        if o["status"] as? String != "ok" {
            throw NSError(domain: "quota", code: 1, userInfo: [NSLocalizedDescriptionKey: o["message"] as? String ?? "扣次失败"])
        }
        if let q = o["quota"] as? [String: Any] { return parseQuota(q) }
        return parseQuota(o)
    }

    /// NewBee 汇付自动支付（走网站 newbee_pay）
    func newbeeAutopay(
        nbToken: String,
        payPassword: String,
        orderId: String = "",
        buyMessage: String = "",
        buyData: [String: Any]? = nil,
        proxy: String = ""
    ) async throws -> (paid: Bool, message: String, orderId: String) {
        var body: [String: Any] = [
            "token": nbToken,
            "pay_password": payPassword,
            "proxy": proxy,
            "order_id": orderId,
            "buy_message": buyMessage
        ]
        if let buyData { body["buy_data"] = buyData }
        var req = URLRequest(url: URL(string: "\(base())/newbee/tech/autopay")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 45
        let (data, _) = try await siteSession(timeout: 45).data(for: req)
        let o = jsonObject(data)
        let paid = o["paid"] as? Bool ?? false
        let msg = (o["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (paid ? "支付成功" : "支付失败")
        return (paid, msg, o["order_id"] as? String ?? "")
    }

    /// NB 首发列表走网站（curl_cffi，避开 EdgeOne 拦直连）
    func fetchNbPresaleList(nbToken: String, proxy: String = "", page: Int = 1) async throws -> [NbPresaleItem] {
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        let url = URL(string: "\(base())/newbee/tech/presale/list?token=\(enc(nbToken))&proxy=\(enc(proxy))&page=\(page)&per_page=30")!
        let (data, _) = try await siteSession().data(from: url)
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.hasPrefix("<") {
            throw NSError(domain: "nb", code: 1, userInfo: [NSLocalizedDescriptionKey: "网站返回异常页，请检查网络/站点"])
        }
        let o = jsonObject(data)
        guard o["status"] as? String == "ok" else {
            throw NSError(domain: "nb", code: 1, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "获取首发列表失败"])
        }
        let arr = o["items"] as? [[String: Any]] ?? []
        return arr.compactMap { it in
            let pid = JSONX.int64Val(it["pid"]) ?? 0
            guard pid > 0 else { return nil }
            let lim = Int(JSONX.int64Val(it["limit"]) ?? 0)
            return NbPresaleItem(
                pid: pid,
                name: (it["name"] as? String)?.isEmpty == false ? (it["name"] as! String) : "PID \(pid)",
                price: JSONX.doubleVal(it["price"]) ?? 0,
                startTime: (it["start_time"] as? String) ?? "",
                limit: lim > 0 ? lim : nil
            )
        }
    }

    func fetchNbPresaleDetail(nbToken: String, pid: Int64, proxy: String = "") async throws -> NbPresaleItem {
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        let url = URL(string: "\(base())/newbee/tech/presale/detail?token=\(enc(nbToken))&proxy=\(enc(proxy))&id=\(pid)")!
        let (data, _) = try await siteSession().data(from: url)
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.hasPrefix("<") {
            throw NSError(domain: "nb", code: 1, userInfo: [NSLocalizedDescriptionKey: "网站返回异常页"])
        }
        let o = jsonObject(data)
        guard o["status"] as? String == "ok", let it = o["item"] as? [String: Any] else {
            throw NSError(domain: "nb", code: 1, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "获取详情失败"])
        }
        let p = JSONX.int64Val(it["pid"]) ?? pid
        let lim = Int(JSONX.int64Val(it["limit"]) ?? 0)
        return NbPresaleItem(
            pid: p,
            name: (it["name"] as? String)?.isEmpty == false ? (it["name"] as! String) : "PID \(p)",
            price: JSONX.doubleVal(it["price"]) ?? 0,
            startTime: (it["start_time"] as? String) ?? "",
            limit: lim > 0 ? lim : nil
        )
    }

    /// NB 市场搜索走网站转发（带会员 Authorization 可用私人代理）
    func searchNbMarket(nbToken: String, keywords: String, platformToken: String = "", proxy: String = "") async throws -> [NbMarketHit] {
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        let kw = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        var map: [Int64: NbMarketHit] = [:]
        for productType in [19, 25] {
            let urlStr = "\(base())/newbee/market/search?token=\(enc(nbToken))&proxy=\(enc(proxy))&page=1&per_page=20" +
                "&keywords=\(enc(kw))&product_type=\(productType)&time_type=1&sort=DESC&hot=0" +
                "&market_type=0&hasmarket=-1&order=fluctuation&collection_id="
            var req = URLRequest(url: URL(string: urlStr)!)
            if !platformToken.isEmpty {
                req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await siteSession().data(for: req)
            let o = jsonObject(data)
            if o["status"] as? String != "ok" {
                if map.isEmpty {
                    throw NSError(domain: "nb", code: 1, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "搜索失败"])
                }
                continue
            }
            for it in o["items"] as? [[String: Any]] ?? [] {
                let id = JSONX.int64Val(it["id"]) ?? 0
                guard id > 0, map[id] == nil else { continue }
                let floor = "\(it["floor"] ?? "")".replacingOccurrences(of: "null", with: "")
                map[id] = NbMarketHit(
                    id: id,
                    name: (it["name"] as? String)?.isEmpty == false ? (it["name"] as! String) : "PID \(id)",
                    floor: floor
                )
            }
            if !kw.isEmpty && map.values.contains(where: { $0.name.localizedCaseInsensitiveContains(kw) }) { break }
        }
        return Array(map.values)
    }

    func fetchSynthQuota(platformToken: String) async throws -> QuotaInfo {
        let enc = platformToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platformToken
        let (data, resp) = try await siteSession().data(from: URL(string: "\(base())/snipe/synth-quota?platform_token=\(enc)")!)
        let o = jsonObject(data)
        if (resp as? HTTPURLResponse)?.statusCode == 403 {
            throw NSError(domain: "quota", code: 403, userInfo: [NSLocalizedDescriptionKey: o["detail"] as? String ?? "需要 VIP"])
        }
        if o["status"] as? String == "error" {
            throw NSError(domain: "quota", code: 1, userInfo: [NSLocalizedDescriptionKey: o["message"] as? String ?? "额度查询失败"])
        }
        return parseQuota(o)
    }

    func fetchPresaleQuota(platformToken: String) async throws -> QuotaInfo {
        let enc = platformToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platformToken
        let (data, resp) = try await siteSession().data(from: URL(string: "\(base())/snipe/presale-quota?platform_token=\(enc)")!)
        let o = jsonObject(data)
        if (resp as? HTTPURLResponse)?.statusCode == 403 {
            throw NSError(domain: "quota", code: 403, userInfo: [NSLocalizedDescriptionKey: o["detail"] as? String ?? "需要 VIP"])
        }
        return parseQuota(o)
    }

    func fetchAnnounceQuota(platformToken: String) async throws -> QuotaInfo {
        let enc = platformToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platformToken
        let (data, resp) = try await siteSession().data(from: URL(string: "\(base())/snipe/announce-lock/quota?platform_token=\(enc)")!)
        let o = jsonObject(data)
        if (resp as? HTTPURLResponse)?.statusCode == 403 {
            throw NSError(domain: "quota", code: 403, userInfo: [NSLocalizedDescriptionKey: o["detail"] as? String ?? "需要月卡或年卡"])
        }
        return parseQuota(o)
    }

    func searchCollections(_ q: String) async throws -> [CollHit] {
        let qq = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qq.isEmpty else { return [] }
        let enc = qq.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? qq
        let url = URL(string: "\(base())/collections/search?q=\(enc)")!
        let (data, resp) = try await siteSession().data(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let arr: [[String: Any]]
        if text.hasPrefix("[") {
            arr = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        } else {
            let o = jsonObject(data)
            if code >= 400 {
                throw NSError(domain: "search", code: code, userInfo: [NSLocalizedDescriptionKey: o["detail"] as? String ?? "搜索失败 HTTP\(code)"])
            }
            arr = (o["items"] as? [[String: Any]])
                ?? (o["results"] as? [[String: Any]])
                ?? (o["data"] as? [[String: Any]])
                ?? ((o["data"] as? [String: Any])?["list"] as? [[String: Any]])
                ?? []
        }
        return arr.compactMap { row in
            let id = JSONX.int64Val(row["id"])
                ?? JSONX.int64Val(row["groupId"])
                ?? JSONX.int64Val(row["digitalCollectionGroupId"])
                ?? 0
            let name = (row["name"] as? String) ?? (row["title"] as? String) ?? ""
            guard id > 0 else { return nil }
            return CollHit(id: id, name: name.isEmpty ? "GID \(id)" : name)
        }
    }

    func announceSubscribe(platformToken: String, iboxToken: String, clientId: String = "") async throws -> (clientId: String, seq: Int64, alive: Bool) {
        var body: [String: Any] = [
            "platform_token": platformToken,
            "token": JwtUtil.normalize(iboxToken)
        ]
        if !clientId.isEmpty { body["client_id"] = clientId }
        var req = URLRequest(url: URL(string: "\(base())/snipe/announce-lock/subscribe")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await siteSession().data(for: req)
        let o = jsonObject(data)
        if (resp as? HTTPURLResponse)?.statusCode == 403 {
            throw NSError(domain: "announce", code: 403, userInfo: [NSLocalizedDescriptionKey: o["detail"] as? String ?? o["message"] as? String ?? "需要月卡或年卡"])
        }
        guard o["status"] as? String == "ok" else {
            throw NSError(domain: "announce", code: 1, userInfo: [NSLocalizedDescriptionKey: o["message"] as? String ?? "订阅失败"])
        }
        return (
            o["client_id"] as? String ?? clientId,
            (o["seq"] as? NSNumber)?.int64Value ?? 0,
            o["discoverer_alive"] as? Bool ?? false
        )
    }

    func announceFeed(platformToken: String, clientId: String, sinceSeq: Int64) async throws -> (seq: Int64, items: [AnnounceFeedItem]) {
        var comps = URLComponents(string: "\(base())/snipe/announce-lock/feed")!
        comps.queryItems = [
            URLQueryItem(name: "platform_token", value: platformToken),
            URLQueryItem(name: "since_seq", value: "\(sinceSeq)"),
            URLQueryItem(name: "client_id", value: clientId)
        ]
        var req = URLRequest(url: comps.url!)
        let (data, resp) = try await siteSession().data(for: req)
        let o = jsonObject(data)
        if (resp as? HTTPURLResponse)?.statusCode == 403 {
            throw NSError(domain: "announce", code: 403, userInfo: [NSLocalizedDescriptionKey: o["detail"] as? String ?? "需要月卡或年卡"])
        }
        guard o["status"] as? String == "ok" else {
            throw NSError(domain: "announce", code: 1, userInfo: [NSLocalizedDescriptionKey: o["message"] as? String ?? "feed 失败"])
        }
        let seq = (o["seq"] as? NSNumber)?.int64Value ?? sinceSeq
        let arr = o["items"] as? [[String: Any]] ?? []
        let items: [AnnounceFeedItem] = arr.map { row in
            var gids: [String: Int64] = [:]
            if let g = row["gids"] as? [String: Any] {
                for (k, v) in g {
                    if let n = v as? NSNumber { gids[k] = n.int64Value }
                }
            }
            return AnnounceFeedItem(
                noticeId: row["notice_id"] as? String ?? "",
                seq: (row["seq"] as? NSNumber)?.int64Value ?? 0,
                title: row["title"] as? String ?? "",
                content: row["content"] as? String ?? "",
                gids: gids
            )
        }
        return (seq, items)
    }

    func announceUnsubscribe(platformToken: String, clientId: String) async {
        guard !clientId.isEmpty else { return }
        let encPt = platformToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platformToken
        let encCid = clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId
        var req = URLRequest(url: URL(string: "\(base())/snipe/announce-lock/unsubscribe?platform_token=\(encPt)&client_id=\(encCid)")!)
        req.httpMethod = "POST"
        _ = try? await siteSession().data(for: req)
    }

    /// 服务端极验（三期本地求解前的降级路径）
    func presaleVerify(iboxToken: String, preferredProxy: String = "") async throws -> CaptchaToken {
        var body: [String: Any] = ["token": JwtUtil.normalize(iboxToken)]
        if !preferredProxy.isEmpty { body["proxy"] = preferredProxy }
        var req = URLRequest(url: URL(string: "\(base())/snipe/presale-verify")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 95
        let (data, _) = try await siteSession(timeout: 95).data(for: req)
        let o = jsonObject(data)
        guard o["status"] as? String == "ok" || o["lot_number"] != nil else {
            throw NSError(domain: "geetest", code: 1, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "验证失败"])
        }
        return CaptchaToken(
            lotNumber: o["lot_number"] as? String ?? "",
            captchaOutput: o["captcha_output"] as? String ?? "",
            passToken: o["pass_token"] as? String ?? "",
            genTime: o["gen_time"] as? String ?? ""
        )
    }

    func newbeeLogin(platformToken: String, mobile: String, password: String) async throws -> (token: String, userId: Int64, nickname: String) {
        let body = try JSONSerialization.data(withJSONObject: [
            "mobile": mobile.trimmingCharacters(in: .whitespaces),
            "password": password
        ])
        var req = URLRequest(url: URL(string: "\(base())/newbee/login")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
        req.httpBody = body
        req.timeoutInterval = 60
        let (data, resp) = try await siteSession(timeout: 60).data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            throw NSError(domain: "nb", code: 401, userInfo: [NSLocalizedDescriptionKey: "网站会员已失效"])
        }
        let o = jsonObject(data)
        guard o["status"] as? String == "ok", let token = o["token"] as? String, !token.isEmpty else {
            throw NSError(domain: "nb", code: 1, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "NB登录失败"])
        }
        return (
            token,
            (o["user_id"] as? NSNumber)?.int64Value ?? 0,
            o["nickname"] as? String ?? ""
        )
    }

    func sendSmsAuto(phone: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["phone": phone, "proxy": ""])
        var req = URLRequest(url: URL(string: "\(base())/snipe/send-sms-auto")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 90
        let (data, resp) = try await siteSession(timeout: 90).data(for: req)
        let o = jsonObject(data)
        let httpCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if httpCode >= 400 {
            throw NSError(domain: "sms", code: httpCode, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "HTTP \(httpCode)"])
        }
        if o["status"] as? String != "ok" && o["ok"] as? Bool != true {
            throw NSError(domain: "sms", code: 1, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "短信发送失败"])
        }
    }

    func loginSms(phone: String, code: String) async throws -> (token: String, uid: Int64) {
        let body = try JSONSerialization.data(withJSONObject: [
            "phoneNumber": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        var req = URLRequest(url: URL(string: "https://sail-api.ibox.art/box-server/api/v1/login/verify")!)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Dart/3.11 (dart:io)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await siteSession(timeout: 20).data(for: req)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "login", code: 1, userInfo: [NSLocalizedDescriptionKey: "响应无效"])
        }
        if obj["encryptKey"] != nil {
            let plain = try IboxCrypto.decryptResponse(String(data: data, encoding: .utf8) ?? "")
            obj = (try JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any]) ?? obj
        }
        if JSONX.code(obj) != 0 {
            throw NSError(domain: "login", code: Int(JSONX.code(obj)), userInfo: [NSLocalizedDescriptionKey: JSONX.message(obj)])
        }
        let d = JSONX.dataDict(obj)
        guard let tokenRaw = d["token"] as? String, !tokenRaw.isEmpty else {
            throw NSError(domain: "login", code: 2, userInfo: [NSLocalizedDescriptionKey: "无 token"])
        }
        let token = JwtUtil.normalize(tokenRaw)
        let uid = JSONX.int64Val((d["userInfo"] as? [String: Any])?["userId"]) ?? JwtUtil.uid(token) ?? 0
        return (token, uid)
    }

    func verifyIboxToken(_ token: String) throws -> (token: String, uid: Int64) {
        let t = JwtUtil.normalize(token)
        guard !t.isEmpty else { throw NSError(domain: "login", code: 1, userInfo: [NSLocalizedDescriptionKey: "Token 无效"]) }
        guard let uid = JwtUtil.uid(t) else { throw NSError(domain: "login", code: 2, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"]) }
        if JwtUtil.isExpired(t) { throw NSError(domain: "login", code: 3, userInfo: [NSLocalizedDescriptionKey: "Token 已过期"]) }
        return (t, uid)
    }

    // MARK: - iBox 直连 API

    private let iboxHost = "https://sail-api.ibox.art"

    func iboxGet(_ path: String, token: String) async throws -> [String: Any] {
        let p = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: iboxHost + p) else { throw NSError(domain: "ibox", code: 1) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let auth = JwtUtil.bearer(token)
        let dev = IboxClient.makeDeviceId(token)
        for (k, v) in [
            "Authorization": auth, "platform-type": "1", "channel": "website",
            "device-id": dev, "User-Agent": "Dart/3.11 (dart:io)",
            "accept": "application/json", "Content-Type": "application/json;charset=UTF-8"
        ] { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await siteSession(timeout: 20).data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 || status == 429 {
            return ["code": status, "message": "HTTP \(status)"]
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return ["code": -1, "message": "empty"] }
        guard var obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return ["code": status, "message": String(text.prefix(60))]
        }
        if obj["encryptKey"] != nil {
            let plain = try IboxCrypto.decryptResponse(text)
            obj = (try JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any]) ?? obj
        }
        return obj
    }

    func fetchActivities(q: String, token: String) async throws -> [SynthActivity] {
        let qq = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if qq.allSatisfy(\.isNumber), !qq.isEmpty {
            let d = try await fetchActivityDetail(id: Int64(qq) ?? 0, token: token)
            return [SynthActivity(id: d.id, name: d.name)]
        }
        var path = "/synthesis-service/synthetic/activity/list?pageNo=1&pageSize=20"
        if !qq.isEmpty {
            path += "&name=\(qq.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? qq)"
        }
        let data = try await iboxGet(path, token: token)
        if JSONX.code(data) != 0 { throw NSError(domain: "synth", code: Int(JSONX.code(data)), userInfo: [NSLocalizedDescriptionKey: JSONX.message(data)]) }
        let list = JSONX.dataDict(data)["list"] as? [[String: Any]] ?? []
        return list.compactMap { a in
            guard let id = JSONX.int64Val(a["id"]), id > 0 else { return nil }
            return SynthActivity(
                    id: id,
                name: a["name"] as? String ?? "活动 \(id)",
                startTime: "\(a["startTime"] ?? "")".replacingOccurrences(of: "null", with: ""),
                maxSyntheticNum: JSONX.int64Val(a["userMaxSyntheticNum"]) ?? JSONX.int64Val(a["maxSyntheticNum"]) ?? 0
            )
        }
    }

    func fetchActivityDetail(id: Int64, token: String) async throws -> ActivityDetail {
        let data = try await iboxGet("/synthesis-service/synthetic/activity/detail?id=\(id)", token: token)
        if JSONX.code(data) != 0 { throw NSError(domain: "synth", code: Int(JSONX.code(data)), userInfo: [NSLocalizedDescriptionKey: JSONX.message(data)]) }
        let a = JSONX.dataDict(data)
        let chArr = a["channels"] as? [[String: Any]] ?? []
        let channels = chArr.compactMap { ch -> SynthChannel? in
            guard let cid = JSONX.int64Val(ch["syntheticActivityId"]), cid > 0 else { return nil }
            return SynthChannel(id: cid, name: ch["name"] as? String ?? "通道 \(cid)")
        }
        let materials = try await channels.first.asyncMap { try await fetchChannelMaterials(centerId: $0.id, token: token) } ?? []
        return ActivityDetail(
            id: JSONX.int64Val(a["id"]) ?? id,
            name: a["name"] as? String ?? "活动 \(id)",
            channels: channels,
            materials: materials
        )
    }

    func fetchChannelMaterials(centerId: Int64, token: String) async throws -> [SynthMaterial] {
        let data = try await iboxGet("/synthesis-service/synthetic/center/\(centerId)", token: token)
        if JSONX.code(data) != 0 { throw NSError(domain: "synth", code: Int(JSONX.code(data)), userInfo: [NSLocalizedDescriptionKey: JSONX.message(data)]) }
        let c = JSONX.dataDict(data)
        let burn = c["burnAlbums"] as? [[String: Any]] ?? []
        var out: [SynthMaterial] = []
        for bg in burn {
            let gid = JSONX.int64Val(bg["groupId"]) ?? 0
            let albums = bg["albums"] as? [[String: Any]] ?? []
            for alb in albums {
                if let aid = JSONX.int64Val(alb["id"]), aid > 0 {
                    out.append(SynthMaterial(gid: gid, name: alb["name"] as? String ?? "材料", albumId: aid))
                }
            }
        }
        return out
    }

    func fetchPresaleList(iboxToken: String, proxyLine: String = "") async throws -> [PresaleItem] {
        let proxy = proxyLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proxy.isEmpty {
            let body = try JSONSerialization.data(withJSONObject: ["token": JwtUtil.normalize(iboxToken), "proxy": proxy, "page": 1])
            var req = URLRequest(url: URL(string: "\(base())/snipe/presale-list")!)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, _) = try await siteSession(timeout: 20).data(for: req)
            let o = jsonObject(data)
            if o["status"] as? String != "ok" {
                throw NSError(domain: "presale", code: 1, userInfo: [NSLocalizedDescriptionKey: o["message"] as? String ?? "列表失败"])
            }
            return parsePresaleItems(o["items"] as? [[String: Any]] ?? [])
        }
        let data = try await iboxGet("/public-service/sale-infos?pageNo=1&pageSize=20&sortField=0&sortType=1", token: iboxToken)
        if JSONX.code(data) != 0 { throw NSError(domain: "presale", code: Int(JSONX.code(data)), userInfo: [NSLocalizedDescriptionKey: JSONX.message(data)]) }
        return parsePresaleItems(JSONX.dataDict(data)["list"] as? [[String: Any]] ?? [])
    }

    private func parsePresaleItems(_ arr: [[String: Any]]) -> [PresaleItem] {
        arr.compactMap { a in
            let gid = a["digitalCollectionGroup"] as? [String: Any]
            let saleId = JSONX.int64Val(a["id"]) ?? JSONX.int64Val(a["saleId"]) ?? JSONX.int64Val(a["groupId"]) ?? 0
            guard saleId > 0 else { return nil }
            let name = (gid?["name"] as? String) ?? (a["name"] as? String) ?? "Sale \(saleId)"
            let price = JSONX.doubleVal(a["price"]) ?? JSONX.doubleVal(a["salePrice"]) ?? 0
            let start = "\(a["onSaleTime"] ?? a["startTime"] ?? a["saleTime"] ?? "")".replacingOccurrences(of: "null", with: "")
            return PresaleItem(saleId: saleId, name: name, price: price, startTime: start)
        }
    }

    struct SnipeLoopStart {
        let taskId: String
        let celery: Bool
        let message: String
    }

    struct SnipeTaskStatus {
        let status: String
        let logs: [[String: Any]]
        let bought: Int
    }

    func startSnipeLoop(
        iboxToken: String,
        platformToken: String,
        groupId: Int64,
        targetPrice: Double,
        quantity: Int,
        collectionName: String,
        buyMode: String,
        batchInterval: Double,
        autoPay: Bool,
        payPassword: String,
        proxy: String = ""
    ) async throws -> SnipeLoopStart {
        let body: [String: Any] = [
            "token": iboxToken,
            "platform_token": platformToken,
            "group_id": groupId,
            "target_price": targetPrice,
            "quantity": quantity,
            "collection_name": collectionName,
            "buy_mode": buyMode,
            "batch_interval": batchInterval,
            "auto_pay": autoPay,
            "pay_password": autoPay ? payPassword : "",
            "wxpusher_uid": "",
            "proxy": proxy,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: URL(string: "\(base())/snipe/start-loop")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 45
        let (raw, resp) = try await siteSession(timeout: 45).data(for: req)
        let o = jsonObject(raw)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 {
            throw NSError(domain: "snipe", code: code, userInfo: [NSLocalizedDescriptionKey: (o["detail"] as? String) ?? "无权限或登录过期"])
        }
        if o["status"] as? String != "ok" {
            throw NSError(domain: "snipe", code: 1, userInfo: [NSLocalizedDescriptionKey: o["message"] as? String ?? "启动失败"])
        }
        let tid = o["task_id"] as? String ?? ""
        if tid.isEmpty { throw NSError(domain: "snipe", code: 2, userInfo: [NSLocalizedDescriptionKey: "无 task_id"]) }
        return SnipeLoopStart(
            taskId: tid,
            celery: o["celery"] as? Bool ?? false,
            message: o["message"] as? String ?? ""
        )
    }

    func snipeStatus(taskId: String) async throws -> SnipeTaskStatus {
        let enc = taskId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? taskId
        var req = URLRequest(url: URL(string: "\(base())/snipe/status?task_id=\(enc)&_t=\(Int(Date().timeIntervalSince1970))")!)
        req.timeoutInterval = 15
        let (raw, _) = try await siteSession(timeout: 15).data(for: req)
        let o = jsonObject(raw)
        let logs = o["logs"] as? [[String: Any]] ?? []
        let bought = o["bought"] as? Int ?? (o["bought"] as? NSNumber)?.intValue ?? 0
        return SnipeTaskStatus(
            status: o["status"] as? String ?? "running",
            logs: logs,
            bought: bought
        )
    }

    func stopSnipeLoop(taskId: String) async {
        let enc = taskId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? taskId
        var req = URLRequest(url: URL(string: "\(base())/snipe/stop-loop?task_id=\(enc)")!)
        req.httpMethod = "POST"
        _ = try? await siteSession().data(for: req)
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await transform(e)) }
        return out
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let v = self else { return nil }
        return try await transform(v)
    }
}

enum JSONX {
    static func code(_ o: [String: Any]) -> Int64 {
        if let n = o["code"] as? NSNumber { return n.int64Value }
        if let i = o["code"] as? Int { return Int64(i) }
        if let s = o["code"] as? String, let i = Int64(s) { return i }
        return -1
    }
    static func message(_ o: [String: Any]) -> String { o["message"] as? String ?? o["msg"] as? String ?? "" }
    static func dataDict(_ o: [String: Any]) -> [String: Any] { o["data"] as? [String: Any] ?? [:] }
    static func dataList(_ o: [String: Any]) -> [[String: Any]] {
        if let a = dataDict(o)["list"] as? [[String: Any]] { return a }
        return []
    }
    static func doubleVal(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    static func int64Val(_ v: Any?) -> Int64? {
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String { return Int64(s) }
        return nil
    }
    static func stringVal(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        if let n = int64Val(v) { return "\(n)" }
        return ""
    }
}
