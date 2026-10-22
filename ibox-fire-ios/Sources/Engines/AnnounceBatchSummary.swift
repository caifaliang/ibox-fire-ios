import Foundation

/** 对齐 announce_lock 批购响应解析与日志摘要。 */
enum AnnounceBatchSummary {
    struct Line {
        var price: Double
        var qty: Int
        var tokenId: String = ""
    }

    struct Summary {
        var count: Int
        var total: Double
        var lines: [Line]
        var text: String
        var orderId: String = ""
    }

    private static let listKeys = [
        "orderList", "orders", "list", "items", "orderItemList", "orderItems",
        "orderRelations", "orderRelationList", "relationList", "subOrders",
        "purchaseConsignmentOrders", "purchaseConsignmentOrderList", "successOrders",
        "lockOrders", "detailList", "orderDetails", "purchaseConsignmentOrderVos",
    ]

    static func summarize(
        orderResp: [String: Any],
        qtyReq: Int,
        cap: Double,
        gid: Int64,
        fetchOrder: (String) async -> [String: Any],
        fetchRecentUnpaid: (Int64) async -> [Line]
    ) async -> Summary {
        var lines = collectLines(orderResp)
        let data = orderResp["data"] as? [String: Any]
        var oid = (data?["orderId"] as? String) ?? ""
        if oid.isEmpty { oid = "\(data?["id"] ?? "")" }
        if oid.isEmpty || oid == "nil" { oid = (data?["orderUuid"] as? String) ?? "" }
        oid = oid.trimmingCharacters(in: .whitespacesAndNewlines)

        var hintCount = 0
        if let data, lines.isEmpty {
            for key in ["successCount", "lockCount", "quantity", "successNum", "actualCount"] {
                if let n = JSONX.int64Val(data[key]), n > 0 {
                    hintCount = Int(n)
                    break
                }
            }
        }

        if !oid.isEmpty {
            let detail = await fetchOrder(oid)
            let detailLines = collectLines(detail)
            let deep = detailLines.isEmpty ? deepCollect(detail) : detailLines
            if deep.count >= lines.count { lines = deep }
            if lines.isEmpty, let d = detail["data"] as? [String: Any] {
                let q = Int(JSONX.int64Val(d["quantity"]) ?? 0)
                let totalP = JSONX.doubleVal(d["price"]) ?? 0
                if q > 0, totalP > 0 {
                    return Summary(
                        count: q,
                        total: totalP,
                        lines: [],
                        text: String(format: "共%d件 合计¥%.2f", q, totalP),
                        orderId: oid
                    )
                }
            }
        }

        if lines.isEmpty, gid > 0 {
            lines = await fetchRecentUnpaid(gid)
        }

        var summary = formatLines(lines)
        if summary.orderId.isEmpty, !oid.isEmpty { summary.orderId = oid }

        if summary.count <= 0 {
            let count = hintCount > 0 ? hintCount : (qtyReq > 0 ? qtyReq : 0)
            if count > 0 {
                let text = hintCount > 0 ? "共\(count)件 (价明细待查)" : "请求\(count)件 ≤¥\(cap)"
                summary.count = count
                summary.text = text
            }
        }
        if !summary.text.isEmpty, cap > 0, !summary.text.contains("≤¥") {
            summary.text += " ≤¥\(cap)"
        }
        return summary
    }

    static func formatLockLog(cap: Double, qty: Int, summary: Summary?) -> String {
        if let s = summary, !s.text.isEmpty { return s.text }
        if cap > 0, qty > 0 { return "请求\(qty)件 ≤¥\(cap)" }
        return "¥\(cap)"
    }

    private static func formatLines(_ lines: [Line]) -> Summary {
        var byPrice: [Double: Int] = [:]
        var order: [Double] = []
        var totalQty = 0
        var totalAmt = 0.0
        for ln in lines {
            guard ln.price > 0 else { continue }
            let p = (ln.price * 100).rounded() / 100.0
            let q = max(1, ln.qty)
            if byPrice[p] == nil { order.append(p) }
            byPrice[p, default: 0] += q
            totalQty += q
            totalAmt += p * Double(q)
        }
        let detail = order.sorted().map { Line(price: $0, qty: byPrice[$0] ?? 0) }
        let text: String
        if !detail.isEmpty {
            let parts = detail.map { "¥\($0.price)×\($0.qty)" }
            text = String(format: "共%d件 ¥%.2f [%@]", totalQty, totalAmt, parts.joined(separator: " "))
        } else {
            text = ""
        }
        return Summary(count: totalQty, total: totalAmt, lines: detail, text: text)
    }

    private static func collectLines(_ obj: [String: Any]?) -> [Line] {
        guard let obj else { return [] }
        var out: [Line] = []
        walkCollect(obj, out: &out, depth: 0)
        return out
    }

    private static func walkCollect(_ node: Any?, out: inout [Line], depth: Int) {
        guard let node, depth <= 5 else { return }
        if let dict = node as? [String: Any] {
            for key in listKeys {
                if let arr = dict[key] as? [[String: Any]] {
                    for it in arr {
                        if let ln = extractLine(it) { out.append(ln) }
                    }
                }
            }
            for (_, v) in dict { walkCollect(v, out: &out, depth: depth + 1) }
        } else if let arr = node as? [Any] {
            for v in arr { walkCollect(v, out: &out, depth: depth + 1) }
        }
    }

    private static func deepCollect(_ obj: [String: Any]) -> [Line] {
        var out: [Line] = []
        func walk(_ node: Any?, _ d: Int) {
            guard let node, d <= 8 else { return }
            if let dict = node as? [String: Any] {
                let hasList = listKeys.contains { (dict[$0] as? [Any])?.isEmpty == false }
                if let row = extractLine(dict), !hasList {
                    let tid = (dict["tokenId"] as? String)
                        ?? ((dict["productPreview"] as? [String: Any])?["tokenId"] as? String)
                        ?? ""
                    if !tid.isEmpty || (JSONX.int64Val(dict["digitalCollectionId"]) ?? 0) > 0 {
                        var r = row
                        r.tokenId = tid
                        out.append(r)
                    }
                }
                for (_, v) in dict { walk(v, d + 1) }
            } else if let arr = node as? [Any] {
                for v in arr { walk(v, d + 1) }
            }
        }
        walk(obj, 0)
        return out
    }

    private static func extractLine(_ it: [String: Any]) -> Line? {
        var price = 0.0
        for key in ["price", "orderAmount", "payAmount", "singlePrice", "amount"] {
            if let v = JSONX.doubleVal(it[key]), v > 0 {
                price = v
                break
            }
        }
        guard price > 0 else { return nil }
        var qty = 1
        for key in ["quantity", "qty", "count", "num", "successCount", "lockCount"] {
            if let q = JSONX.int64Val(it[key]), q > 0 {
                qty = Int(q)
                break
            }
        }
        let pp = it["productPreview"] as? [String: Any]
        let dc = it["digitalCollection"] as? [String: Any]
        var tokenId = ""
        for src in [it, pp, dc] {
            guard let src else { continue }
            if let tid = src["tokenId"] as? String, !tid.isEmpty, tid != "0" {
                tokenId = tid
                break
            }
        }
        return Line(price: price, qty: max(1, qty), tokenId: tokenId)
    }
}
