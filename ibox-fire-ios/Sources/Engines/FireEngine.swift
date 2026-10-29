import Foundation

/// 抢合 — 对齐 Android FireEngine / 网站 3.0.13：
/// `/ibox-synthesis-service-go` submit → 快轮询 task → confirm。
///
/// - proxies 为空：单路本机（null proxy），永不抛「无存活代理」
/// - proxies 非空：本机 + 各代理各一路并发
/// - 任意业务错误码都不全局停止；durationS<=0 表示一直打到用户手动停止
struct FireConfig {
    var token: String
    var syntheticId: Int64
    var syntheticNum: Int
    var albumIds: [Int64]
    var fireAtEpochSec: Int64
    var workers: Int = 1
    var proxies: [String] = []
    var earlyS: Double = 0.8
    var peakAfterS: Double = 4.0
    /// <=0：不限时，直到手动停止或抢满
    var durationS: Double = 0.0
    var peakReadMs: Double = 1800
    var allowBatch: Bool = true
    /// 0=满额一批 1=每次1 10=每次10；多路仍强制 1
    var batchChunk: Int = 0
}

final class FireEngine: @unchecked Sendable {
    private let cfg: FireConfig
    private let onLog: (String) -> Void
    private let stopLock = NSLock()
    private var stopFlag = false
    private let prefix = "/ibox-synthesis-service-go"
    private let boughtLock = NSLock()
    private var boughtCount = 0
    private let logLock = NSLock()
    private let attemptsLock = NSLock()
    private var attemptsCount = 0
    private let aliveLock = NSLock()
    private var aliveLanes = 0

    /// 仅「硬挂」连续多少次才弃路；读超时/高峰卡顿不算硬挂
    private let deadHardStreak = 8

    init(cfg: FireConfig, onLog: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onLog = onLog
    }

    func requestStop() {
        stopLock.lock()
        stopFlag = true
        stopLock.unlock()
    }

    private var stopped: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopFlag
    }

    private func boughtGet() -> Int {
        boughtLock.lock()
        defer { boughtLock.unlock() }
        return boughtCount
    }

    @discardableResult
    private func boughtAdd(_ n: Int) -> Int {
        boughtLock.lock()
        boughtCount += n
        let v = boughtCount
        boughtLock.unlock()
        return v
    }

    private func attemptsInc() -> Int {
        attemptsLock.lock()
        attemptsCount += 1
        let v = attemptsCount
        attemptsLock.unlock()
        return v
    }

    private func attemptsGet() -> Int {
        attemptsLock.lock()
        defer { attemptsLock.unlock() }
        return attemptsCount
    }

    private func aliveDec() -> Int {
        aliveLock.lock()
        aliveLanes = max(0, aliveLanes - 1)
        let v = aliveLanes
        aliveLock.unlock()
        return v
    }

    private func aliveGet() -> Int {
        aliveLock.lock()
        defer { aliveLock.unlock() }
        return aliveLanes
    }

    func run() async throws -> Int {
        guard let uid = JwtUtil.uid(cfg.token) else {
            throw NSError(domain: "fire", code: 1, userInfo: [NSLocalizedDescriptionKey: "JWT 无 userId"])
        }
        let cid = cfg.syntheticId
        let target = max(1, cfg.syntheticNum)
        let now0 = Date().timeIntervalSince1970
        let late = now0 - Double(cfg.fireAtEpochSec)
        if late > 10 {
            throw NSError(
                domain: "fire",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "开火时间已过 \(Int(late))s，已放弃"]
            )
        }

        var lanes: [String?] = [nil]
        var seen = Set<String>()
        for px in cfg.proxies {
            let t = px.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, seen.insert(t).inserted {
                lanes.append(t)
            }
        }
        let nWorkers = max(1, min(lanes.count, max(1, cfg.workers)))
        let multi = nWorkers > 1
        let chunk = cfg.batchChunk

        if cfg.proxies.isEmpty {
            await log("本机直连抢合 ID=\(cid) x\(target) · 提前\(fmt1(cfg.earlyS))s")
        } else {
            await log("本机+易代理抢合 ID=\(cid) x\(target) · 路数=\(nWorkers)(本机1+代理\(lanes.count - 1)) · 提前\(fmt1(cfg.earlyS))s")
        }
        if multi {
            await log("多路并发：每路每次提交 1 · 超时不弃路、硬挂才弃")
        } else if chunk == 10 {
            await log("每次提交 10（最后一笔按剩余）")
        } else if chunk == 0 && cfg.allowBatch {
            await log("可批量：一次提交满额")
        } else {
            await log("每次提交 1 · 业务错误/超时不停")
        }

        let fireStart = Double(cfg.fireAtEpochSec) - cfg.earlyS
        let deadlineMs: Double = cfg.durationS > 0
            ? (Double(cfg.fireAtEpochSec) + cfg.durationS) * 1000.0
            : Double.greatestFiniteMagnitude
        let now = Date().timeIntervalSince1970
        if now < fireStart {
            await log("等待开火 T-\(fmt1(fireStart - now))s")
            await waitUntil(fireStart)
        }
        if stopped { return 0 }

        let clients: [(String, IboxClient)] = lanes.prefix(nWorkers).enumerated().map { i, px in
            let label = px == nil ? "本机" : "代理#\(i)"
            let client = IboxClient(
                token: cfg.token,
                proxyLine: px,
                connectMs: 4_000,
                readMs: 8_000,
                deviceIdMode: .stableMD5
            )
            return (label, client)
        }

        aliveLock.lock()
        aliveLanes = clients.count
        aliveLock.unlock()

        let (warmLabel, warmClient) = clients[0]
        await log("预热 \(warmLabel) GET center/\(cid)")
        let warm: [String: Any]
        do {
            warm = try await warmClient.getThrowing("\(prefix)/synthetic/center/\(cid)")
        } catch {
            warm = ["code": -1, "message": error.localizedDescription]
        }
        let warmMsg = JSONX.message(warm)
        let warmMsgShort = warmMsg.count > 40 ? String(warmMsg.prefix(40)) : warmMsg
        await log("预热结果 code=\(JSONX.code(warm)) \(warmMsgShort)")
        if clients.count > 1 {
            let rest = Array(clients.dropFirst())
            Task.detached {
                await withTaskGroup(of: Void.self) { group in
                    for (_, c) in rest {
                        group.addTask {
                            _ = try? await c.getThrowing("\(self.prefix)/synthetic/center/\(cid)")
                        }
                    }
                }
            }
            await log("其余 \(clients.count - 1) 路后台预热中")
        }
        if cfg.durationS > 0 {
            await log("到点，开始提交（窗口\(Int(cfg.durationS))s · 遇错不停）")
        } else {
            await log("到点，开始提交（不限时 · 手动停止才停 · 遇错不停）")
        }

        await withTaskGroup(of: Void.self) { group in
            for (label, client) in clients {
                group.addTask {
                    await self.laneLoop(
                        label: label,
                        client: client,
                        uid: uid,
                        cid: cid,
                        target: target,
                        chunk: chunk,
                        multi: multi,
                        deadlineMs: deadlineMs
                    )
                }
            }
        }

        let got = min(boughtGet(), target)
        let left = max(0, aliveGet())
        if got > 0 {
            await log("完成 \(got)/\(target)（提交\(attemptsGet())次 · \(nWorkers)路 · 存活\(left)）")
        } else {
            await log("结束未成交（提交\(attemptsGet())次 · \(nWorkers)路 · 存活\(left)）")
        }
        return got
    }

    private func laneLoop(
        label: String,
        client: IboxClient,
        uid: Int64,
        cid: Int64,
        target: Int,
        chunk: Int,
        multi: Bool,
        deadlineMs: Double
    ) async {
        var hardStreak = 0
        while !Task.isCancelled && !stopped &&
            Date().timeIntervalSince1970 * 1000 < deadlineMs &&
            boughtGet() < target
        {
            let remain = target - boughtGet()
            if remain <= 0 { break }
            let shot: Int
            if multi {
                shot = 1
            } else if chunk > 0 {
                shot = min(chunk, remain)
            } else if cfg.allowBatch {
                shot = remain
            } else {
                shot = 1
            }
            let n = attemptsInc()
            let body: [String: Any] = [
                "syntheticId": NSNumber(value: cid),
                "syntheticNum": shot,
                "preferentialAlbumIds": cfg.albumIds.map { NSNumber(value: $0) }
            ]
            await log("→ [\(label)] submit#\(n) x\(shot)")
            let t0 = Date().timeIntervalSince1970 * 1000
            let subResult: Result<[String: Any], Error> = await {
                do { return .success(try await client.postJsonThrowing("\(prefix)/synthetic/center/submit", body: body)) }
                catch { return .failure(error) }
            }()
            let ms = Int(Date().timeIntervalSince1970 * 1000 - t0)
            if boughtGet() >= target || stopped { break }

            if case .failure(let err) = subResult {
                let kind = classifyTransport(err)
                if kind == .hard {
                    hardStreak += 1
                    let em = err.localizedDescription
                    let emShort = em.count > 50 ? String(em.prefix(50)) : em
                    await log("← [\(label)] submit#\(n) 硬挂 \(ms)ms \(emShort) streak=\(hardStreak)")
                    if hardStreak >= deadHardStreak {
                        let left = aliveDec()
                        await log("[\(label)] 连续硬挂\(hardStreak)次，弃路（剩\(left)路）")
                        break
                    }
                } else {
                    hardStreak = 0
                    await log("← [\(label)] submit#\(n) 超时/卡顿 \(ms)ms（继续不弃路）")
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            guard case .success(let sub) = subResult else { continue }
            hardStreak = 0

            let code = JSONX.code(sub)
            let msg = JSONX.message(sub)
            let sdata = JSONX.dataDict(sub)
            let taskIdRaw = JSONX.stringVal(sdata["taskId"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let taskId: String? = taskIdRaw.isEmpty ? nil : taskIdRaw
            if code != 0 || taskId == nil {
                let msgShort = msg.count > 80 ? String(msg.prefix(80)) : msg
                await log("← [\(label)] submit#\(n) 失败 \(ms)ms code=\(code) \(msgShort)（继续）")
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            let tid = taskId!
            let tidShort = tid.count > 12 ? String(tid.prefix(12)) : tid
            await log("← [\(label)] submit#\(n) OK \(ms)ms task=\(tidShort) status=\(JSONX.stringVal(sdata["status"]))")

            var phase = taskPhase(sdata)
            var cur = sdata
            var polls = 0
            let pollUntil = Date().timeIntervalSince1970 * 1000 + 20_000
            while phase == "wait" && Date().timeIntervalSince1970 * 1000 < pollUntil &&
                !stopped && boughtGet() < target
            {
                try? await Task.sleep(nanoseconds: 150_000_000)
                polls += 1
                let polledResult: Result<[String: Any], Error> = await {
                    do { return .success(try await client.getThrowing("\(prefix)/synthetic/center/task/\(tid)")) }
                    catch { return .failure(error) }
                }()
                if case .failure(let err) = polledResult {
                    let kind = classifyTransport(err)
                    if kind == .hard {
                        hardStreak += 1
                        await log("← [\(label)] poll#\(polls) 硬挂 streak=\(hardStreak)")
                        if hardStreak >= deadHardStreak {
                            let left = aliveDec()
                            await log("[\(label)] 连续硬挂\(hardStreak)次，弃路（剩\(left)路）")
                            return
                        }
                    } else {
                        hardStreak = 0
                        await log("← [\(label)] poll#\(polls) 超时/卡顿（继续）")
                    }
                    break
                }
                guard case .success(let polled) = polledResult else { break }
                hardStreak = 0
                if JSONX.code(polled) != 0 {
                    let pmsg = JSONX.message(polled)
                    let pShort = pmsg.count > 60 ? String(pmsg.prefix(60)) : pmsg
                    await log("← [\(label)] poll#\(polls) 业务失败 code=\(JSONX.code(polled)) \(pShort)（继续）")
                    break
                }
                cur = JSONX.dataDict(polled)
                phase = taskPhase(cur)
                if polls <= 3 || phase != "wait" {
                    await log("← [\(label)] poll#\(polls) status=\(JSONX.stringVal(cur["status"])) phase=\(phase)")
                }
            }
            if boughtGet() >= target || stopped { break }
            if phase != "ok" {
                var last = JSONX.stringVal(cur["failCode"]).trimmingCharacters(in: .whitespacesAndNewlines)
                if last.isEmpty {
                    last = JSONX.stringVal(cur["status"]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if last.isEmpty { last = "任务未成功" }
                await log("[\(label)] 任务未成功: \(last)，继续")
                continue
            }

            await log("→ [\(label)] confirm task=\(tidShort)")
            let c0 = Date().timeIntervalSince1970 * 1000
            let confBody: [String: Any] = ["syntheticId": NSNumber(value: cid), "taskId": tid]
            let confResult: Result<[String: Any], Error> = await {
                do {
                    return .success(try await client.postJsonThrowing(
                        "\(prefix)/synthetic/center/confirm?uid=\(uid)",
                        body: confBody
                    ))
                } catch {
                    return .failure(error)
                }
            }()
            let cms = Int(Date().timeIntervalSince1970 * 1000 - c0)
            if case .failure(let err) = confResult {
                let kind = classifyTransport(err)
                if kind == .hard {
                    hardStreak += 1
                    await log("← [\(label)] confirm 硬挂 \(cms)ms streak=\(hardStreak)")
                    if hardStreak >= deadHardStreak {
                        let left = aliveDec()
                        await log("[\(label)] 连续硬挂\(hardStreak)次，弃路（剩\(left)路）")
                        break
                    }
                } else {
                    hardStreak = 0
                    await log("← [\(label)] confirm 超时/卡顿 \(cms)ms（继续不弃路）")
                }
                continue
            }
            guard case .success(let conf) = confResult else { continue }
            hardStreak = 0
            let ccode = JSONX.code(conf)
            if ccode == 0 {
                let got = confirmedQty(JSONX.dataDict(conf), requested: shot)
                let total = boughtAdd(got)
                await log("← [\(label)] confirm OK \(cms)ms x\(got) 累计\(min(total, target))/\(target)")
                if total >= target { break }
                continue
            }
            let cmsg = JSONX.message(conf)
            let cShort = cmsg.count > 80 ? String(cmsg.prefix(80)) : cmsg
            await log("← [\(label)] confirm 失败 \(cms)ms code=\(ccode) \(cShort)（继续）")
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private enum TransportKind { case soft, hard }

    /// SOFT：读/写超时、高峰卡顿 → 继续打，绝不弃路
    /// HARD：连不上/代理死/DNS/拒连 → 累计后才弃路
    private func classifyTransport(_ t: Error) -> TransportKind {
        let ns = t as NSError
        let msg = (t.localizedDescription + " " + ns.domain + " \(ns.code)").lowercased()
        let name = String(describing: type(of: t)).lowercased()

        // URLSession 超时
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                return .soft
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed, NSURLErrorNotConnectedToInternet,
                 NSURLErrorSecureConnectionFailed:
                // 代理连不上走下方 msg.contains("proxy") 硬挂分支（部分 SDK 无 ProxyConnectionFailure 符号）
                return .hard
            default:
                break
            }
        }
        if name.contains("timeout") || msg.contains("timeout") || msg.contains("timed out") {
            return .soft
        }
        if msg.contains("refused") || msg.contains("unreachable") || msg.contains("unknownhost")
            || msg.contains("econnreset") || msg.contains("connection reset")
            || msg.contains("failed to connect") || msg.contains("could not connect")
            || (msg.contains("proxy") && (msg.contains("fail") || msg.contains("error") || msg.contains("unable")))
        {
            return .hard
        }
        // 其余传输异常：偏软，高峰宁可不弃
        return .soft
    }

    private func taskPhase(_ data: [String: Any]) -> String {
        let fail = JSONX.stringVal(data["failCode"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !fail.isEmpty { return "fail" }
        let st = JSONX.stringVal(data["status"]).uppercased()
        if st == "SUCCESS" { return "ok" }
        let fails: Set<String> = ["FAILED", "FAIL", "CANCELED", "CANCELLED", "TIMEOUT", "EXPIRED"]
        if fails.contains(st) { return "fail" }
        return "wait"
    }

    private func confirmedQty(_ data: [String: Any], requested: Int) -> Int {
        for key in ["total", "syntheticNum", "aboutTargetNum"] {
            if let n = JSONX.int64Val(data[key]), n > 0 { return Int(n) }
        }
        if let list = data["list"] as? [Any], !list.isEmpty { return list.count }
        return max(1, requested)
    }

    private func waitUntil(_ targetUnix: Double) async {
        while !stopped {
            let now = Date().timeIntervalSince1970
            let rem = targetUnix - now
            if rem <= 0 { break }
            if rem > 0.05 {
                let ms = max(10.0, (rem - 0.03) * 1000)
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            } else {
                break
            }
        }
    }

    private func log(_ msg: String) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale.current
        let t = formatter.string(from: Date())
        logLock.lock()
        onLog("[\(t)] \(msg)")
        logLock.unlock()
    }

    private func fmt1(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}
