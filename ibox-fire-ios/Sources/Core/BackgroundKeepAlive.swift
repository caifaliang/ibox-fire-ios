import AVFoundation
import Combine
import UIKit

/// 自签分发场景下的锁屏/后台保活：
/// - 主路径：`UIBackgroundModes=audio` + 循环静音播放（可锁屏继续跑本地引擎）
/// - 辅路径：`beginBackgroundTask` 短续期
/// 非 App Store；系统仍可能在极端省电/内存压力下杀进程。
@MainActor
final class BackgroundKeepAlive: ObservableObject {
    static let shared = BackgroundKeepAlive()

    @Published private(set) var isActive = false
    /// 供 UI 展示
    @Published private(set) var statusText = "未开启"

    private var player: AVAudioPlayer?
    private var taskId: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []
    private var silenceURL: URL?

    func begin() {
        if isActive {
            // 已在跑：确保音频未停
            if player?.isPlaying != true { startAudioSessionAndPlay() }
            renewBackgroundTask()
            return
        }
        isActive = true
        statusText = "音频保活启动中…"
        installSessionObservers()
        startAudioSessionAndPlay()
        renewBackgroundTask()
        statusText = player?.isPlaying == true ? "音频保活中（可锁屏/切后台）" : "保活已请求（音频未就绪）"
    }

    func end() {
        guard isActive || player != nil || taskId != .invalid else { return }
        isActive = false
        statusText = "已停止"
        tearDownObservers()
        stopAudio()
        endBackgroundTask()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio

    private func startAudioSessionAndPlay() {
        let session = AVAudioSession.sharedInstance()
        do {
            // mixWithOthers：尽量不抢占用户正在听的音乐；playback 才能进后台
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            statusText = "音频会话失败: \(error.localizedDescription)"
            return
        }
        let url: URL
        do {
            url = try ensureSilenceFile()
        } catch {
            statusText = "静音文件失败: \(error.localizedDescription)"
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.01 // 极低音量；部分系统对 volume=0 可能优化掉播放
            p.prepareToPlay()
            if !p.play() {
                statusText = "静音播放未能启动"
            }
            player = p
        } catch {
            statusText = "播放器失败: \(error.localizedDescription)"
        }
    }

    private func stopAudio() {
        player?.stop()
        player = nil
    }

    /// 生成约 2s 单声道 8kHz 16-bit PCM 静音 WAV（落盘复用）
    private func ensureSilenceFile() throws -> URL {
        if let silenceURL, FileManager.default.fileExists(atPath: silenceURL.path) {
            return silenceURL
        }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ibox_keepalive_silence.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            silenceURL = url
            return url
        }

        let sampleRate: Int = 8000
        let channels: Int = 1
        let bitsPerSample: Int = 16
        let durationSec = 2
        let numSamples = sampleRate * durationSec
        let dataSize = numSamples * channels * (bitsPerSample / 8)

        var data = Data()
        data.reserveCapacity(44 + dataSize)
        func appendASCII(_ s: String) { data.append(contentsOf: s.utf8) }
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendU32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendU32(16) // PCM chunk size
        appendU16(1) // PCM
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * channels * bitsPerSample / 8))
        appendU16(UInt16(channels * bitsPerSample / 8))
        appendU16(UInt16(bitsPerSample))
        appendASCII("data")
        appendU32(UInt32(dataSize))
        data.append(Data(count: dataSize)) // zeros = silence

        try data.write(to: url, options: .atomic)
        silenceURL = url
        return url
    }

    // MARK: - Background task (short leash)

    private func renewBackgroundTask() {
        endBackgroundTask()
        taskId = UIApplication.shared.beginBackgroundTask(withName: "ibox.fire.keepalive") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
            taskId = .invalid
        }
    }

    // MARK: - Interruptions

    private func installSessionObservers() {
        tearDownObservers()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleInterruption(note)
            }
        })
        observers.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.startAudioSessionAndPlay()
                self.renewBackgroundTask()
            }
        })
        observers.append(nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                if self.player?.isPlaying != true {
                    self.startAudioSessionAndPlay()
                }
                self.renewBackgroundTask()
                self.statusText = self.player?.isPlaying == true
                    ? "音频保活中（后台/锁屏）"
                    : "后台中·音频未播"
            }
        })
        observers.append(nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                if self.player?.isPlaying != true {
                    self.startAudioSessionAndPlay()
                }
                self.statusText = "音频保活中（前台）"
            }
        })
    }

    private func tearDownObservers() {
        let nc = NotificationCenter.default
        for o in observers { nc.removeObserver(o) }
        observers.removeAll()
    }

    private func handleInterruption(_ note: Notification) {
        guard isActive else { return }
        guard let info = note.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
        switch type {
        case .began:
            statusText = "音频被中断（来电等）"
        case .ended:
            // 自签保活：中断结束后尽量一律续播（不依赖 shouldResume）
            startAudioSessionAndPlay()
            renewBackgroundTask()
            statusText = "音频保活已恢复"
        @unknown default:
            break
        }
    }
}
