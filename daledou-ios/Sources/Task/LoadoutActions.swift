import Foundation

struct LoadoutOpt: Identifiable, Hashable {
    var id: String
    var name: String
    /// 侠士：当前出战位 "0"/"1"；头像：正在使用为 "on"
    var extra: String
    var detail: String
}

/// 换装应用：装扮槽仍走 `farmYiJianHuanZhuang`；本文件接侠士 / 头像。
enum LoadoutActions {
    static func fetchKnights(cookie: String) async -> [LoadoutOpt] {
        var byId: [String: LoadoutOpt] = [:]
        var order: [String] = []
        for op in ["6", "5"] {
            let (_, body) = await LedouCGI.getPetPk(cmd: "knight", extra: ["teamid": "0", "op": op], cookie: cookie)
            guard let arr = jsonArray(body, key: "knights") else { continue }
            for item in arr {
                guard let o = item as? [String: Any] else { continue }
                let id = str(o["id"])
                if id.isEmpty { continue }
                if byId[id] == nil { order.append(id) }
                let prev = byId[id]
                let lv = str(o["level"])
                let talent = str(o["talentSkillName"]).ifEmpty(str(o["talentSkill"]))
                var detail = ""
                if !lv.isEmpty { detail = "Lv.\(lv)" }
                if !talent.isEmpty { detail = detail.isEmpty ? talent : "\(detail) · \(talent)" }
                let desc = str(o["desc"])
                if !desc.isEmpty {
                    let cut = String(desc.prefix(24))
                    detail = detail.isEmpty ? cut : "\(detail) · \(cut)"
                }
                byId[id] = LoadoutOpt(
                    id: id,
                    name: str(o["name"]).ifEmpty(prev?.name ?? id),
                    extra: str(o["teamPos"]).ifEmpty(prev?.extra ?? ""),
                    detail: detail.ifEmpty(prev?.detail ?? "")
                )
            }
        }
        return order.compactMap { byId[$0] }.sorted { $0.name < $1.name }
    }

    static func fetchAvatars(cookie: String) async -> (opts: [LoadoutOpt], current: LoadoutOpt?) {
        let (_, body) = await LedouCGI.getPetPk(cmd: "profile", extra: ["op": "viewindex"], cookie: cookie)
        guard let root = jsonObject(body) else { return ([], nil) }
        var opts: [LoadoutOpt] = []
        if let arr = root["profiles"] as? [Any] {
            for item in arr {
                guard let o = item as? [String: Any] else { continue }
                if int(o["status"], default: 1) == 0 { continue }
                let id = str(o["id"])
                if id.isEmpty { continue }
                let desc = str(o["desc"]).replacingOccurrences(of: "乐斗基础佩戴外观，使用", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let attrs = attrsLine(o["attrs"])
                var detail = desc
                if !attrs.isEmpty { detail = detail.isEmpty ? attrs : "\(detail) · \(attrs)" }
                opts.append(LoadoutOpt(
                    id: id,
                    name: str(o["name"]),
                    extra: int(o["status"]) == 1 ? "on" : "",
                    detail: detail
                ))
            }
        }
        let curId = str(root["cur_id"])
        let cur: LoadoutOpt? = curId.isEmpty ? nil : LoadoutOpt(
            id: curId,
            name: str(root["cur_name"]),
            extra: "on",
            detail: ""
        )
        return (opts, cur)
    }

    /// trigger "1"…"3" → 该触发位下的佣兵。extra=="on" 表示当前已装备。
    static func fetchMercs(cookie: String) async -> [String: [LoadoutOpt]] {
        let (_, body) = await LedouCGI.getPetPk(cmd: "newmercenary", extra: ["sub": "0"], cookie: cookie)
        var map: [String: [LoadoutOpt]] = ["1": [], "2": [], "3": []]
        guard let arr = jsonArray(body, key: "array") else { return map }
        for item in arr {
            guard let o = item as? [String: Any] else { continue }
            let t = int(o["trigger"])
            if t < 1 || t > 3 { continue }
            let id = str(o["id"])
            if id.isEmpty { continue }
            map["\(t)", default: []].append(LoadoutOpt(
                id: id,
                name: str(o["name"]),
                extra: int(o["status"]) == 1 ? "on" : "",
                detail: ""
            ))
        }
        return map
    }

    /// storage "1"…"4"（青龙/白虎/朱雀/玄武）。
    static func fetchAoyi(cookie: String) async -> [String: [LoadoutOpt]] {
        var map: [String: [LoadoutOpt]] = [:]
        for sid in 1...4 {
            let (_, body) = await LedouCGI.getPetPk(
                cmd: "skillEnhance",
                extra: ["storageId": "\(sid)", "op": "6"],
                cookie: cookie
            )
            var list: [LoadoutOpt] = []
            if let arr = jsonArray(body, key: "skillList") {
                for item in arr {
                    guard let o = item as? [String: Any] else { continue }
                    let id = str(o["id"])
                    if id.isEmpty { continue }
                    list.append(LoadoutOpt(
                        id: id,
                        name: str(o["name"]),
                        extra: int(o["isEnhanced"]) == 1 ? "on" : "",
                        detail: ""
                    ))
                }
            }
            map["\(sid)"] = list
        }
        return map
    }

    /// 应用已接线槽位。空槽保持现状。
    static func applyWired(cfg: LoadoutConfig, cookie: String, onLog: (String) -> Void) async -> String {
        var parts: [String] = []
        if cfg.enabled["侠士"] == true {
            var ok = 0
            let slots = ["位置1", "位置2"]
            for pos in 0...1 {
                let token = cfg.knight["\(pos)"] ?? ""
                let kid = tokenId(token)
                if token.isEmpty || kid.isEmpty || kid == "0" { continue }
                let (_, body) = await LedouCGI.getPetPk(
                    cmd: "knight",
                    extra: ["pos": "\(pos)", "teamid": "0", "op": "7", "knightid": kid],
                    cookie: cookie
                )
                let msg = plain(body)
                if !msg.contains("失败"), !msg.contains("错误") { ok += 1 }
                onLog("侠士\(slots[pos])：\(tokenName(token)) → \(msg)")
            }
            parts.append("侠士\(ok)")
        }
        if cfg.enabled["头像"] == true {
            let id = tokenId(cfg.avatar)
            if !id.isEmpty, id != "0" {
                let (_, body) = await LedouCGI.getPetPk(
                    cmd: "profile",
                    extra: ["op": "setprofile", "id": id],
                    cookie: cookie
                )
                let msg = plain(body)
                onLog("头像：\(tokenName(cfg.avatar)) → \(msg)")
                parts.append("头像")
            }
        }
        if cfg.enabled["佣兵"] == true {
            let (_, liveBody) = await LedouCGI.getPetPk(cmd: "newmercenary", extra: ["sub": "0"], cookie: cookie)
            var equipped: [Int: String] = [:]
            if let arr = jsonArray(liveBody, key: "array") {
                for item in arr {
                    guard let o = item as? [String: Any], int(o["status"]) == 1 else { continue }
                    equipped[int(o["trigger"])] = str(o["id"])
                }
            }
            var ok = 0
            for i in 0..<LoadoutConfig.mercSlots.count {
                let trigger = i + 1
                let token = cfg.mercenary["\(trigger)"] ?? ""
                let mid = tokenId(token)
                if token.isEmpty || mid.isEmpty { continue }
                let body: String
                if mid == "0" {
                    let cur = equipped[trigger] ?? ""
                    if cur.isEmpty {
                        onLog("佣兵\(LoadoutConfig.mercSlots[i])：无需卸下")
                        continue
                    }
                    body = await LedouCGI.getPetPk(cmd: "newmercenary", extra: ["sub": "2", "id": cur], cookie: cookie).1
                } else if equipped[trigger] == mid {
                    onLog("佣兵\(LoadoutConfig.mercSlots[i])：已是 \(tokenName(token))，跳过")
                    ok += 1
                    continue
                } else {
                    body = await LedouCGI.getPetPk(cmd: "newmercenary", extra: ["sub": "1", "id": mid], cookie: cookie).1
                }
                let msg = plain(body)
                if !msg.contains("失败") { ok += 1 }
                onLog("佣兵\(LoadoutConfig.mercSlots[i])：\(tokenName(token)) → \(msg)")
            }
            parts.append("佣兵\(ok)")
        }
        if cfg.enabled["奥义"] == true {
            var ok = 0
            for i in 0..<LoadoutConfig.aoyiSlots.count {
                let storageId = i + 1
                let token = cfg.aoyi["\(storageId)"] ?? ""
                let sid = tokenId(token)
                if token.isEmpty || sid.isEmpty || sid == "0" { continue }
                let (_, body) = await LedouCGI.getPetPk(
                    cmd: "skillEnhance",
                    extra: ["storageId": "\(storageId)", "skillid": sid, "op": "7"],
                    cookie: cookie
                )
                let msg = plain(body)
                if !msg.contains("失败") { ok += 1 }
                onLog("奥义\(LoadoutConfig.aoyiSlots[i])：\(tokenName(token)) → \(msg)")
            }
            parts.append("奥义\(ok)")
        }
        return parts.joined(separator: " ")
    }

    static func tokenId(_ token: String) -> String {
        token.split(separator: "|", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    static func tokenName(_ token: String) -> String {
        let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count > 1, !parts[1].trimmingCharacters(in: .whitespaces).isEmpty {
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return parts.first?.trimmingCharacters(in: .whitespaces) ?? token
    }

    static func token(_ id: String, _ name: String) -> String {
        if id.isEmpty, name.isEmpty { return "" }
        return "\(id)|\(name)"
    }

    private static func jsonObject(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return o
    }

    private static func jsonArray(_ body: String, key: String) -> [Any]? {
        jsonObject(body)?[key] as? [Any]
    }

    private static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    private static func int(_ v: Any?, default d: Int = 0) -> Int {
        if let n = v as? Int { return n }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let n = Int(s) { return n }
        return d
    }

    private static func attrsLine(_ v: Any?) -> String {
        guard let arr = v as? [Any] else { return "" }
        var parts: [String] = []
        for item in arr {
            guard let o = item as? [String: Any] else { continue }
            let k = str(o["attrId"]).ifEmpty(str(o["name"]))
            let val = str(o["attrValue"]).ifEmpty(str(o["value"]))
            if !k.isEmpty || !val.isEmpty { parts.append(k + val) }
        }
        return parts.joined(separator: " ")
    }

    private static func plain(_ body: String) -> String {
        if let msg = jsonObject(body).flatMap({ str($0["msg"]).ifEmpty(str($0["message"])) }), !msg.isEmpty {
            return String(msg.prefix(60))
        }
        let stripped = body.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let one = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(one.prefix(60))
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
