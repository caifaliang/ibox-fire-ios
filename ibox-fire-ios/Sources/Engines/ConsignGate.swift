import Foundation

/// 本机寄售硬间隔 — 对齐 Android `ConsignGate`（单进程 + 锁）。
final class ConsignGate: @unchecked Sendable {
    static let shared = ConsignGate()
    static let listMinGapS = 5.0
    static let batchListGapS = 3.5

    private let lock = NSLock()
    private var lastMarkMs: [Int64: Int64] = [:]
    private var locks: [Int64: Bool] = [:]

    func wait(
        uid: Int64,
        gapS: Double? = nil,
        isStopped: @escaping @Sendable () -> Bool,
        addLog: @escaping @Sendable (String) -> Void,
        floorS: Double = listMinGapS
    ) async -> Bool {
        let floor = floorS
        let gap = max(floor, gapS ?? floor)
        while isLocked(uid) {
            if isStopped() { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        setLocked(uid, true)
        if isStopped() {
            setLocked(uid, false)
            return false
        }
        let last = getLastMark(uid)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var needMs = last > 0 ? Int64(gap * 1000) - (now - last) : 0
        if needMs > 0 {
            addLog(String(format: "挂单硬间隔等待 %.1fs (目标%.1fs,底线%.1fs)", Double(needMs) / 1000.0, gap, floor))
        }
        while needMs > 0 {
            if isStopped() {
                setLocked(uid, false)
                return false
            }
            let slice = min(500, needMs)
            try? await Task.sleep(nanoseconds: UInt64(slice) * 1_000_000)
            let n2 = Int64(Date().timeIntervalSince1970 * 1000)
            needMs = last > 0 ? Int64(gap * 1000) - (n2 - last) : 0
        }
        return true
    }

    func mark(uid: Int64) {
        lock.lock()
        lastMarkMs[uid] = Int64(Date().timeIntervalSince1970 * 1000)
        locks[uid] = false
        lock.unlock()
    }

    func release(uid: Int64) {
        setLocked(uid, false)
    }

    private func isLocked(_ uid: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return locks[uid] == true
    }

    private func setLocked(_ uid: Int64, _ value: Bool) {
        lock.lock()
        locks[uid] = value
        lock.unlock()
    }

    private func getLastMark(_ uid: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return lastMarkMs[uid] ?? 0
    }
}
