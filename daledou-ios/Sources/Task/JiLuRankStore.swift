import Foundation

/// 真源：`JiLuRankStore` — 武林/群侠月历 + 历史/商会按账号本地持久化。
@MainActor
final class JiLuRankStore: ObservableObject {
    static let shared = JiLuRankStore()

    @Published private(set) var revision = 0
    @Published var userName: String = "自己"
    @Published var accountUin: String = ""

    private let defaults = UserDefaults.standard
    private let prefix = "daledou.jilu."

    private init() {
        let u = defaults.string(forKey: prefix + "user")?.trimmingCharacters(in: .whitespaces) ?? ""
        userName = u.isEmpty ? "自己" : u
        accountUin = defaults.string(forKey: prefix + "uin")?.filter(\.isNumber) ?? ""
    }

    func bindAccount(uin: String, nameHint: String = "") {
        let digits = uin.filter(\.isNumber)
        if !digits.isEmpty {
            accountUin = digits
            defaults.set(digits, forKey: prefix + "uin")
        }
        if !nameHint.isEmpty && !nameHint.hasPrefix("QQ ") {
            userName = nameHint
            defaults.set(nameHint, forKey: prefix + "user")
        }
        bump()
    }

    func loadMonth(kind: JiLuKind, year: Int, month: Int) -> JiLuMonth {
        let key = storageKey(kind: kind, year: year, month: month)
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(JiLuMonth.self, from: data),
           !decoded.list.isEmpty
        {
            return recount(kind: kind, year: year, month: month, data: decoded)
        }
        let fresh = buildEmptyMonth(kind: kind, year: year, month: month)
        saveMonth(kind: kind, year: year, month: month, monthData: fresh)
        return fresh
    }

    func setDayRank(kind: JiLuKind, year: Int, month: Int, day: Int, rank: String) {
        guard day > 0 else { return }
        var current = loadMonth(kind: kind, year: year, month: month)
        let type = rank == "空白" ? "" : rank
        var list = current.list
        var found = false
        for i in list.indices where list[i].index == day {
            list[i].type = type
            found = true
        }
        if !found {
            list.append(JiLuDay(index: day, type: type))
            list.sort { a, b in
                if a.index == 0 { return true }
                if b.index == 0 { return false }
                return a.index < b.index
            }
        }
        current.list = list
        let next = recount(kind: kind, year: year, month: month, data: current)
        saveMonth(kind: kind, year: year, month: month, monthData: next)
        bump()
    }

    func saveLiShiDay(year: Int, month: Int, day: LiShiDay) {
        var map = loadLiShiMonth(year: year, month: month)
        let prev = map[day.day]
        let baseline: String = {
            if !day.dayExp.isEmpty { return day.dayExp }
            if let p = prev, !p.dayExp.isEmpty { return p.dayExp }
            let earlier = map.values
                .filter { $0.day < day.day && JiLuExp.parse($0.exp) != nil }
                .max(by: { $0.day < $1.day })
            if let e = earlier, !e.exp.isEmpty { return e.exp }
            return day.exp
        }()
        var merged = day
        merged.dayExp = baseline
        map[day.day] = merged
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: liShiKey(year: year, month: month))
        }
        if !day.name.isEmpty && day.name != "?" {
            userName = day.name
            defaults.set(day.name, forKey: prefix + "user")
        }
        bump()
    }

    /// 年历史：每月取首尾有记录的快照，合成「当月经验」。
    func loadYearSummary(year: Int) -> [LiShiDay] {
        var out: [LiShiDay] = []
        for m in 1...12 {
            let days = loadLiShiMonth(year: year, month: m).values.sorted { $0.day < $1.day }
            guard !days.isEmpty else { continue }
            let first = days.first(where: { !$0.dayExp.isEmpty }) ?? days[0]
            let last = days.last(where: { !$0.dayExp.isEmpty }) ?? days[days.count - 1]
            let monthExp: String = {
                if let a = JiLuExp.parse(first.exp), let b = JiLuExp.parse(last.exp), b >= a {
                    return "\(b - a)"
                }
                return "—"
            }()
            var row = last
            row.day = m
            row.dayExp = monthExp
            out.append(row)
        }
        return out
    }

    func loadLiShiMonth(year: Int, month: Int) -> [Int: LiShiDay] {
        guard let data = defaults.data(forKey: liShiKey(year: year, month: month)),
              let map = try? JSONDecoder().decode([Int: LiShiDay].self, from: data)
        else { return [:] }
        return map
    }

    func saveShangHuiDay(year: Int, month: Int, day: ShangHuiDay) {
        var map = loadShangHuiMonth(year: year, month: month)
        map[day.day] = day
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: shangHuiKey(year: year, month: month))
        }
        bump()
    }

    func loadShangHuiMonth(year: Int, month: Int) -> [Int: ShangHuiDay] {
        guard let data = defaults.data(forKey: shangHuiKey(year: year, month: month)),
              let map = try? JSONDecoder().decode([Int: ShangHuiDay].self, from: data)
        else { return [:] }
        return map
    }

    private func bump() { revision &+= 1 }

    private func keyPrefix() -> String {
        accountUin.isEmpty ? userName : "uin_\(accountUin)"
    }

    private func storageKey(kind: JiLuKind, year: Int, month: Int) -> String {
        let suffix = "\(year)年\(month)月"
        switch kind {
        case .wuLin: return prefix + keyPrefix() + suffix
        case .qunXia: return prefix + keyPrefix() + "_QUNXIA" + suffix
        }
    }

    private func liShiKey(year: Int, month: Int) -> String {
        prefix + "lishi." + keyPrefix() + ".\(year).\(month)"
    }

    private func shangHuiKey(year: Int, month: Int) -> String {
        prefix + "shanghui." + keyPrefix() + ".\(year).\(month)"
    }

    private func saveMonth(kind: JiLuKind, year: Int, month: Int, monthData: JiLuMonth) {
        if let data = try? JSONEncoder().encode(monthData) {
            defaults.set(data, forKey: storageKey(kind: kind, year: year, month: month))
        }
    }

    private func recount(kind: JiLuKind, year: Int, month: Int, data: JiLuMonth) -> JiLuMonth {
        var map = Dictionary(uniqueKeysWithValues: JiLuRanks.counted.map { ($0, 0) })
        for d in data.list {
            let t = d.type.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, map[t] != nil {
                map[t, default: 0] += 1
            }
        }
        let boxes = JiLuBoxes.compute(kind: kind, counts: map, year: year, month: month, list: data.list)
        return JiLuMonth(list: data.list, counts: map, boxes: boxes)
    }

    private func buildEmptyMonth(kind: JiLuKind, year: Int, month: Int) -> JiLuMonth {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = cal.date(from: comps) else {
            return recount(kind: kind, year: year, month: month, data: JiLuMonth(list: [], counts: [:], boxes: [0, 0, 0, 0, 0]))
        }
        let weekStart = cal.component(.weekday, from: first) // 周日=1
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var list: [JiLuDay] = []
        for _ in 1..<weekStart {
            list.append(JiLuDay(index: 0, type: ""))
        }
        for d in 1...daysInMonth {
            list.append(JiLuDay(index: d, type: ""))
        }
        return recount(kind: kind, year: year, month: month, data: JiLuMonth(list: list, counts: [:], boxes: []))
    }
}
