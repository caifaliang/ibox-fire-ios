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

    struct ZjLane {
        var storageId: String
        var weaponId: String
        var weaponName: String
    }

    struct ZjBoard {
        var typeIdx: Int
        var title: String
        var lanes: [ZjLane]
    }

    struct SpecializePack {
        var boards: [ZjBoard]
        var weapons: [String: [LoadoutOpt]]
    }

    static func fetchSpecialize(cookie: String, qq: String) async -> SpecializePack {
        let uin = qq.filter(\.isNumber)
        let zjBody: String
        if uin.isEmpty {
            zjBody = await LedouCGI.getPetPk(cmd: "weapon_specialize", extra: ["op": "0", "type_id": "0"], cookie: cookie).1
        } else {
            zjBody = await LedouCGI.getPetPk(cmd: "weapon_specialize", extra: ["op": "10", "op_uin": uin], cookie: cookie).1
        }
        var boards = parseSpecializeBoards(zjBody)
        var weapons: [String: LoadoutOpt] = [:]
        for b in boards {
            for lane in b.lanes where !lane.weaponName.isEmpty {
                let id = lane.weaponId.isEmpty ? lane.weaponName : lane.weaponId
                weapons[id] = LoadoutOpt(id: lane.weaponId, name: lane.weaponName, extra: "\(b.typeIdx)", detail: "")
            }
        }
        if !uin.isEmpty {
            let visit = await LedouCGI.getPetPk(cmd: "visit", extra: ["puin": uin, "kind": "1"], cookie: cookie).1
            for w in parseWeaponsFromVisit(visit) {
                let key = w.id.isEmpty ? w.name : w.id
                if weapons[key] == nil { weapons[key] = w }
            }
        }
        if boards.isEmpty {
            boards = (0..<LoadoutConfig.zjTypes.count).map { i in
                ZjBoard(
                    typeIdx: i,
                    title: LoadoutConfig.zjTypes[i],
                    lanes: (0..<3).map { li in
                        ZjLane(storageId: "\(i * 3 + 1000 + li)", weaponId: "", weaponName: "")
                    }
                )
            }
        }
        var byType: [String: [LoadoutOpt]] = [:]
        for w in weapons.values {
            byType[w.extra, default: []].append(w)
        }
        for k in byType.keys {
            byType[k]?.sort { $0.name < $1.name }
        }
        return SpecializePack(boards: boards, weapons: byType)
    }

    /// 应用已接线槽位。空槽保持现状。
    static func applyWired(cfg: LoadoutConfig, cookie: String, onLog: (String) -> Void) async -> String {
        var parts: [String] = []
        if cfg.enabled["专精"] == true {
            let qq = await MainActor.run { SessionStore.shared.qq }
            parts.append(await applySpecialize(cfg: cfg, cookie: cookie, qq: qq, onLog: onLog))
        }
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

    private static func applySpecialize(
        cfg: LoadoutConfig,
        cookie: String,
        qq: String,
        onLog: (String) -> Void
    ) async -> String {
        let pack = await fetchSpecialize(cookie: cookie, qq: qq)
        func liveMap(_ boards: [ZjBoard]) -> [String: ZjLane] {
            var map: [String: ZjLane] = [:]
            for b in boards {
                for (li, lane) in b.lanes.enumerated() {
                    var slot = lane
                    if slot.storageId.isEmpty { slot.storageId = "\(b.typeIdx * 3 + 1000 + li)" }
                    map[LoadoutConfig.zjKey(b.typeIdx, li)] = slot
                }
            }
            return map
        }
        var live = liveMap(pack.boards)
        var ok = 0, fail = 0, skip = 0
        for t in 0..<LoadoutConfig.zjTypes.count {
            for l in 0..<LoadoutConfig.zjLanes.count {
                let key = LoadoutConfig.zjKey(t, l)
                let token = cfg.specialize[key] ?? ""
                let storage = live[key]?.storageId ?? "\(t * 3 + 1000 + l)"
                let label = "专精\(LoadoutConfig.zjTypes[t])\(LoadoutConfig.zjLanes[l])"
                if token == "-" || token == "-|" || token.hasPrefix("-|") {
                    _ = await LedouCGI.getPetPk(cmd: "weapon_specialize", extra: ["op": "4", "storage_id": storage], cookie: cookie)
                    _ = await LedouCGI.getPetPk(cmd: "weapon_specialize", extra: ["op": "7", "storage_id": storage], cookie: cookie)
                    let body = await LedouCGI.getPetPk(
                        cmd: "weapon_specialize",
                        extra: ["op": "8", "storage_id": storage, "weapon_id": "0"],
                        cookie: cookie
                    ).1
                    let plainMsg = plain(body)
                    let after = await fetchSpecialize(cookie: cookie, qq: qq)
                    live = liveMap(after.boards)
                    let got = live[key]
                    let cleared = (got?.weaponId ?? "").isEmpty || (got?.weaponName ?? "").isEmpty
                    let success = cleared || plainMsg.contains("成功") || plainMsg.contains("卸下") || plainMsg.contains("解除")
                    if success { ok += 1 } else { fail += 1 }
                    onLog("\(label)：解除 → \(success ? "已空" : plainMsg)")
                    continue
                }
                let widRaw = tokenId(token)
                let wname = tokenName(token)
                if widRaw.isEmpty && wname.isEmpty { skip += 1; continue }
                let cgiWid = phoneWeaponId(widRaw)
                let liveWid = phoneWeaponId(live[key]?.weaponId ?? "")
                let liveName = live[key]?.weaponName ?? ""
                if cgiWid != "0", cgiWid == liveWid || (!wname.isEmpty && wname == liveName) {
                    skip += 1
                    onLog("\(label)：已是 \(wname)，跳过")
                    continue
                }
                _ = await LedouCGI.getPetPk(cmd: "weapon_specialize", extra: ["op": "4", "storage_id": storage], cookie: cookie)
                _ = await LedouCGI.getPetPk(cmd: "weapon_specialize", extra: ["op": "7", "storage_id": storage], cookie: cookie)
                let body = await LedouCGI.getPetPk(
                    cmd: "weapon_specialize",
                    extra: ["op": "8", "storage_id": storage, "weapon_id": cgiWid],
                    cookie: cookie
                ).1
                let plainMsg = plain(body)
                let after = await fetchSpecialize(cookie: cookie, qq: qq)
                live = liveMap(after.boards)
                let gotWid = phoneWeaponId(live[key]?.weaponId ?? "")
                let gotName = live[key]?.weaponName ?? ""
                let success = gotWid == cgiWid
                    || (!wname.isEmpty && gotName.contains(String(wname.prefix(2))))
                    || plainMsg.contains("成功")
                    || plainMsg.contains("装备")
                if success { ok += 1 } else { fail += 1 }
                onLog("\(label)：\(wname) → \(success ? "已生效(\(gotName))" : "未生效 \(plainMsg)")")
            }
        }
        return "专精成\(ok)/败\(fail)/跳\(skip)"
    }

    private static func phoneWeaponId(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard let n = Int(digits), n > 0 else { return "0" }
        return n < 1000 ? "\(n + 1000)" : "\(n)"
    }

    private static func parseSpecializeBoards(_ body: String) -> [ZjBoard] {
        guard let root = jsonObject(body) else { return [] }
        let arr = (root["dst_weapons0"] as? [Any]) ?? (root["src_weapons0"] as? [Any]) ?? []
        var out: [ZjBoard] = []
        for (i, item) in arr.enumerated() {
            guard let o = item as? [String: Any] else { continue }
            let typeName = str(o["type_name"])
            let typeIdx: Int
            if typeName.contains("投掷") { typeIdx = 0 }
            else if typeName.contains("小型") { typeIdx = 1 }
            else if typeName.contains("中型") { typeIdx = 2 }
            else if typeName.contains("大型") { typeIdx = 3 }
            else { typeIdx = min(3, i) }
            let stage = str(o["stage"])
            let level = str(o["level"])
            var title = LoadoutConfig.zjTypes[typeIdx]
            if !stage.isEmpty || !level.isEmpty {
                title += " \(stage)"
                if !level.isEmpty { title += "\(level)星" }
            }
            var lanes: [ZjLane] = []
            let storages = o["storages"] as? [Any] ?? []
            for si in 0..<min(3, storages.count) {
                guard let s = storages[si] as? [String: Any] else { continue }
                let sid = str(s["storage_id"])
                lanes.append(ZjLane(
                    storageId: sid.isEmpty ? "\(typeIdx * 3 + 1000 + si)" : sid,
                    weaponId: str(s["weapon_id"]),
                    weaponName: str(s["weapon_name"])
                ))
            }
            while lanes.count < 3 {
                let li = lanes.count
                lanes.append(ZjLane(storageId: "\(typeIdx * 3 + 1000 + li)", weaponId: "", weaponName: ""))
            }
            out.append(ZjBoard(typeIdx: typeIdx, title: title, lanes: lanes))
        }
        return out.sorted { $0.typeIdx < $1.typeIdx }
    }

    private static func parseWeaponsFromVisit(_ body: String) -> [LoadoutOpt] {
        guard let goods = jsonObject(body)?["goods"] as? String, !goods.isEmpty else { return [] }
        var out: [LoadoutOpt] = []
        for item in goods.split(separator: ";") {
            if item.isEmpty || item == "----" { continue }
            let lines = item.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let headLine = lines.first else { continue }
            let head = headLine.split(separator: ",").map(String.init)
            let tail = lines.last?.split(separator: ",").map(String.init) ?? []
            let rawName = head.first?.trimmingCharacters(in: .whitespaces) ?? ""
            if rawName.isEmpty { continue }
            let dmg = head.last ?? ""
            let typeIdx: Int
            if dmg.contains("投掷") || rawName.contains("投掷") { typeIdx = 0 }
            else if dmg.contains("小型") || rawName.contains("小型") { typeIdx = 1 }
            else if dmg.contains("中型") || rawName.contains("中型") { typeIdx = 2 }
            else if dmg.contains("大型") || rawName.contains("大型") { typeIdx = 3 }
            else { continue }
            let tailId = tail.count >= 2 ? Int(tail[tail.count - 2].trimmingCharacters(in: .whitespaces)) : nil
            let headId = head.count > 3 ? Int(head[3].trimmingCharacters(in: .whitespaces)) : nil
            var weaponId = tailId ?? headId ?? 0
            if weaponId >= 1000 { weaponId -= 1000 }
            if weaponId <= 0 { continue }
            let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            out.append(LoadoutOpt(id: "\(weaponId)", name: name, extra: "\(typeIdx)", detail: ""))
        }
        return out
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
