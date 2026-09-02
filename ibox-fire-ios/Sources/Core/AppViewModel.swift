import Foundation
import Combine
import SwiftUI

enum AppPlatform: String {
    case ibox, newbee
}

enum TechMode: String, CaseIterable, Identifiable {
    case announce, synth, presale, buy, sell, batch, query
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
    @Published var siteLoggedIn = false
    @Published var siteUser: SiteUser?
    @Published var siteUserName = ""
    @Published var sitePassword = ""
    @Published var siteError = ""

    @Published var iboxLoggedIn = false
    @Published var iboxToken = ""
    @Published var iboxLoginError = ""

    @Published var nbLoggedIn = false
    @Published var nbToken = ""
    @Published var nbMobile = ""
    @Published var nbPassword = ""
    @Published var nbError = ""

    @Published var appPlatform: AppPlatform = .ibox
    @Published var techMode: TechMode = .buy

    @Published var searchQ = ""
    @Published var searchHits: [CollHit] = []
    @Published var selectedGid: Int64 = 0
    @Published var selectedName = ""

    @Published var priceText = ""
    @Published var qtyText = "1"
    @Published var consignPwd = ""
    @Published var payPwd = ""
    @Published var autoPay = false
    @Published var buyMode = "cross"
    @Published var batchSafe = true
    @Published var batchActionList = true
    @Published var queryKind = "consignment"
    @Published var queryDepth = "200"
    @Published var fireH = 20
    @Published var fireM = 0
    @Published var fireS = 0
    @Published var synthIdText = ""
    @Published var synthNumText = "1"
    @Published var albumIdsText = ""
    @Published var workersText = "8"
    @Published var saleIdText = ""
    @Published var nbPidText = ""
    @Published var proxyExtractUrl = ""

    @Published var logs: [LogLine] = []
    @Published var queryTiers: [QueryTier] = []
    @Published var vipPreviewBanner = true

    private let prefs = UserDefaults.standard
    private let api = ApiRepository()
    let runner = TaskRunner.shared

    private let kSite = "ibox.site.token"
    private let kIbox = "ibox.jwt"
    private let kNb = "ibox.nb.token"

    init() {
        if let t = prefs.string(forKey: kSite), !t.isEmpty {
            Task { await restoreSite(t) }
        }
        if let t = prefs.string(forKey: kIbox), !t.isEmpty, !JwtUtil.isExpired(t) {
            iboxToken = t
            iboxLoggedIn = true
        }
        if let t = prefs.string(forKey: kNb), !t.isEmpty {
            nbToken = t
            nbLoggedIn = true
        }
    }

    var isVip: Bool { siteUser?.isVip == true || siteUser?.isAdmin == true }
    var iboxTabs: [TechMode] { [.announce, .synth, .presale, .buy, .sell, .batch, .query] }
    var nbTabs: [TechMode] { [.nb_presale, .nb_snipe] }

    func appendLog(_ msg: String, type: String = "info") {
        logs.insert(LogLine(time: bjTimeString(), msg: msg, type: type), at: 0)
        if logs.count > 400 { logs = Array(logs.prefix(400)) }
    }

    private func restoreSite(_ token: String) async {
        do {
            let u = try await api.siteMe(platformToken: token)
            siteUser = u
            siteLoggedIn = true
            vipPreviewBanner = !u.isVip && !u.isAdmin
        } catch {
            prefs.removeObject(forKey: kSite)
        }
    }

    func siteLogin() async {
        siteError = ""
        do {
            let u = try await api.siteLogin(username: siteUserName, password: sitePassword)
            siteUser = u
            siteLoggedIn = true
            vipPreviewBanner = !u.isVip && !u.isAdmin
            prefs.set(u.token, forKey: kSite)
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

    func saveIboxToken() {
        let t = JwtUtil.normalize(iboxToken)
        if t.isEmpty { iboxLoginError = "Token 为空"; return }
        if JwtUtil.isExpired(t) { iboxLoginError = "Token 已过期"; return }
        if JwtUtil.uid(t) == nil { iboxLoginError = "JWT 无 userId"; return }
        iboxToken = t
        iboxLoggedIn = true
        iboxLoginError = ""
        prefs.set(t, forKey: kIbox)
    }

    func clearIbox() {
        iboxLoggedIn = false
        iboxToken = ""
        prefs.removeObject(forKey: kIbox)
    }

    func saveNbToken() {
        let t = nbToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { nbError = "Token 为空"; return }
        nbToken = t
        nbLoggedIn = true
        nbError = ""
        prefs.set(t, forKey: kNb)
    }

    func nbOcrLogin() async {
        guard let pt = siteUser?.token else { nbError = "请先登录网站"; return }
        do {
            let r = try await api.newbeeLogin(platformToken: pt, mobile: nbMobile, password: nbPassword)
            nbToken = r.token
            nbLoggedIn = true
            prefs.set(r.token, forKey: kNb)
            nbError = ""
            appendLog("NB登录成功 \(r.nickname)", type: "buy")
        } catch {
            nbError = error.localizedDescription
        }
    }

    func requireVip() -> Bool {
        if isVip { return true }
        appendLog("非VIP仅可预览，开火已拦截", type: "error")
        return false
    }

    func search() async {
        do {
            searchHits = try await api.searchCollections(searchQ)
        } catch {
            appendLog("搜索失败 \(error.localizedDescription)", type: "error")
        }
    }

    func pick(_ hit: CollHit) {
        selectedGid = hit.id
        selectedName = hit.name
        searchHits = []
        searchQ = hit.name
    }

    private func resolveProxyUrl() async -> String {
        if let pt = siteUser?.token {
            if let u = try? await api.fetchUserProxy(platformToken: pt), !u.isEmpty {
                return ProxyPool.effectiveExtractUrl(u)
            }
        }
        return ProxyPool.effectiveExtractUrl(proxyExtractUrl)
    }

    // MARK: - Starts

    func startQuery() {
        guard requireVip(), iboxLoggedIn, selectedGid > 0 else { return }
        let depth = Int(queryDepth) ?? 200
        let engine = QueryEngine(cfg: QueryConfig(token: iboxToken, groupId: selectedGid, collectionName: selectedName, kind: queryKind, depth: depth), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m) }
        })
        runner.start(kind: .query, stop: { engine.requestStop() }) { [weak self] in
            do {
                let r = try await engine.run()
                await MainActor.run {
                    guard let self else { return }
                    self.queryTiers = r.tiers
                    self.appendLog("查询完成 扫描\(r.scanned)", type: "buy")
                }
            } catch {
                await MainActor.run { self?.appendLog(error.localizedDescription, type: "error") }
            }
        }
    }

    func startBuy() {
        guard requireVip(), iboxLoggedIn, selectedGid > 0 else { return }
        let price = Double(priceText) ?? 0
        let qty = Int(qtyText) ?? 1
        let engine = BuyEngine(cfg: BuyConfig(token: iboxToken, groupId: selectedGid, collectionName: selectedName, targetPrice: price, quantity: qty, buyMode: buyMode, autoPay: autoPay, payPassword: payPwd), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m, type: m.contains("成功") ? "buy" : "info") }
        })
        runner.start(kind: .buy, stop: { engine.requestStop() }) {
            _ = await engine.run()
        }
    }

    func startSell() {
        guard requireVip(), iboxLoggedIn, selectedGid > 0 else { return }
        let engine = SellEngine(cfg: SellConfig(token: iboxToken, groupId: selectedGid, collectionName: selectedName, targetPrice: Double(priceText) ?? 0, quantity: Int(qtyText) ?? 1, consignPassword: consignPwd), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m) }
        })
        runner.start(kind: .sell, stop: { engine.requestStop() }) {
            _ = try? await engine.run()
        }
    }

    func startBatch(list: Bool) {
        guard requireVip(), iboxLoggedIn, selectedGid > 0 else { return }
        let engine = BatchEngine(cfg: BatchConfig(token: iboxToken, groupId: selectedGid, collectionName: selectedName, action: list ? "list" : "unlist", price: Double(priceText) ?? 0, consignPassword: consignPwd, quantity: Int(qtyText) ?? 0, safeMode: batchSafe), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m) }
        })
        runner.start(kind: .batch, stop: { engine.requestStop() }) {
            _ = try? await engine.run()
        }
    }

    func startAnnounce() {
        guard requireVip(), iboxLoggedIn, let pt = siteUser?.token else { return }
        let engine = AnnounceEngine(cfg: AnnounceConfig(token: iboxToken, platformToken: pt), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m) }
        })
        runner.start(kind: .announce, stop: { engine.requestStop() }) {
            await engine.run()
        }
    }

    func startSynth() {
        guard requireVip(), iboxLoggedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            if let pt = siteUser?.token { _ = try? await api.consumeLocal(platformToken: pt, kind: "synth") }
            appendLog("抽取代理中…")
            let url = await resolveProxyUrl()
            do {
                let pool = try await ProxyPool.extractAlivePool(url)
                appendLog(pool.detail)
                if pool.needMore { appendLog("存活代理不足", type: "error"); return }
                let fireAt = todayFireAtEpochSec(h: fireH, m: fireM, s: fireS)
                let albums = albumIdsText.split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
                let engine = FireEngine(cfg: FireConfig(token: iboxToken, syntheticId: Int64(synthIdText) ?? 0, syntheticNum: Int(synthNumText) ?? 1, albumIds: albums, fireAtEpochSec: fireAt, workers: Int(workersText) ?? 8, proxies: pool.proxies), onLog: { [weak self] m in
                    Task { @MainActor in self?.appendLog(m) }
                })
                runner.start(kind: .synth, stop: { engine.requestStop() }) {
                    _ = try? await engine.run()
                }
            } catch {
                appendLog("代理失败 \(error.localizedDescription)", type: "error")
            }
        }
    }

    func startPresale() {
        guard requireVip(), iboxLoggedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            appendLog("抽取代理中…")
            let url = await resolveProxyUrl()
            do {
                let pool = try await ProxyPool.extractAlivePool(url)
                appendLog(pool.detail)
                let fireAt = todayFireAtEpochSec(h: fireH, m: fireM, s: fireS)
                let engine = PresaleEngine(cfg: PresaleConfig(token: iboxToken, saleId: Int64(saleIdText) ?? 0, quantity: Int(qtyText) ?? 1, fireAtEpochSec: fireAt, proxies: pool.proxies, autoPay: autoPay, payPassword: payPwd), onLog: { [weak self] m in
                    Task { @MainActor in self?.appendLog(m) }
                })
                runner.start(kind: .presale, stop: { engine.requestStop() }) {
                    await engine.run()
                }
            } catch {
                appendLog("代理失败 \(error.localizedDescription)", type: "error")
            }
        }
    }

    func startNbPresale() {
        guard requireVip(), nbLoggedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            let url = await resolveProxyUrl()
            do {
                let pool = try await ProxyPool.extractAlivePool(url)
                let fireAt = todayFireAtEpochSec(h: fireH, m: fireM, s: fireS)
                let engine = NbPresaleEngine(cfg: NbPresaleConfig(token: nbToken, pid: Int64(nbPidText) ?? 0, name: selectedName, quantity: Int(qtyText) ?? 1, fireAtEpochSec: fireAt, proxies: pool.proxies), onLog: { [weak self] m in
                    Task { @MainActor in self?.appendLog(m) }
                })
                runner.start(kind: .nbPresale, stop: { engine.requestStop() }) {
                    await engine.run()
                }
            } catch {
                appendLog(error.localizedDescription, type: "error")
            }
        }
    }

    func startNbSnipe() {
        guard requireVip(), nbLoggedIn else { return }
        let engine = NbSnipeEngine(cfg: NbSnipeConfig(token: nbToken, productId: Int64(nbPidText) ?? selectedGid, name: selectedName, maxPrice: Double(priceText) ?? 0, quantity: Int(qtyText) ?? 1), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m) }
        })
        runner.start(kind: .nbSnipe, stop: { engine.requestStop() }) {
            await engine.run()
        }
    }

    func startSweep() {
        guard requireVip(), iboxLoggedIn, selectedGid > 0 else { return }
        let engine = SweepEngine(cfg: SweepConfig(token: iboxToken, groupId: selectedGid, maxPrice: Double(priceText) ?? 0, quantity: Int(qtyText) ?? 1), onLog: { [weak self] m in
            Task { @MainActor in self?.appendLog(m) }
        })
        runner.start(kind: .sweep, stop: { engine.requestStop() }) {
            await engine.run()
        }
    }

    func smsLogin(phone: String) async {
        do {
            try await api.sendSmsAuto(phone: phone)
            appendLog("短信已发（服务端极验）", type: "buy")
        } catch {
            appendLog("短信失败 \(error.localizedDescription)", type: "error")
        }
    }
}
