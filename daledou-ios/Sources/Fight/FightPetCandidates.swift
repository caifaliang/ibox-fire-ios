import Foundation

/// phonepk 战报页 → petpk 动画 Act 候选接口（对齐 Android `phoneViewFightPetCandidates`）
enum FightPetCandidates {
    private static let petBase = "https://fight.pet.qq.com/cgi-bin/petpk"

    static func urls(from phoneUrl: String) -> [String] {
        guard let comps = URLComponents(string: phoneUrl) else { return [] }
        let items = comps.queryItems ?? []
        func q(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value?.nilIfEmpty
        }
        guard let id = q("id") ?? q("repid") else { return [] }
        let type = q("type") ?? ""
        let idMid = id.split(separator: "_").dropFirst().first.map(String.init) ?? ""
        let kind = type.isEmpty ? idMid : type
        let urlLow = phoneUrl.lowercased()

        var out = [String]()
        var seen = Set<String>()

        func add(_ cmd: String, extras: [String: String] = [:]) {
            var c = URLComponents(string: petBase)!
            var qs: [URLQueryItem] = [URLQueryItem(name: "cmd", value: cmd)]
            for (k, v) in extras { qs.append(URLQueryItem(name: k, value: v)) }
            let skipAutoId = extras.keys.contains("id") || extras.keys.contains("repid")
                || ["knightfight", "arena", "knightarena", "ascendheaven", "jianghudream",
                    "abyss_tide", "couplefight", "thronesbattle", "sectmelee", "tbattle"].contains(cmd)
            if !skipAutoId {
                qs.append(URLQueryItem(name: "id", value: id))
            }
            c.queryItems = qs
            guard let s = c.url?.absoluteString, seen.insert(s).inserted else { return }
            out.append(s)
        }

        func addCouple() { add("couplefight", extras: ["subtype": "6", "id": id]) }
        func addArena() { add("arena", extras: ["op": "replay", "repid": id]) }
        func addHuashan() { add("knightarena", extras: ["op": "replay", "repid": id]) }
        func addThrones() { add("thronesbattle", extras: ["op": "showreplay", "repid": id]) }
        func addSectMelee() { add("sectmelee", extras: ["op": "showreplay", "repid": id]) }
        func addTbattle() { add("tbattle", extras: ["op": "showreplay", "repid": id]) }
        func addFeisheng() {
            add("ascendheaven", extras: ["op": "view_my_replay", "id": id])
            add("ascendheaven", extras: ["op": "view_replay", "id": id])
        }
        func addJianghu() {
            add("jianghudream", extras: ["op": "view_my_replay", "id": id])
            add("jianghudream", extras: ["op": "view_replay", "id": id])
        }
        func addAbyss() {
            add("abyss_tide", extras: ["op": "view_my_replay", "id": id])
            add("abyss_tide", extras: ["op": "view_replay", "id": id])
        }
        func addQunxia() {
            add("knightfight", extras: ["op": "view_my_replay", "id": id])
            add("knightfight", extras: ["op": "view_replay", "id": id])
        }
        func addWulin(withType1: Bool = false) {
            if withType1 { add("showwulinrep", extras: ["id": id, "type": "1"]) }
            add("showwulinrep")
        }
        func addViewfight(_ t: String? = nil) {
            if let t, !t.isEmpty {
                add("viewfight", extras: ["type": t])
            } else {
                add("viewfight")
            }
        }

        switch true {
        case urlLow.contains("thronesbattle"):
            addThrones(); addViewfight(type.nilIfEmpty)
        case urlLow.contains("sectmelee"), urlLow.contains("secttournament"):
            addSectMelee(); addViewfight(type.nilIfEmpty)
        case urlLow.contains("cmd=tbattle"), urlLow.contains("&cmd=tbattle"):
            addTbattle(); addViewfight(type.nilIfEmpty)
        case urlLow.contains("knightarena"):
            addHuashan(); addViewfight(type.isEmpty ? "1" : type)
        case urlLow.contains("jianghudream"):
            addJianghu(); addViewfight(type.nilIfEmpty)
        case urlLow.contains("abyss"):
            addAbyss(); addViewfight(type.nilIfEmpty)
        case urlLow.contains("ascendheaven"):
            addFeisheng(); addViewfight(type.nilIfEmpty)
        case urlLow.contains("cmd=arena") && !urlLow.contains("knightarena"):
            addArena(); addViewfight(type.isEmpty ? "13" : type)
        case urlLow.contains("cfight"), urlLow.contains("couple"), urlLow.contains("xialv"):
            addCouple(); addViewfight(type.isEmpty ? "3" : type)
        case urlLow.contains("recommendmanor"), urlLow.contains("manorfight"):
            addWulin(withType1: true); addViewfight(type.isEmpty ? "1" : type)
        case type == "13", type == "26":
            addArena(); addViewfight(type)
        case type == "12":
            addAbyss(); addViewfight("12")
        case type == "11":
            addFeisheng(); addViewfight("11")
        case type == "10":
            addJianghu(); addViewfight("10")
        case type == "9", type == "24":
            addQunxia(); addViewfight(type)
        case type == "3", type == "2":
            if idMid == "2" && type == "2" {
                addThrones(); addCouple(); addWulin(); addViewfight(type)
            } else {
                addCouple(); addWulin(); addViewfight(type)
            }
        case type == "4":
            addTbattle(); addWulin(); addViewfight("4")
        case type == "1":
            if idMid == "1" {
                addHuashan(); addWulin(withType1: true); addViewfight("1")
            } else {
                addWulin(withType1: true); addHuashan(); addViewfight("1")
            }
        case kind == "6":
            addFeisheng(); addViewfight()
        case kind == "10":
            addCouple(); addAbyss(); addJianghu(); addViewfight()
        case kind == "5":
            addSectMelee(); addJianghu(); addWulin(withType1: true); addViewfight()
        case kind == "4":
            addTbattle(); addWulin(); addViewfight()
        case kind == "2":
            addThrones(); addCouple(); addWulin(); addViewfight()
        case kind == "1":
            addHuashan(); addViewfight(); addWulin()
        case urlLow.contains("knight"):
            addQunxia(); addHuashan(); addViewfight()
        default:
            addViewfight(type.nilIfEmpty)
            addThrones(); addSectMelee(); addTbattle(); addCouple()
            addJianghu(); addWulin(withType1: true); addAbyss()
            addFeisheng(); addHuashan(); addArena()
        }

        let preferHide = urlLow.contains("hide_knight=1")
        var hideVariants = [String]()
        for u in out where u.lowercased().contains("cmd=viewfight") && !u.contains("hide_knight=") {
            hideVariants.append(u.contains("?") ? "\(u)&hide_knight=1" : "\(u)?hide_knight=1")
        }
        if preferHide {
            var reordered = [String]()
            var seen2 = Set<String>()
            for u in hideVariants + out where seen2.insert(u).inserted {
                reordered.append(u)
            }
            return reordered
        }
        for u in hideVariants where seen.insert(u).inserted {
            out.append(u)
        }
        return out
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
