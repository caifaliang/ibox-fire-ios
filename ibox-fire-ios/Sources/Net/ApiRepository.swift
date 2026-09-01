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
        var req = URLRequest(url: URL(string: "\(base())/auth/proxy")!)
        req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
        let (data, _) = try await siteSession().data(for: req)
        let o = jsonObject(data)
        return (o["extract_url"] as? String) ?? (o["proxy"] as? String) ?? ""
    }

    func consumeLocal(platformToken: String, kind: String) async throws -> QuotaInfo {
        let body = try JSONSerialization.data(withJSONObject: ["kind": kind])
        var req = URLRequest(url: URL(string: "\(base())/quota/consume-local")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, _) = try await siteSession().data(for: req)
        return parseQuota(jsonObject(data))
    }

    func searchCollections(_ q: String) async throws -> [CollHit] {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let url = URL(string: "\(base())/collections/search?q=\(enc)")!
        let (data, _) = try await siteSession().data(from: url)
        let o = jsonObject(data)
        let arr = (o["items"] as? [[String: Any]]) ?? (o["data"] as? [[String: Any]]) ?? []
        return arr.compactMap { row in
            let id = (row["id"] as? NSNumber)?.int64Value ?? Int64(row["id"] as? String ?? "") ?? 0
            let name = row["name"] as? String ?? ""
            guard id > 0 else { return nil }
            return CollHit(id: id, name: name)
        }
    }

    func announceSubscribe(platformToken: String, clientId: String = "") async throws -> (clientId: String, seq: Int64, alive: Bool) {
        var body: [String: Any] = [:]
        if !clientId.isEmpty { body["client_id"] = clientId }
        var req = URLRequest(url: URL(string: "\(base())/announce/subscribe")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await siteSession().data(for: req)
        let o = jsonObject(data)
        return (
            o["client_id"] as? String ?? clientId,
            (o["seq"] as? NSNumber)?.int64Value ?? 0,
            o["discoverer_alive"] as? Bool ?? false
        )
    }

    func announceFeed(platformToken: String, clientId: String, afterSeq: Int64) async throws -> [AnnounceFeedItem] {
        let url = URL(string: "\(base())/announce/feed?client_id=\(clientId)&after=\(afterSeq)")!
        var req = URLRequest(url: url)
        req.setValue(JwtUtil.bearer(platformToken), forHTTPHeaderField: "Authorization")
        let (data, _) = try await siteSession().data(for: req)
        let o = jsonObject(data)
        let arr = o["items"] as? [[String: Any]] ?? []
        return arr.map { row in
            var gids: [String: Int64] = [:]
            if let g = row["gids"] as? [String: Any] {
                for (k, v) in g {
                    if let n = v as? NSNumber { gids[k] = n.int64Value }
                }
            }
            return AnnounceFeedItem(
                noticeId: row["notice_id"] as? String ?? UUID().uuidString,
                seq: (row["seq"] as? NSNumber)?.int64Value ?? 0,
                title: row["title"] as? String ?? "",
                content: row["content"] as? String ?? "",
                gids: gids
            )
        }
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
        let body = try JSONSerialization.data(withJSONObject: ["phone": phone])
        var req = URLRequest(url: URL(string: "\(base())/snipe/sms-auto")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 90
        let (data, _) = try await siteSession(timeout: 90).data(for: req)
        let o = jsonObject(data)
        if o["status"] as? String != "ok" && o["ok"] as? Bool != true {
            throw NSError(domain: "sms", code: 1, userInfo: [NSLocalizedDescriptionKey: (o["message"] as? String) ?? "短信发送失败"])
        }
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
}
