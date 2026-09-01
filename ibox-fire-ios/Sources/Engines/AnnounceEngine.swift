import Foundation

struct AnnounceConfig {
    var token: String
    var platformToken: String
    var mode: String = "lock" // lock | buy
    var quantity: Int = 1
    var proxy: String = ""
    var durationS: Double = 3600
}

final class AnnounceEngine: @unchecked Sendable {
    private let cfg: AnnounceConfig
    private let onLog: (String) -> Void
    private let api = ApiRepository()
    private var stop = false

    init(cfg: AnnounceConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() { stop = true }

    func run() async {
        onLog("公告锁定启动 mode=\(cfg.mode)")
        var clientId = ""
        var seq: Int64 = 0
        do {
            let sub = try await api.announceSubscribe(platformToken: cfg.platformToken)
            clientId = sub.clientId
            seq = sub.seq
            onLog("已订阅 client=\(clientId.prefix(8))… alive=\(sub.alive)")
        } catch {
            onLog("订阅失败: \(error.localizedDescription)")
            return
        }
        let deadline = Date().timeIntervalSince1970 + cfg.durationS
        let client = IboxClient(token: cfg.token, proxyLine: cfg.proxy.isEmpty ? nil : cfg.proxy, deviceIdMode: .stableMD5)
        while !stop && Date().timeIntervalSince1970 < deadline {
            do {
                let items = try await api.announceFeed(platformToken: cfg.platformToken, clientId: clientId, afterSeq: seq)
                for it in items {
                    seq = max(seq, it.seq)
                    onLog("公告: \(it.title.prefix(40))")
                    for (name, gid) in it.gids {
                        onLog("解析 GID \(gid) \(name.prefix(20))")
                        if cfg.mode == "buy" {
                            let path = "/public-market-service/digital-collection-groups/\(gid)/consignment-orders?pageNo=1&pageSize=5&sortField=1&sortType=1"
                            let page = await client.get(path)
                            if JSONX.code(page) == 0, let first = JSONX.dataList(page).first,
                               let oid = JSONX.int64Val(first["id"]),
                               let uid = JwtUtil.uid(cfg.token) {
                                let buy = await client.postJson("/order-create-service/consignment-orders/\(oid)/purchase?uid=\(uid)", body: ["paymentPlatformCode": 30])
                                onLog("公告买 c=\(JSONX.code(buy)) \(JSONX.message(buy).prefix(40))")
                            }
                        }
                    }
                }
            } catch {
                onLog("feed: \(error.localizedDescription.prefix(40))")
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        onLog("公告任务结束")
    }
}
