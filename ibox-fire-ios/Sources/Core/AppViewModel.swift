import Foundation
import Combine
import SwiftUI

enum AppPlatform: String {
    case ibox, newbee
}

enum TechMode: String, CaseIterable, Identifiable {
    case announce, synth, presale, buy, sell, batch, sweep, query
    case nb_presale, nb_snipe
    case profile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .announce: return "公告锁定"
        case .synth: return "抢合"
        case .presale: return "抢购"
        case .buy: return "捡漏"
        case .sell: return "卖求购"
        case .batch: return "上下架"
        case .sweep: return "点对点"
        case .query: return "查询"
        case .nb_presale: return "抢购"
        case .nb_snipe: return "捡漏"
        case .profile: return "我的"
        }
    }
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let time: String
    let msg: String
    let type: String
}

@MainActor
final class AppViewModel: ObservableObject {
    static let queryDepths = [500, 1000, 2000, 3000, 4000, 5000, 6000, 10000]
    static let workerOptions = [1, 3, 5, 6, 8, 10, 12, 20]

    @Published var siteLoggedIn = false
    @Published var siteUser: SiteUser?
    @Published var siteUserName = ""
    @Published var sitePassword = ""
    @Published var siteError = ""

    @Published var iboxLoggedIn = false
    @Published var iboxToken = ""
    @Published var iboxTokenInput = ""
    @Published var iboxPhone = ""
    @Published var iboxCode = ""
    @Published var iboxLoginError = ""
    @Published var smsSent = false
    @Published var smsLoading = false
    @Published var loginLoading = false

    @Published var nbLoggedIn = false
    @Published var nbToken = ""
    @Published var nbTokenInput = ""
    @Published var nbMobile = ""
    @Published var nbPassword = ""
    @Published var nbError = ""

    @Published var appPlatform: AppPlatform = .ibox
    @Published var techMode: TechMode = .announce

    @Published var collSearch = ""
    @Published var collHits: [CollHit] = []

    @Published var buyGid: Int64 = 0
    @Published var buyCname = ""
    @Published var buyPrice = ""
    @Published var buyQty = "1"
    @Published var buyMode = "cross"
    @Published var buyCloudMode = true
    @Published var buyBatchInterval = "6"
    @Published var buyAutoPay = false
    @Published var buyPayPwd = ""

    @Published var sellGid: Int64 = 0
    @Published var sellCname = ""
    @Published var sellPrice = ""
    @Published var sellQty = "1"

    @Published var batchGid: Int64 = 0
    @Published var batchCname = ""
    @Published var batchPrice = ""
    @Published var batchQty = "0"
    @Published var batchAction = "list"
    @Published var batchSafe = true

    @Published var sweepMarkerSearch = ""
    @Published var sweepMarkerHits: [CollHit] = []
    @Published var sweepMarkerGid: Int64 = 0
    @Published var sweepMarkerCname = ""
    @Published var sweepMarkerOrders: [SweepMarkerOrder] = []
    @Published var sweepMarkerSortValues = ""
    @Published var sweepMarkerHasMore = false
    @Published var sweepMarkerLoading = false
    @Published var sweepSeller: SweepSeller?
    @Published var sweepSellerConfirm: SweepSeller?
    @Published var sweepWhGroups: [SweepWhGroup] = []
    @Published var sweepWhItems: [SweepWhItem] = []
    @Published var sweepWhPage = 1
    @Published var sweepWhHasMore = false
    @Published var sweepWhLoading = false
    @Published var sweepSelected: [SweepSelectedItem] = []
    @Published var sweepGid: Int64 = 0
    @Published var sweepCname = ""
    @Published var sweepMaxPrice = ""
    @Published var sweepQty = "1"
    @Published var sweepAutoPay = false
    @Published var sweepPayPwd = ""
    @Published var sweepAutoSelecting = false
    @Published var sweepAutoSelectMsg = ""
    @Published var sweepHint = ""
    @Published var sweepHelp = false
    private var sweepAutoSelectGen = 0
    private var sweepAutoSelectTask: Task<Void, Never>?
    private var sweepMarkerSearchTask: Task<Void, Never>?

    @Published var queryGid: Int64 = 0
    @Published var queryCname = ""
    @Published var queryKind = "consignment"
    @Published var queryDepth = 1000
    @Published var queryScanned = 0
    @Published var queryApiTotal = 0
    @Published var queryProgressMsg = ""

    @Published var consignPwd = ""
    @Published var fireH = 0
    @Published var fireM = 0
    @Published var fireS = 0
    @Published var workers = 10

    @Published var activitySearch = ""
    @Published var activities: [SynthActivity] = []
    @Published var selectedActivity: SynthActivity?
    @Published var channels: [SynthChannel] = []
    @Published var channelId: Int64 = 0
    @Published var materials: [SynthMaterial] = []
    @Published var checkedAlbums: Set<Int64> = []
    @Published var synthQty = "1"
    @Published var busyMsg = ""

    @Published var synthQuota = QuotaInfo(limit: 2, remaining: 2)
    @Published var presaleQuota = QuotaInfo(limit: 1, remaining: 1)
    @Published var announceQuota = QuotaInfo(limit: 3, remaining: 3)

    @Published var presaleItems: [PresaleItem] = []
    @Published var presaleSelected: PresaleItem?
    @Published var presaleAutoPay = false
    @Published var presaleQty = "1"

    @Published var announceOrderMode = "batch"
    @Published var announceMaxPrice = ""
    @Published var announceMaxCount = "1"

    @Published var nbPresaleItems: [NbPresaleItem] = []
    @Published var nbPresaleSelected: NbPresaleItem?
    @Published var nbPresaleAutoPay = true
    @Published var nbPresalePayPwd = ""
    @Published var nbPresaleQty = "1"

    @Published var nbSnipeSearch = ""
    @Published var nbSnipeHits: [NbMarketHit] = []
    @Published var nbSnipePid: Int64 = 0
    @Published var nbSnipeName = ""
    @Published var nbSnipePrice = ""
    @Published var nbSnipeQty = "1"
    @Published var nbSnipeMode = "cross"
    @Published var nbSnipeAutoPay = true
    @Published var nbSnipePayPwd = ""

    @Published var proxyExtractUrl = ""
    @Published var modeLogs: [String: [LogLine]] = [:]
    @Published var logExpanded = false
    @Published var vipPreviewBanner = true

    private let prefs = UserDefaults.standard
    private let api = ApiRepository()
    let runner = TaskRunner.shared

    private let kSite = "ibox.site.token"
    private let kIbox = "ibox.jwt"
    private let kNb = "ibox.nb.token"
    private let kPhone = "ibox.phone"
    private let kProxy = "ibox.proxy_api"
    private let kWorkers = "ibox.workers"
    private var nbSnipeSearchTask: Task<Void, Never>?
    private var lastQuotaRefreshAt: TimeInterval = 0
    private var activePrep: String?

    init() {
        iboxPhone = prefs.string(forKey: kPhone) ?? ""
        workers = prefs.object(forKey: kWorkers) as? Int ?? 10
        let savedProxy = prefs.string(forKey: kProxy)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        proxyExtractUrl = ProxyPool.effectiveExtractUrl(savedProxy)
        if savedProxy.isEmpty { prefs.set(proxyExtractUrl, forKey: kProxy) }
        if let t = prefs.string(forKey: kSite), !t.isEmpty {
            Task { await restoreSite(t) }
        }
        if let t = prefs.string(forKey: kIbox), !t.isEmpty, !JwtUtil.isExpired(t) {
            iboxToken = t
            iboxLoggedIn = true
            Task { await onIboxReady() }
        }
        if let t = prefs.string(forKey: kNb), !t.isEmpty {
            nbToken = t
            nbLoggedIn = true
            Task { await refreshNbPresaleList(silent: true) }
        }
    }

    var isVip: Bool { siteUser?.isVip == true || siteUser?.isAdmin == true }
    var isYearVip: Bool { siteUser?.isYearVip == true || siteUser?.isAdmin == true }
    var isMonthVip: Bool { siteUser?.isMonthVip == true }
    var canAnnounce: Bool { siteUser?.isAdmin == true || isYearVip || isMonthVip || siteUser?.isVip == true }
    var iboxTabs: [TechMode] { [.announce, .synth, .presale, .buy, .sell, .batch, .sweep, .query] }
    var nbTabs: [TechMode] { [.nb_presale, .nb_snipe] }

    var currentLogs: [LogLine] {
        modeLogs[techMode.rawValue] ?? []
    }

    func appendLog(_ msg: String, type: String = "info", mode: TechMode? = nil) {
        let key = (mode ?? techMode).rawValue
        var list = modeLogs[key] ?? []
        list.insert(LogLine(time: bjTimeString(), msg: msg, type: type), at: 0)
        if list.count > 300 { list = Array(list.prefix(300)) }
        modeLogs[key] = list
    }

    func clearLogs(_ mode: TechMode? = nil) {
        modeLogs[(mode ?? techMode).rawValue] = []
    }

    func syncServerLogs(_ entries: [[String: Any]], mode: TechMode) {
        var list: [LogLine] = []
        for e in entries {
            let msg = JSONX.stringVal(e["msg"])
            if msg.isEmpty { continue }
            let t = JSONX.stringVal(e["time"])
            let typ = JSONX.stringVal(e["type"])
            list.append(LogLine(time: t.isEmpty ? bjTimeString() : t, msg: msg, type: typ.isEmpty ? "info" : typ))
        }
        modeLogs[mode.rawValue] = Array(list.prefix(300))
    }

    func logsText(_ mode: TechMode? = nil) -> String {
        (modeLogs[(mode ?? techMode).rawValue] ?? []).map { "[\($0.time)] \($0.msg)" }.joined(separator: "\n")
    }

    private func restoreSite(_ token: String) async {
        do {
            let u = try await api.siteMe(platformToken: token)
            siteUser = u
            siteLoggedIn = true
            vipPreviewBanner = !u.isVip && !u.isAdmin
            await syncUserProxyFromSite()
            await refreshAllQuotas(force: true)
        } catch {
            prefs.removeObject(forKey: kSite)
        }
    }

    private func onIboxReady() async {
        await refreshActivities("")
        await refreshPresaleList(silent: true)
        await refreshAllQuotas(force: true)
    }

    func saveProxyExtractUrl() {
        let t = proxyExtractUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        proxyExtractUrl = t.isEmpty ? ProxyPool.defaultExtractURL : t
        prefs.set(proxyExtractUrl, forKey: kProxy)
    }

    func setWorkers(_ w: Int) {
        workers = w
        prefs.set(w, forKey: kWorkers)
    }

    private func syncUserProxyFromSite() async {
        guard let pt = siteUser?.token else { return }
        if let url = try? await api.fetchUserProxy(platformToken: pt), !url.isEmpty {
            proxyExtractUrl = url
            prefs.set(url, forKey: kProxy)
        }
    }

    func siteLogin() async {
        siteError = ""
        loginLoading = true
        defer { loginLoading = false }
        do {
            let u = try await api.siteLogin(username: siteUserName, password: sitePassword)
            siteUser = u
            siteLoggedIn = true
            vipPreviewBanner = !u.isVip && !u.isAdmin
            prefs.set(u.token, forKey: kSite)
            await syncUserProxyFromSite()
            await refreshAllQuotas(force: true)
        } catch {
            siteError = error.localizedDescription
        }
    }

    func siteLogout() {
        siteLoggedIn = false
        siteUser = nil
        prefs.removeObject(forKey: kSite)
        runner.stopAll()
    }

    func refreshAllQuotas(force: Bool = false) async {
        guard let pt = siteUser?.token else { return }
        let now = Date().timeIntervalSince1970
        if !force, now - lastQuotaRefreshAt < 12 { return }
        lastQuotaRefreshAt = now
        if let q = try? await api.fetchSynthQuota(platformToken: pt) { synthQuota = q }
        if let q = try? await api.fetchPresaleQuota(platformToken: pt) { presaleQuota = q }
        if isYearVip || isMonthVip || isVip {
            if let q = try? await api.fetchAnnounceQuota(platformToken: pt) { announceQuota = q }
        }
    }

    /// 对齐 Android setTechMode：切 Tab 后延迟刷新，12s 节流。
    func onTechModeChanged(_ mode: TechMode) {
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard techMode == mode else { return }
            switch mode {
            case .announce, .synth:
                await refreshAllQuotas(force: true)
            case .presale:
                await refreshAllQuotas(force: true)
                if iboxLoggedIn { await refreshPresaleList(silent: true) }
            case .nb_presale:
                if nbLoggedIn { await refreshNbPresaleList(silent: true) }
            default:
                break
            }
        }
    }

    private func prepBusy(_ kind: String, _ msg: String) -> Bool {
        if activePrep != nil { return false }
        activePrep = kind
        busyMsg = msg
        return true
    }

    private func clearPrep() {
        activePrep = nil
        busyMsg = ""
    }

    private func guardNotRunning(_ kind: TaskKind, prepKey: String) -> Bool {
        if runner.isRunning(kind) || activePrep == prepKey {
            if activePrep == prepKey { appendLog("准备中，请稍候…", type: "error") }
            return false
        }
        return true
    }

    func loginToken() {
        guard requireVip() else { return }
        let raw = iboxTokenInput.isEmpty ? iboxToken : iboxTokenInput
        loginLoading = true
        iboxLoginError = ""
        Task {
            do {
                let (token, uid) = try api.verifyIboxToken(raw)
                iboxToken = token
                iboxLoggedIn = true
                iboxLoginError = ""
                loginLoading = false
                prefs.set(token, forKey: kIbox)
                appendLog("iBox Token 登录 UID=\(uid)", type: "buy")
                await onIboxReady()
            } catch {
                iboxLoginError = error.localizedDescription
                loginLoading = false
            }
        }
    }

    func sendSms() {
        guard requireVip() else { return }
        let phone = iboxPhone.filter { !$0.isWhitespace }
        guard phone.count >= 11 else { iboxLoginError = "请输入手机号"; return }
        smsLoading = true
        iboxLoginError = ""
        smsSent = false
        prefs.set(phone, forKey: kPhone)
        Task {
            do {
                try await api.sendSmsAuto(phone: phone)
                smsSent = true
                smsLoading = false
                appendLog("验证码已发送", type: "buy")
            } catch {
                iboxLoginError = error.localizedDescription
                smsLoading = false
            }
        }
    }

    func loginSms() {
        guard requireVip() else { return }
        let phone = iboxPhone.filter { !$0.isWhitespace }
        loginLoading = true
        iboxLoginError = ""
        Task {
            do {
                let (token, uid) = try await api.loginSms(phone: phone, code: iboxCode)
                iboxToken = token
                iboxLoggedIn = true
                loginLoading = false
                prefs.set(token, forKey: kIbox)
                prefs.set(phone, forKey: kPhone)
                appendLog("iBox 登录成功 UID=\(uid)", type: "buy")
                await onIboxReady()
            } catch {
                iboxLoginError = error.localizedDescription
                loginLoading = false
            }
        }
    }

    func clearIbox() {
        iboxLoggedIn = false
        iboxToken = ""
        selectedActivity = nil
        presaleSelected = nil
        activities = []
        presaleItems = []
        prefs.removeObject(forKey: kIbox)
    }

    func saveNbToken() {
        let t = nbTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 8 else { nbError = "请粘贴有效 NewBee Token"; return }
        nbToken = t
        nbTokenInput = ""
        nbLoggedIn = true
        nbError = ""
        prefs.set(t, forKey: kNb)
        appendLog("NewBee Token 已保存", mode: .nb_presale)
        Task { await refreshNbPresaleList(silent: true) }
    }

    func clearNb() {
        nbLoggedIn = false
        nbToken = ""
        nbPresaleSelected = nil
        nbPresaleItems = []
        nbSnipePid = 0
        prefs.removeObject(forKey: kNb)
    }

    func nbOcrLogin() async {
        guard let pt = siteUser?.token else { nbError = "请先登录网站"; return }
        let mobile = nbMobile.trimmingCharacters(in: .whitespacesAndNewlines)
        if mobile.range(of: #"^1\d{10}$"#, options: .regularExpression) == nil {
            nbError = "请输入11位手机号"; return
        }
        if nbPassword.count < 4 { nbError = "密码至少4位"; return }
        do {
            let r = try await api.newbeeLogin(platformToken: pt, mobile: nbMobile, password: nbPassword)
            nbToken = r.token
            nbLoggedIn = true
            prefs.set(r.token, forKey: kNb)
            nbError = ""
            appendLog("NB登录成功 \(r.nickname)", type: "buy")
            await refreshNbPresaleList(silent: true)
        } catch {
            nbError = error.localizedDescription
        }
    }

    func requireVip() -> Bool {
        if isVip { return true }
        appendLog("该功能需要网站 VIP，请先开通", type: "error")
        return false
    }

    func requireAnnounceVip() -> Bool {
        if canAnnounce { return true }
        appendLog("公告锁定仅月卡/年卡可用", type: "error")
        return false
    }

    func searchColl(_ q: String) {
        collSearch = q
        let qq = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qq.isEmpty else { collHits = []; return }
        Task {
            do {
                collHits = Array((try await api.searchCollections(qq)).prefix(20))
                if collHits.isEmpty { appendLog("搜索无结果: \(qq)") }
            } catch {
                collHits = []
                appendLog("搜索失败 \(error.localizedDescription)", type: "error")
            }
        }
    }

    func pickColl(_ hit: CollHit, target: String) {
        collHits = []
        collSearch = hit.name
        switch target {
        case "buy": buyGid = hit.id; buyCname = hit.name
        case "sell": sellGid = hit.id; sellCname = hit.name
        case "batch": batchGid = hit.id; batchCname = hit.name
        case "query":
            queryGid = hit.id; queryCname = hit.name
            queryTiers = []; queryScanned = 0; queryApiTotal = 0; queryProgressMsg = ""
        case "sweepMarker":
            sweepMarkerGid = hit.id
            sweepMarkerCname = hit.name
            sweepMarkerHits = []
            sweepMarkerSearch = hit.name
            clearSweepSeller()
            loadMarkerOrders(reset: true)
        default: buyGid = hit.id; buyCname = hit.name
        }
    }

    func refreshActivities(_ q: String) async {
        guard iboxLoggedIn else { return }
        activitySearch = q
        do {
            activities = try await api.fetchActivities(q: q, token: iboxToken)
            appendLog("活动列表 \(activities.count) 条", mode: .synth)
        } catch {
            appendLog("活动列表失败: \(error.localizedDescription)", type: "error", mode: .synth)
        }
    }

    func selectActivity(_ a: SynthActivity) {
        selectedActivity = a
        if let (h, m, s) = parseStartToHms(a.startTime) {
            fireH = h; fireM = m; fireS = s
            appendLog(String(format: "已自动填入开火时间 %02d:%02d:%02d", h, m, s), mode: .synth)
        }
        busyMsg = "加载详情…"
        Task {
            do {
                let d = try await api.fetchActivityDetail(id: a.id, token: iboxToken)
                channels = d.channels
                channelId = d.channels.first?.id ?? 0
                materials = d.materials
                checkedAlbums = Set(d.materials.map(\.albumId).filter { $0 > 0 })
                appendLog("活动详情已加载", mode: .synth)
            } catch {
                appendLog("详情失败: \(error.localizedDescription)", type: "error", mode: .synth)
            }
            busyMsg = ""
        }
    }

    func selectChannel(_ cid: Int64) {
        channelId = cid
        Task {
            do {
                materials = try await api.fetchChannelMaterials(centerId: cid, token: iboxToken)
                checkedAlbums = Set(materials.map(\.albumId).filter { $0 > 0 })
                appendLog("通道材料已刷新", mode: .synth)
            } catch {
                appendLog("材料失败: \(error.localizedDescription)", type: "error", mode: .synth)
            }
        }
    }

    func clearSynthSelection() {
        guard !runner.isRunning(.synth), activePrep != "synth" else { return }
        selectedActivity = nil
        channels = []
        materials = []
        checkedAlbums = []
        channelId = 0
    }

    func refreshPresaleList(silent: Bool = false) async {
        guard iboxLoggedIn else {
            if !silent { appendLog("抢购需先登录 iBox", type: "error", mode: .presale) }
            return
        }
        do {
            presaleItems = try await api.fetchPresaleList(iboxToken: iboxToken)
            if !silent { appendLog("发售列表 \(presaleItems.count) 条", mode: .presale) }
        } catch {
            if !silent { appendLog("发售列表失败: \(error.localizedDescription)", type: "error", mode: .presale) }
        }
    }

    func selectPresale(_ item: PresaleItem) {
        presaleSelected = item
        if let (h, m, s) = parseStartToHms(item.startTime) {
            fireH = h; fireM = m; fireS = s
            appendLog(String(format: "已自动填入开火时间 %02d:%02d:%02d", h, m, s), mode: .presale)
        }
    }

    func clearPresaleSelection() {
        guard !runner.isRunning(.presale), activePrep != "presale" else { return }
        presaleSelected = nil
    }

    func refreshNbPresaleList(silent: Bool = false) async {
        guard nbLoggedIn, !nbToken.isEmpty else { return }
        do {
            nbPresaleItems = try await api.fetchNbPresaleList(nbToken: nbToken)
            if !silent { appendLog("NB发售 \(nbPresaleItems.count) 条", mode: .nb_presale) }
        } catch {
            if !silent { appendLog("NB发售列表失败: \(error.localizedDescription)", type: "error", mode: .nb_presale) }
        }
    }

    func selectNbPresale(_ item: NbPresaleItem) {
        nbPresaleSelected = item
        if let (h, m, s) = parseStartToHms(item.startTime) {
            fireH = h; fireM = m; fireS = s
            appendLog(String(format: "已自动填入开火时间 %02d:%02d:%02d", h, m, s), mode: .nb_presale)
        }
        Task {
            guard !nbToken.isEmpty else { return }
            guard let detail = try? await api.fetchNbPresaleDetail(nbToken: nbToken, pid: item.pid) else { return }
            guard nbPresaleSelected?.pid == item.pid else { return }
            nbPresaleSelected = detail
            if let lim = detail.limit, lim > 0 { nbPresaleQty = "\(lim)" }
            if let (h, m, s) = parseStartToHms(detail.startTime) {
                fireH = h; fireM = m; fireS = s
            }
        }
    }

    func clearNbPresaleSelection() {
        guard !runner.isRunning(.nbPresale), activePrep != "nb_presale" else { return }
        nbPresaleSelected = nil
    }

    func searchNbSnipe(_ q: String) {
        nbSnipeSearch = q
        guard nbLoggedIn, !nbToken.isEmpty else { nbSnipeHits = []; return }
        let qq = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if qq.isEmpty { nbSnipeHits = []; nbSnipeSearchTask?.cancel(); return }
        if let pid = Int64(qq), pid > 0, qq.allSatisfy(\.isNumber) {
            nbSnipeSearchTask?.cancel()
            nbSnipeHits = [NbMarketHit(id: pid, name: "PID \(pid)")]
            return
        }
        nbSnipeSearchTask?.cancel()
        nbSnipeSearchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard nbSnipeSearch.trimmingCharacters(in: .whitespacesAndNewlines) == qq else { return }
            let pt = siteUser?.token ?? ""
            do {
                let hits = try await api.searchNbMarket(nbToken: nbToken, keywords: qq, platformToken: pt)
                guard !Task.isCancelled, nbSnipeSearch.trimmingCharacters(in: .whitespacesAndNewlines) == qq else { return }
                nbSnipeHits = Array(hits.prefix(20))
                if hits.isEmpty { appendLog("未找到「\(qq)」", mode: .nb_snipe) }
            } catch {
                guard !Task.isCancelled else { return }
                appendLog("搜藏品失败: \(error.localizedDescription)", mode: .nb_snipe)
                nbSnipeHits = []
            }
        }
    }

    func pickNbSnipe(_ hit: NbMarketHit) {
        nbSnipePid = hit.id
        nbSnipeName = hit.name
        nbSnipeHits = []
        nbSnipeSearch = ""
        let floorDigits = hit.floor.filter { $0.isNumber || $0 == "." }
        if !floorDigits.isEmpty { nbSnipePrice = floorDigits }
    }

    func clearNbSnipeSelection() {
        nbSnipePid = 0
        nbSnipeName = ""
    }

    private func parseStartToHms(_ raw: String) -> (Int, Int, Int)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "null" || s == "0" { return nil }
        if s.contains(":") {
            guard let re = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2}):(\d{2})"#),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  m.numberOfRanges >= 4,
                  let hR = Range(m.range(at: 1), in: s),
                  let mR = Range(m.range(at: 2), in: s),
                  let sR = Range(m.range(at: 3), in: s) else { return nil }
            return (Int(s[hR]) ?? 0, Int(s[mR]) ?? 0, Int(s[sR]) ?? 0)
        }
        let digits = s.filter(\.isNumber)
        guard let n = Int64(digits), n > 0 else { return nil }
        let ms = n > 10_000_000_000 ? n : n * 1000
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let d = Date(timeIntervalSince1970: Double(ms) / 1000)
        return (cal.component(.hour, from: d), cal.component(.minute, from: d), cal.component(.second, from: d))
    }

    private func resolveProxyUrl() -> String { ProxyPool.effectiveExtractUrl(proxyExtractUrl) }

    private func fireTimeNotTooLate() -> Bool {
        let fireAt = todayFireAtEpochSec(h: fireH, m: fireM, s: fireS)
        let late = Int64(Date().timeIntervalSince1970) - fireAt
        if late > 10 {
            appendLog("开火时间已过 \(late)s，请改时间后再启动", type: "error")
            return false
        }
        return true
    }

    private func quotaOk(_ q: QuotaInfo, label: String) -> Bool {
        if q.unlimited || q.remaining > 0 { return true }
        appendLog("今日\(label)次数已用完（每天限\(q.limit)次）", type: "error")
        return false
    }

    // MARK: - Starts

    @Published var queryTiers: [QueryTier] = []

    func startQuery() {
        guard requireVip(), iboxLoggedIn, queryGid > 0 else {
            appendLog("请搜索并选择藏品", type: "error", mode: .query); return
        }
        guard guardNotRunning(.query, prepKey: "query") else { return }
        queryTiers = []; queryScanned = 0; queryApiTotal = 0; queryProgressMsg = "查询中…"
        let engine = QueryEngine(cfg: QueryConfig(token: iboxToken, groupId: queryGid, collectionName: queryCname, kind: queryKind, depth: queryDepth), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m, mode: .query) }
        })
        runner.start(kind: .query, stop: { engine.requestStop() }) { [weak self] in
            do {
                let r = try await engine.run(onProgress: { scanned, total in
                    Task { @MainActor in
                        self?.queryScanned = scanned
                        self?.queryProgressMsg = "已扫 \(scanned)/\(total)"
                    }
                })
                await MainActor.run {
                    guard let self else { return }
                    self.queryTiers = r.tiers
                    self.queryScanned = r.scanned
                    self.queryApiTotal = r.apiTotal
                    self.queryProgressMsg = ""
                    self.appendLog("查询完成 扫描\(r.scanned) 档位\(r.tiers.count)", type: "buy", mode: .query)
                }
            } catch {
                await MainActor.run {
                    self?.queryProgressMsg = ""
                    self?.appendLog(error.localizedDescription, type: "error", mode: .query)
                }
            }
        }
    }

    func startBuy() {
        if buyCloudMode { startBuyCloud(); return }
        startBuyLocal()
    }

    private func startBuyLocal() {
        guard requireVip(), iboxLoggedIn, buyGid > 0 else { appendLog("请搜索并选择藏品", type: "error", mode: .buy); return }
        guard guardNotRunning(.buy, prepKey: "buy") else { return }
        let price = Double(buyPrice) ?? 0
        let qty = Int(buyQty) ?? 0
        guard price > 0 else { appendLog("请填写目标价", type: "error", mode: .buy); return }
        guard qty >= 1 else { appendLog("请填写数量", type: "error", mode: .buy); return }
        if buyAutoPay && buyPayPwd.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("开启自动支付需填写支付密码", type: "error", mode: .buy); return
        }
        appendLog("⚡本地模式（请保持前台，切后台约2分钟后会暂停）", mode: .buy)
        let interval = (Double(buyBatchInterval) ?? 6).clamped(to: 1...60)
        let engine = BuyEngine(cfg: BuyConfig(token: iboxToken, groupId: buyGid, collectionName: buyCname, targetPrice: price, quantity: qty, buyMode: buyMode, batchIntervalS: interval, autoPay: buyAutoPay, payPassword: buyPayPwd), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m, type: m.contains("成功") ? "buy" : "info", mode: .buy) }
        })
        runner.start(kind: .buy, stop: { engine.requestStop() }, keepAlive: true) { _ = await engine.run() }
    }

    func startBuyCloud() {
        guard requireVip(), siteLoggedIn, let pt = siteUser?.token else {
            appendLog("云端捡漏需先登录网站账号", type: "error", mode: .buy); return
        }
        guard iboxLoggedIn, buyGid > 0 else { appendLog("请搜索并选择藏品", type: "error", mode: .buy); return }
        guard guardNotRunning(.buy, prepKey: "buy") else { return }
        let price = Double(buyPrice) ?? 0
        let qty = Int(buyQty) ?? 0
        guard price > 0 else { appendLog("请填写目标价", type: "error", mode: .buy); return }
        guard qty >= 1 else { appendLog("请填写数量", type: "error", mode: .buy); return }
        if buyAutoPay && buyPayPwd.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("开启自动支付需填写支付密码", type: "error", mode: .buy); return
        }
        let interval = (Double(buyBatchInterval) ?? 6).clamped(to: 1...60)
        final class TaskBox: @unchecked Sendable { var id = "" }
        let taskBox = TaskBox()
        runner.start(kind: .buy, stop: {
            Task { await self.api.stopSnipeLoop(taskId: taskBox.id) }
        }, keepAlive: false) { [weak self] in
            guard let self else { return }
            var retry = 0
            while retry < 30 && !Task.isCancelled {
                do {
                    let start = try await self.api.startSnipeLoop(
                        iboxToken: self.iboxToken,
                        platformToken: pt,
                        groupId: self.buyGid,
                        targetPrice: price,
                        quantity: qty,
                        collectionName: self.buyCname,
                        buyMode: self.buyMode,
                        batchInterval: interval,
                        autoPay: self.buyAutoPay,
                        payPassword: self.buyPayPwd,
                        proxy: ""
                    )
                    taskBox.id = start.taskId
                    let engine = start.celery ? "Celery" : "线程"
                    await MainActor.run {
                        self.appendLog("☁️云端捡漏[\(self.modeLabelBuy(self.buyMode))/\(engine)] ≤¥\(price) x\(qty)", type: "buy", mode: .buy)
                        if !start.message.isEmpty { self.appendLog(start.message, mode: .buy) }
                    }
                    break
                } catch {
                    let msg = error.localizedDescription
                    if msg.contains("繁忙") || msg.contains("排队") {
                        retry += 1
                        await MainActor.run { self.appendLog("排队中...(\(retry)/30)", mode: .buy) }
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    await MainActor.run { self.appendLog("启动失败: \(msg)", type: "error", mode: .buy) }
                    return
                }
            }
            if taskBox.id.isEmpty { return }
            while !Task.isCancelled {
                do {
                    let st = try await self.api.snipeStatus(taskId: taskBox.id)
                    await MainActor.run { self.syncServerLogs(st.logs, mode: .buy) }
                    if st.status == "stopped" || st.status == "SUCCESS" || st.status == "FAILURE" {
                        await MainActor.run {
                            self.appendLog("云端任务结束 成交 \(st.bought)/\(qty)", mode: .buy)
                        }
                        break
                    }
                } catch { }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func modeLabelBuy(_ m: String) -> String {
        switch m {
        case "normal": return "普通"
        case "batch": return "纯批量"
        default: return "批量+普通"
        }
    }

    func startSell() {
        guard requireVip(), iboxLoggedIn, sellGid > 0 else { appendLog("请搜索并选择藏品", type: "error", mode: .sell); return }
        guard guardNotRunning(.sell, prepKey: "sell") else { return }
        let price = Double(sellPrice) ?? 0
        let qty = Int(sellQty) ?? 0
        guard price > 0 else { appendLog("请填写最低接受价", type: "error", mode: .sell); return }
        guard qty >= 1 else { appendLog("请填写数量", type: "error", mode: .sell); return }
        if consignPwd.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("请填写寄售密码", type: "error", mode: .sell); return
        }
        let engine = SellEngine(cfg: SellConfig(token: iboxToken, groupId: sellGid, collectionName: sellCname, targetPrice: price, quantity: qty, consignPassword: consignPwd), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m, mode: .sell) }
        })
        runner.start(kind: .sell, stop: { engine.requestStop() }) { _ = try? await engine.run() }
    }

    func searchMarkerColl(_ q: String) {
        sweepMarkerSearch = q
        sweepMarkerSearchTask?.cancel()
        let qq = q.trimmingCharacters(in: .whitespaces)
        guard !qq.isEmpty else { sweepMarkerHits = []; return }
        sweepMarkerSearchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            do {
                let list = Array((try await api.searchCollections(qq)).prefix(20))
                await MainActor.run {
                    self.sweepMarkerHits = list
                }
            } catch {
                await MainActor.run { self.sweepMarkerHits = [] }
            }
        }
    }

    func loadMarkerOrders(reset: Bool) {
        guard iboxLoggedIn, sweepMarkerGid > 0 else { return }
        if !reset && sweepMarkerLoading { return }
        if !reset && !sweepMarkerHasMore { return }
        if reset {
            sweepMarkerSortValues = ""
            sweepMarkerOrders = []
            sweepMarkerHasMore = false
            sweepHint = ""
        }
        sweepMarkerLoading = true
        sweepHint = ""
        let token = iboxToken
        let gid = sweepMarkerGid
        let sv = sweepMarkerSortValues
        Task {
            do {
                let r = try await SweepBrowse.markerOrders(token: token, gid: gid, sortValues: sv)
                await MainActor.run {
                    let seen = Set(self.sweepMarkerOrders.map(\.id))
                    let fresh = r.items.filter { !seen.contains($0.id) }
                    self.sweepMarkerOrders = reset ? r.items : self.sweepMarkerOrders + fresh
                    self.sweepMarkerSortValues = r.nextSv
                    self.sweepMarkerHasMore = r.hasMore && !r.nextSv.isEmpty && (reset || !fresh.isEmpty)
                    self.sweepMarkerLoading = false
                }
            } catch {
                await MainActor.run {
                    self.sweepMarkerLoading = false
                    self.sweepHint = error.localizedDescription
                    self.appendLog(error.localizedDescription, type: "error", mode: .sweep)
                }
            }
        }
    }

    func pickMarkerOrder(_ order: SweepMarkerOrder) {
        guard iboxLoggedIn else { appendLog("请先登录 iBox", type: "error", mode: .sweep); return }
        guard order.digitalCollectionId > 0 else { return }
        sweepHint = ""
        let token = iboxToken
        let gid = sweepMarkerGid
        Task {
            do {
                var seller = try await SweepBrowse.resolveSeller(token: token, digitalCollectionId: order.digitalCollectionId)
                seller.markerOrderId = order.orderId
                seller.markerGid = gid
                if seller.name.isEmpty { seller.name = order.sellerName.isEmpty ? "未知卖家" : order.sellerName }
                await MainActor.run { self.sweepSellerConfirm = seller }
            } catch {
                await MainActor.run {
                    self.sweepHint = error.localizedDescription
                    self.appendLog(error.localizedDescription, type: "error", mode: .sweep)
                }
            }
        }
    }

    func confirmSweepSeller() {
        guard let pending = sweepSellerConfirm else { return }
        sweepSeller = pending
        sweepSellerConfirm = nil
        resetSweepWarehouse()
        loadWarehouseGroups()
    }

    func cancelSweepSellerConfirm() { sweepSellerConfirm = nil }

    func clearSweepSeller() {
        sweepAutoSelectGen += 1
        sweepAutoSelectTask?.cancel()
        sweepSeller = nil
        sweepSellerConfirm = nil
        resetSweepWarehouse()
    }

    func reselectSweepSeller() {
        clearSweepSeller()
        if sweepMarkerGid > 0 { loadMarkerOrders(reset: true) }
    }

    private func resetSweepWarehouse() {
        sweepAutoSelectGen += 1
        sweepAutoSelectTask?.cancel()
        sweepWhGroups = []
        sweepWhItems = []
        sweepWhPage = 1
        sweepWhHasMore = false
        sweepWhLoading = false
        sweepSelected = []
        sweepGid = 0
        sweepCname = ""
        sweepAutoSelecting = false
        sweepAutoSelectMsg = ""
    }

    func loadWarehouseGroups() {
        guard iboxLoggedIn, let sso = sweepSeller?.sso, !sso.isEmpty else { return }
        sweepWhLoading = true
        sweepHint = ""
        let token = iboxToken
        Task {
            do {
                let groups = try await SweepBrowse.warehouseGroups(token: token, sellerSso: sso)
                await MainActor.run {
                    self.sweepWhGroups = groups
                    self.sweepWhLoading = false
                    if groups.isEmpty { self.sweepHint = "卖家仓库为空或不可见" }
                }
            } catch {
                await MainActor.run {
                    self.sweepWhLoading = false
                    self.sweepHint = error.localizedDescription
                    self.appendLog(error.localizedDescription, type: "error", mode: .sweep)
                }
            }
        }
    }

    func selectWhGroup(_ g: SweepWhGroup) {
        guard g.groupId > 0 else { return }
        sweepGid = g.groupId
        sweepCname = g.name
        sweepSelected = []
        scheduleAutoSelectWh(delayMs: 0)
    }

    func loadWarehouseItems(reset: Bool) {
        guard iboxLoggedIn, let sso = sweepSeller?.sso, sweepGid > 0 else { return }
        if sweepWhLoading || sweepAutoSelecting { return }
        if !reset && !sweepWhHasMore { return }
        if reset {
            sweepWhPage = 1
            sweepWhItems = []
            sweepWhHasMore = false
        }
        sweepWhLoading = true
        sweepHint = ""
        let token = iboxToken
        let gid = sweepGid
        let page = max(1, sweepWhPage)
        Task {
            do {
                let r = try await SweepBrowse.warehouseItems(token: token, sellerSso: sso, groupId: gid, page: page)
                await MainActor.run {
                    let tagged = r.items.map { item -> SweepWhItem in
                        var x = item
                        x.groupId = gid
                        return x
                    }
                    self.sweepWhItems = reset ? tagged : self.sweepWhItems + tagged
                    self.sweepWhHasMore = r.hasMore
                    if !tagged.isEmpty || r.hasMore { self.sweepWhPage = page + 1 }
                    self.sweepWhLoading = false
                }
            } catch {
                await MainActor.run {
                    self.sweepWhLoading = false
                    self.sweepHint = error.localizedDescription
                    self.appendLog(error.localizedDescription, type: "error", mode: .sweep)
                }
            }
        }
    }

    func setSweepPriceQty(maxPrice: String? = nil, qty: String? = nil) {
        if let maxPrice { sweepMaxPrice = maxPrice }
        if let qty { sweepQty = qty }
        scheduleAutoSelectWh()
    }

    func toggleWhItem(_ it: SweepWhItem) {
        if sweepAutoSelecting { return }
        let id = it.digitalCollectionId
        guard id > 0 else { return }
        if let idx = sweepSelected.firstIndex(where: { $0.digitalCollectionId == id }) {
            sweepSelected.remove(at: idx)
            return
        }
        let maxP = Double(sweepMaxPrice) ?? 0
        if it.hasPrice && maxP > 0 && it.price > maxP { return }
        let n = Int(sweepQty) ?? 1
        if sweepSelected.count >= n { return }
        sweepSelected.append(SweepSelectedItem(
            digitalCollectionId: it.digitalCollectionId,
            tokenId: it.tokenId,
            price: it.hasPrice ? it.price : 0,
            groupId: it.groupId > 0 ? it.groupId : sweepGid
        ))
    }

    private func scheduleAutoSelectWh(delayMs: UInt64 = 350) {
        sweepAutoSelectTask?.cancel()
        sweepAutoSelectTask = Task { [weak self] in
            if delayMs > 0 { try? await Task.sleep(nanoseconds: delayMs * 1_000_000) }
            if Task.isCancelled { return }
            await self?.autoSelectWhByPriceQty()
        }
    }

    private func autoSelectWhByPriceQty() async {
        let gen = sweepAutoSelectGen + 1
        sweepAutoSelectGen = gen
        let maxP = Double(sweepMaxPrice) ?? 0
        let n = Int(sweepQty) ?? 0
        guard let sso = sweepSeller?.sso, sweepGid > 0, maxP > 0, n >= 1 else {
            sweepAutoSelectMsg = ""
            return
        }
        sweepAutoSelecting = true
        sweepAutoSelectMsg = "自动勾选中…"
        sweepSelected = []
        sweepWhPage = 1
        sweepWhItems = []
        sweepWhHasMore = true
        sweepHint = ""
        var candidates: [SweepSelectedItem] = []
        let token = iboxToken
        let gid = sweepGid
        do {
            while candidates.count < n && gen == sweepAutoSelectGen {
                let page = max(1, sweepWhPage)
                if page > 1 && !sweepWhHasMore { break }
                sweepWhLoading = true
                let r = try await SweepBrowse.warehouseItems(token: token, sellerSso: sso, groupId: gid, page: page)
                if gen != sweepAutoSelectGen { return }
                let tagged = r.items.map { item -> SweepWhItem in
                    var x = item
                    x.groupId = gid
                    return x
                }
                sweepWhItems = page == 1 ? tagged : sweepWhItems + tagged
                sweepWhHasMore = r.hasMore
                sweepWhPage = page + 1
                for it in tagged {
                    if it.digitalCollectionId <= 0 || !it.hasPrice { continue }
                    if it.price > maxP + 0.009 { continue }
                    if candidates.contains(where: { $0.digitalCollectionId == it.digitalCollectionId }) { continue }
                    candidates.append(SweepSelectedItem(digitalCollectionId: it.digitalCollectionId, tokenId: it.tokenId, price: it.price, groupId: it.groupId))
                }
                if r.items.isEmpty || !r.hasMore { break }
            }
            if gen != sweepAutoSelectGen { return }
            let picked = Array(candidates.sorted { $0.price < $1.price }.prefix(n))
            sweepSelected = picked
            sweepAutoSelectMsg = picked.count >= n ? "已自动勾选 \(picked.count)/\(n)" : "仅找到 \(picked.count) 件符合（目标 \(n)）"
            sweepAutoSelecting = false
            sweepWhLoading = false
        } catch {
            if gen == sweepAutoSelectGen {
                sweepHint = error.localizedDescription
                sweepAutoSelectMsg = ""
                sweepAutoSelecting = false
                sweepWhLoading = false
            }
        }
    }

    func startSweep() {
        guard requireVip(), iboxLoggedIn else { appendLog("请先登录 iBox", type: "error", mode: .sweep); return }
        guard let seller = sweepSeller else { appendLog("未确认卖家", type: "error", mode: .sweep); return }
        guard !sweepSelected.isEmpty else { appendLog("未勾选目标", type: "error", mode: .sweep); return }
        let maxP = Double(sweepMaxPrice) ?? 0
        guard maxP > 0 else { appendLog("请填写最高接受价", type: "error", mode: .sweep); return }
        let qty = Int(sweepQty) ?? 0
        guard qty >= 1 else { appendLog("请填写数量", type: "error", mode: .sweep); return }
        if sweepSelected.count > qty { appendLog("已选超过数量", type: "error", mode: .sweep); return }
        if sweepAutoPay && sweepPayPwd.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("开启自动支付需填写支付密码", type: "error", mode: .sweep); return
        }
        guard guardNotRunning(.sweep, prepKey: "sweep") else { return }
        appendLog("⚡本地模式（请保持前台）", mode: .sweep)
        let engine = SweepEngine(cfg: SweepConfig(
            token: iboxToken,
            sellerSso: seller.sso,
            sellerName: seller.name,
            markerGid: sweepMarkerGid,
            groupId: sweepGid,
            collectionName: sweepCname,
            maxPrice: maxP,
            quantity: qty,
            selected: sweepSelected,
            autoPay: sweepAutoPay,
            payPassword: sweepPayPwd
        ), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m, type: m.contains("成功") || m.contains("确认") ? "buy" : "info", mode: .sweep) }
        })
        runner.start(kind: .sweep, stop: { engine.requestStop() }, keepAlive: true) { _ = await engine.run() }
    }

    func startBatch() {
        guard requireVip(), iboxLoggedIn, batchGid > 0 else { appendLog("请搜索并选择藏品", type: "error", mode: .batch); return }
        guard guardNotRunning(.batch, prepKey: "batch") else { return }
        let list = batchAction == "list"
        if list {
            if (Double(batchPrice) ?? 0) <= 0 { appendLog("请填写上架价", type: "error", mode: .batch); return }
            if consignPwd.trimmingCharacters(in: .whitespaces).isEmpty { appendLog("请填写寄售密码", type: "error", mode: .batch); return }
        }
        let engine = BatchEngine(cfg: BatchConfig(token: iboxToken, groupId: batchGid, collectionName: batchCname, action: list ? "list" : "unlist", price: Double(batchPrice) ?? 0, consignPassword: consignPwd, quantity: Int(batchQty) ?? 0, safeMode: batchSafe), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m, mode: .batch) }
        })
        runner.start(kind: .batch, stop: { engine.requestStop() }) { _ = try? await engine.run() }
    }

    func startAnnounce() {
        guard requireAnnounceVip(), iboxLoggedIn else {
            if iboxLoggedIn == false { appendLog("请先登录 iBox", type: "error", mode: .announce) }
            return
        }
        guard guardNotRunning(.announce, prepKey: "announce") else { return }
        guard let pt = siteUser?.token else { return }
        if !announceQuota.openNow {
            appendLog("仅北京时间 \(announceQuota.openHours.isEmpty ? "09:00-23:59" : announceQuota.openHours) 可用", type: "error", mode: .announce)
            return
        }
        guard quotaOk(announceQuota, label: "公告锁定") else { return }
        if announceOrderMode == "batch" {
            if (Double(announceMaxPrice) ?? 0) <= 0 { appendLog("批量模式请填写钱包余额", type: "error", mode: .announce); return }
            if (Int(announceMaxCount) ?? 0) < 1 { appendLog("批量模式请填写数量", type: "error", mode: .announce); return }
        }
        guard prepBusy("announce", "扣次中…") else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { clearPrep() }
            do {
                let q = try await api.consumeLocal(platformToken: pt, kind: "announce_lock")
                announceQuota = q
                appendLog("公告锁已扣次 剩 \(q.unlimited ? "不限" : "\(q.remaining)/\(q.limit)")", mode: .announce)
            } catch {
                appendLog("扣次失败: \(error.localizedDescription)", type: "error", mode: .announce)
                return
            }
            busyMsg = "本地监听中"
            let cfg = AnnounceConfig(token: iboxToken, orderMode: announceOrderMode, maxSinglePrice: Double(announceMaxPrice) ?? 0, maxCount: Int(announceMaxCount) ?? 1, s1SearchBase: api.siteBase)
            appendLog("公告发现本机直连（不走代理）", mode: .announce)
            let engine = AnnounceEngine(cfg: cfg, onLog: { [weak self] m in
                Task { @MainActor in self?.appendLog(m, mode: .announce) }
            })
            clearPrep()
            runner.start(kind: .announce, stop: { engine.requestStop() }) { _ = await engine.run() }
        }
    }

    func startSynth() {
        guard requireVip(), iboxLoggedIn else { return }
        guard selectedActivity != nil else { appendLog("请选择活动", type: "error", mode: .synth); return }
        let sid = channelId > 0 ? channelId : (selectedActivity?.id ?? 0)
        guard sid > 0 else { appendLog("请先选择活动", type: "error", mode: .synth); return }
        guard quotaOk(synthQuota, label: "抢合") else { return }
        guard fireTimeNotTooLate() else { return }
        guard guardNotRunning(.synth, prepKey: "synth") else { return }
        guard prepBusy("synth", "扣次中…") else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { if activePrep == "synth" { clearPrep() } }
            if let pt = siteUser?.token {
                do {
                    let q = try await api.consumeLocal(platformToken: pt, kind: "synth")
                    synthQuota = q
                    appendLog(q.unlimited ? "扣次成功（不限）" : "扣次成功 今日剩 \(q.remaining)/\(q.limit)", mode: .synth)
                } catch {
                    appendLog("扣次失败: \(error.localizedDescription)", type: "error", mode: .synth)
                    return
                }
            }
            busyMsg = "提取+验活中…"
            appendLog("抽取代理中…", mode: .synth)
            let url = resolveProxyUrl()
            do {
                let pool = try await ProxyPool.extractAlivePool(url)
                appendLog("代理池就绪 \(pool.proxies.count) 条 | \(pool.detail)", mode: .synth)
                if pool.proxies.count < 12 {
                    appendLog("存活仅 \(pool.proxies.count) 条，放弃", type: "error", mode: .synth)
                    return
                }
                if pool.needMore { appendLog("存活代理不足", type: "error", mode: .synth); return }
                let fireAt = todayFireAtEpochSec(h: fireH, m: fireM, s: fireS)
                let w = max(1, min(20, min(workers, pool.proxies.count)))
                busyMsg = "本地开火中"
                appendLog("启动本地抢合 ID=\(sid) workers=\(w)", mode: .synth)
                let engine = FireEngine(cfg: FireConfig(token: iboxToken, syntheticId: sid, syntheticNum: Int(synthQty) ?? 1, albumIds: Array(checkedAlbums), fireAtEpochSec: fireAt, workers: w, proxies: pool.proxies), onLog: { [weak self] m in
                    Task { @MainActor in self?.appendLog(m, mode: .synth) }
                })
                clearPrep()
                runner.start(kind: .synth, stop: { engine.requestStop() }) { _ = try? await engine.run() }
            } catch {
                appendLog("代理失败 \(error.localizedDescription)", type: "error", mode: .synth)
            }
        }
    }

    func startPresale() {
        guard requireVip(), iboxLoggedIn else { return }
        guard let item = presaleSelected else { appendLog("请选择发售", type: "error", mode: .presale); return }
        guard quotaOk(presaleQuota, label: "抢购") else { return }
        guard fireTimeNotTooLate() else { return }
        guard guardNotRunning(.presale, prepKey: "presale") else { return }
        if presaleAutoPay && consignPwd.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("开启自动支付需填写支付密码", type: "error", mode: .presale); return
        }
        guard prepBusy("presale", "扣次中…") else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { if activePrep == "presale" { clearPrep() } }
            if let pt = siteUser?.token {
                do {
                    let q = try await api.consumeLocal(platformToken: pt, kind: "presale")
                    presaleQuota = q
                    appendLog(q.unlimited ? "抢购已扣次（不限）" : "抢购已扣次 剩 \(q.remaining)/\(q.limit)", mode: .presale)
                } catch {
                    appendLog("扣次失败: \(error.localizedDescription)", type: "error", mode: .presale)
                    return
                }
            }
            let fireAt = todayFireAtEpochSec(h: fireH, m: fireM, s: fireS)
            let nowSec = Date().timeIntervalSince1970
            let prestoreLead = 160.0
            if Double(fireAt) - nowSec > prestoreLead {
                let waitSec = max(1, Int64(Double(fireAt) - prestoreLead - nowSec))
                busyMsg = "等待预存窗口 \(waitSec)s"
                appendLog("等待至预存窗口 \(waitSec)s (极验~3min有效)", mode: .presale)
                try? await Task.sleep(nanoseconds: UInt64(waitSec) * 1_000_000_000)
            }
            busyMsg = "提取+验活中…"
            appendLog("抽取代理中…", mode: .presale)
            do {
                let pool = try await ProxyPool.extractAlivePool(resolveProxyUrl())
                appendLog("代理 \(pool.proxies.count) 活 | \(pool.detail)", mode: .presale)
                if pool.proxies.count < ProxyPool.minAlive {
                    appendLog("存活过少(\(pool.proxies.count)<\(ProxyPool.minAlive))，放弃", type: "error", mode: .presale)
                    return
                }
                busyMsg = "预存极验中…"
                appendLog("预存极验…", mode: .presale)
                let caps = await PresaleCaptchas.prestored(proxies: pool.proxies, iboxToken: iboxToken) { [weak self] m in
                    Task { @MainActor in self?.appendLog(m, mode: .presale) }
                }
                if caps.isEmpty {
                    appendLog("极验码为 0，放弃", type: "error", mode: .presale)
                    return
                }
                busyMsg = "本地开火中"
                let payProxy = pool.proxies.first ?? ""
                let engine = PresaleEngine(cfg: PresaleConfig(
                    token: iboxToken,
                    saleId: item.saleId,
                    saleName: item.name,
                    quantity: Int(presaleQty) ?? 1,
                    fireAtEpochSec: fireAt,
                    proxies: Array(pool.proxies.prefix(50)),
                    captchas: caps,
                    workers: 6,
                    autoPay: presaleAutoPay,
                    payPassword: presaleAutoPay ? consignPwd : "",
                    payProxy: payProxy
                ), onLog: { [weak self] m in
                    Task { @MainActor in self?.appendLog(m, mode: .presale) }
                })
                clearPrep()
                runner.start(kind: .presale, stop: { engine.requestStop() }) { await engine.run() }
            } catch {
                appendLog("代理失败 \(error.localizedDescription)", type: "error", mode: .presale)
            }
        }
    }

    func startNbPresale() {
        guard requireVip(), nbLoggedIn else { return }
        guard let item = nbPresaleSelected else { appendLog("请选择发售", type: "error", mode: .nb_presale); return }
        guard fireTimeNotTooLate() else { return }
        guard guardNotRunning(.nbPresale, prepKey: "nb_presale") else { return }
        if nbPresaleAutoPay && nbPresalePayPwd.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("开启自动支付需填写支付密码", type: "error", mode: .nb_presale); return
        }
        guard prepBusy("nb_presale", "提取+验活中…") else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { if activePrep == "nb_presale" { clearPrep() } }
            appendLog("提取+验活中…", mode: .nb_presale)
            do {
                let pool = try await ProxyPool.extractAlivePool(resolveProxyUrl())
                appendLog("代理池就绪 \(pool.proxies.count) 条 | \(pool.detail)", mode: .nb_presale)
                if pool.proxies.count < ProxyPool.minAlive {
                    appendLog("存活仅 \(pool.proxies.count) 条，放弃", type: "error", mode: .nb_presale)
                    return
                }
                let fireAt = todayFireAtEpochSec(h: fireH, m: fireM, s: fireS)
                let w = max(1, min(20, min(workers, pool.proxies.count)))
                busyMsg = "本地开火中"
                appendLog("启动 NB抢购 pid=\(item.pid) 高峰\(w)线程×60s→单线程300ms→最长20min\(nbPresaleAutoPay ? " · 自动支付" : "")", mode: .nb_presale)
                let engine = NbPresaleEngine(cfg: NbPresaleConfig(
                    token: nbToken,
                    pid: item.pid,
                    name: item.name,
                    quantity: Int(nbPresaleQty) ?? 1,
                    fireAtEpochSec: fireAt,
                    proxies: pool.proxies,
                    workers: w,
                    proxyExtractUrl: resolveProxyUrl(),
                    autoPay: nbPresaleAutoPay,
                    payPassword: nbPresaleAutoPay ? nbPresalePayPwd : "",
                    siteBase: api.siteBase
                ), onLog: { [weak self] m in
                    Task { @MainActor in self?.appendLog(m, mode: .nb_presale) }
                })
                clearPrep()
                runner.start(kind: .nbPresale, stop: { engine.requestStop() }) { await engine.run() }
            } catch {
                appendLog(error.localizedDescription, type: "error", mode: .nb_presale)
            }
        }
    }

    func startNbSnipe() {
        guard requireVip(), nbLoggedIn else { return }
        guard guardNotRunning(.nbSnipe, prepKey: "nb_snipe") else { return }
        guard nbSnipePid > 0 else { appendLog("请搜索并选择商品", type: "error", mode: .nb_snipe); return }
        let price = Double(nbSnipePrice) ?? 0
        let qty = Int(nbSnipeQty) ?? 0
        guard price > 0 else { appendLog("请填写目标价", type: "error", mode: .nb_snipe); return }
        guard qty >= 1 else { appendLog("请填写数量", type: "error", mode: .nb_snipe); return }
        if nbSnipeAutoPay && nbSnipePayPwd.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("开启自动支付需填写支付密码", type: "error", mode: .nb_snipe); return
        }
        let engine = NbSnipeEngine(cfg: NbSnipeConfig(
            token: nbToken,
            productId: nbSnipePid,
            name: nbSnipeName,
            maxPrice: price,
            quantity: qty,
            mode: nbSnipeMode,
            autoPay: nbSnipeAutoPay,
            payPassword: nbSnipePayPwd,
            siteBase: api.siteBase
        ), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m, mode: .nb_snipe) }
        })
        runner.start(kind: .nbSnipe, stop: { engine.requestStop() }) { await engine.run() }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
