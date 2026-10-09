import Foundation

/// 公告推送：1s 扫 announcements，上新系统通知 + 微信。
final class AnnouncePushEngine: @unchecked Sendable {
    private let store: AlertWatchStore
    private let onLog: (String) -> Void
    private let onHit: (String, String, String) -> Void
    private var stop = false
    private var seen = Set<String>()
    private var ready = false
    private var round = 0

    init(store: AlertWatchStore, onLog: @escaping (String) -> Void, onHit: @escaping (String, String, String) -> Void) {
        self.store = store
        self.onLog = onLog
        self.onHit = onHit
    }

    func requestStop() { stop = true }

    func run() async {
        onLog("公告推送启动 · 间隔1s · sail/bulletin 列表")
        while !stop && store.announcePushEnabled {
            do { try await tick() }
            catch { onLog("公告扫描异常 · \(String(error.localizedDescription.prefix(60)))") }
            var waited: UInt64 = 0
            while waited < 1_000 && !stop && store.announcePushEnabled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 200
            }
        }
        onLog("公告推送已停止")
    }

    private func tick() async throws {
        let token = store.iboxToken
        if token.isEmpty { onLog("公告推送需登录 iBox"); return }
        let client = IboxClient(token: token, deviceIdMode: .stableMD5)
        round += 1
        onLog("请求公告列表…")
        let items = await fetchList(client)
        let topTip: String = {
            guard let it = items.first else { return "-" }
            let t = JSONX.stringVal(it["title"]).isEmpty ? JSONX.stringVal(it["noticeTitle"]) : JSONX.stringVal(it["title"])
            return "#\(String(itemId(it).prefix(12))) \(String(t.prefix(24)))"
        }()
        onLog("巡检 #\(round) OK 已见\(seen.count) 条\(items.count) 最新\(topTip)")
        if items.isEmpty { return }
        let ids = items.map { itemId($0) }.filter { !$0.isEmpty }
        if !ready {
            seen = Set(ids)
            ready = true
            onLog("公告已同步存量 \(seen.count) 条 · 之后上新才推")
            return
        }
        for it in items.reversed() {
            let nid = itemId(it)
            if nid.isEmpty || seen.contains(nid) { continue }
            seen.insert(nid)
            var title = JSONX.stringVal(it["title"])
            if title.isEmpty { title = JSONX.stringVal(it["noticeTitle"]) }
            if title.isEmpty { title = "无标题" }
            let url = "https://announcement.ibox.art/#/detail?noticeId=\(nid)&is_full_screen=1"
            let brief = await fetchBrief(client, nid: nid, listItem: it)
            var body = "【公告】\(title)\n"
            if !brief.isEmpty { body += String(brief.prefix(220)) + "\n" }
            body += "直达：\(url)"
            onLog("新公告 · \(title)")
            onHit(title, body, url)
        }
        if seen.count > 500 { seen = seen.intersection(Set(ids)) }
    }

    private func fetchList(_ client: IboxClient) async -> [[String: Any]] {
        let r = await client.get("/public-service/announcements?pageNo=1&pageSize=10")
        if JSONX.code(r) != 0 && r["data"] == nil { return [] }
        if let a = r["data"] as? [[String: Any]] { return a }
        let d = JSONX.dataDict(r)
        for k in ["list", "records", "items", "announcements"] {
            if let a = d[k] as? [[String: Any]] { return a }
        }
        return []
    }

    private func fetchBrief(_ client: IboxClient, nid: String, listItem: [String: Any]) async -> String {
        let detail = await client.get("/public-service/announcements/uuid/\(nid)")
        let d = JSONX.dataDict(detail)
        var raw = JSONX.stringVal(d["content"])
        if raw.isEmpty { raw = JSONX.stringVal(d["noticeContent"]) }
        if raw.isEmpty { raw = JSONX.stringVal(listItem["content"]) }
        if raw.isEmpty { raw = JSONX.stringVal(listItem["noticeContent"]) }
        return String(stripHtml(raw).prefix(220))
    }

    private func itemId(_ it: [String: Any]) -> String {
        for k in ["uuid", "id", "noticeId", "announcementId"] {
            let v = JSONX.stringVal(it[k]).trimmingCharacters(in: .whitespaces)
            if !v.isEmpty && v != "null" { return v }
        }
        return ""
    }

    private func stripHtml(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</p>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t\\u00a0]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
