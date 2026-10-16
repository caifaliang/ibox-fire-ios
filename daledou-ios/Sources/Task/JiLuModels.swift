import Foundation

enum JiLuKind: String, Codable {
    case wuLin
    case qunXia
}

enum JiLuRanks {
    static let all: [String] = [
        "总冠", "总亚", "冠军", "亚军", "四强", "八强",
        "16强", "32强", "64强", "128", "256", "512", "1024", "2048", "空白",
    ]
    static let counted: [String] = all.filter { $0 != "空白" }
}

struct JiLuDay: Codable, Hashable, Identifiable {
    var id: Int { index }
    var index: Int
    var type: String
}

struct JiLuMonth: Codable, Hashable {
    var list: [JiLuDay]
    var counts: [String: Int]
    var boxes: [Int]
}

struct LiShiDay: Codable, Hashable {
    var day: Int
    var name: String
    var bangPai: String
    var dengJi: String
    var zhanLi: String
    var exp: String
    /// 当日经验基线（用于算增益）；年视图里复用为「当月经验」展示
    var dayExp: String = ""
}

enum JiLuExp {
    static func parse(_ raw: String) -> Int64? {
        let digits = raw.filter { $0.isNumber || $0 == "-" }
        guard !digits.isEmpty, let v = Int64(digits) else { return nil }
        return v
    }

    static func dailyGainText(_ row: LiShiDay) -> String {
        guard let cur = parse(row.exp), let base = parse(row.dayExp) else { return "—" }
        let d = cur - base
        return d >= 0 ? "\(d)" : "—"
    }
}

struct ShangHuiDay: Codable, Hashable {
    var day: Int
    var totalGiftNum: String
    var updateTime: Double
}

enum JiLuBoxes {
    static let wuLinLabels = ["碎片宝箱", "一级宝箱", "二级宝箱", "三级宝箱", "四级宝箱"]
    static let qunXiaLabels: [(Int, String)] = [
        (2, "侠士修身录"), (3, "侠士手记"), (4, "冠军侠士碎片"),
    ]

    static func compute(
        kind: JiLuKind,
        counts: [String: Int],
        year: Int,
        month: Int,
        list: [JiLuDay]
    ) -> [Int] {
        switch kind {
        case .wuLin: return computeWuLin(counts)
        case .qunXia: return computeQunXia(counts, year: year, month: month, list: list)
        }
    }

    private static func c(_ map: [String: Int], _ key: String) -> Int { map[key] ?? 0 }

    private static func computeWuLin(_ counts: [String: Int]) -> [Int] {
        let t0 = c(counts, "总冠"), t00 = c(counts, "总亚")
        let t1 = c(counts, "冠军"), t2 = c(counts, "亚军")
        let t4 = c(counts, "四强"), t8 = c(counts, "八强")
        let t16 = c(counts, "16强"), t32 = c(counts, "32强"), t64 = c(counts, "64强")
        let t128 = c(counts, "128"), t256 = c(counts, "256"), t512 = c(counts, "512")
        let t1024 = c(counts, "1024"), t2048 = c(counts, "2048")
        let box4 = t0 * 3 + t00 * 2 + t1 * 2 + t2 * 1
        let box3 = t0 * 2 + t00 * 2 + t1 * 1 + t2 * 1 + t4 * 1
        let box2 = t0 * 2 + t00 * 2 + t1 * 2 + t2 * 2 + t4 * 2 + t8 * 2 + t16 * 1
        let box1 = t0 * 2 + t00 * 2 + t1 * 2 + t2 * 2 + t4 * 2 + t8 * 2 + t16 * 2 + t32 * 2 + t64 * 1
        let box0Base = t0 * 2 + t00 * 2 + t1 * 2 + t2 * 2 + t4 * 2 + t8 * 2 + t16 * 2
            + t32 * 2 + t64 * 2 + t128 * 2 + t256 * 2 + t512 * 2 + t1024 * 1 + t2048 * 1
        return [box0Base * 2, box1, box2, box3, box4]
    }

    private static func isQunXiaBoosted(year: Int, month: Int, day: Int) -> Bool {
        if year < 2026 || (year == 2026 && month < 7) { return false }
        if year == 2026 && month == 7 && day <= 16 { return false }
        return true
    }

    private static func computeQunXia(
        _ counts: [String: Int], year: Int, month: Int, list: [JiLuDay]
    ) -> [Int] {
        var crownOld = 0, crownNew = 0, runnerOld = 0, runnerNew = 0
        var champOld = 0, champNew = 0, secondOld = 0, secondNew = 0
        for d in list where d.index > 0 && !d.type.isEmpty {
            let boosted = isQunXiaBoosted(year: year, month: month, day: d.index)
            switch d.type {
            case "总冠": if boosted { crownNew += 1 } else { crownOld += 1 }
            case "总亚": if boosted { runnerNew += 1 } else { runnerOld += 1 }
            case "冠军": if boosted { champNew += 1 } else { champOld += 1 }
            case "亚军": if boosted { secondNew += 1 } else { secondOld += 1 }
            default: break
            }
        }
        let box4 = crownOld * 2 + crownNew * 4 + runnerOld * 2 + runnerNew * 4
            + champOld * 1 + champNew * 2 + secondOld * 1 + secondNew * 2
        let t0 = c(counts, "总冠"), t00 = c(counts, "总亚")
        let t1 = c(counts, "冠军"), t2 = c(counts, "亚军")
        let t4 = c(counts, "四强"), t8 = c(counts, "八强")
        let t16 = c(counts, "16强"), t32 = c(counts, "32强"), t64 = c(counts, "64强")
        let t128 = c(counts, "128"), t256 = c(counts, "256"), t512 = c(counts, "512")
        let t1024 = c(counts, "1024")
        let box3 = t0 * 139 + t00 * 139 + t1 * 91 + t2 * 91 + t4 * 46 + t8 * 28
            + t16 * 20 + t32 * 12 + t64 * 12 + t128 * 6 + t256 * 6 + t512 * 2 + t1024 * 2
        let box2 = t0 * 14 + t00 * 14 + t1 * 14 + t2 * 14 + t4 * 14 + t8 * 14
            + t16 * 10 + t32 * 10 + t64 * 5 + t128 * 5 + t256 * 2 + t512 * 2
        return [0, 0, box2, box3, box4]
    }
}
