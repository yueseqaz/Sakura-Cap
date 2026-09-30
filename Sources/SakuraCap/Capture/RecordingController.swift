import AppKit
import AVFoundation
import ScreenCaptureKit

/// 录制状态机：idle → preparing → countdown → recording → finalizing → idle。
/// 对外唯一入口（toggle/start/stop），面板、快捷键、菜单都走它。
@MainActor
final class RecordingController: ObservableObject {
    enum State: Equatable {
        case idle, ready, preparing, countdown, recording, finalizing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isPaused = false
    @Published var banner: String?

    private(set) var lastSavedFiles: [URL] = []

    let settings = AppSettings.shared

    private var sessions: [StreamSession] = []
    private var mic: MicCapture?
    private var timer: Timer?
    private var recordStart: Date?
    private var pauseStartedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var generation = 0
    private let screenMonitor = ScreenChangeMonitor()

    init() {
        screenMonitor.onScreensChanged = { [weak self] in self?.handleScreensChanged() }
    }

    var isBusy: Bool { state != .idle }

    func toggle() {
        switch state {
        case .idle, .ready:
            start()
        default:
            stop()
        }
    }

    /// 选择完成后进入「待开始」：不立即采集，等用户点「开始录制」
    func arm() {
        guard state == .idle else { return }
        banner = nil
        state = .ready
    }

    /// 取消「待开始」状态
    func cancelArmed() {
        guard state == .ready else { return }
        state = .idle
    }

    /// 暂停/继续（仅录制中有意义）
    func togglePause() {
        guard state == .recording else { return }
        if isPaused {
            if let start = pauseStartedAt { pausedTotal += Date().timeIntervalSince(start) }
            pauseStartedAt = nil
            isPaused = false
            for session in sessions { session.resume() }
            Log.app.info("录制已继续")
        } else {
            isPaused = true
            pauseStartedAt = Date()
            for session in sessions { session.pause() }
            Log.app.info("录制已暂停")
        }
    }

    func start() {
        guard state == .idle || state == .ready else { return }
        generation += 1
        let gen = generation
        Task { await startFlow(generation: gen) }
    }

    func stop() {
        guard state != .idle, state != .finalizing else { return }
        generation += 1
        Task { await stopFlow() }
    }

    // MARK: - 启动流程

    private func startFlow(generation gen: Int) async {
        state = .preparing
        banner = nil

        /// 失败统一出口：写持久化错误日志 + 可选弹窗（默认弹，确保用户不可能忽略）
        func abort(_ message: String, showAlert: Bool = true) {
            Log.app.error("录制启动失败: \(message, privacy: .public)")
            banner = message
            if showAlert {
                let alert = NSAlert()
                alert.messageText = "无法开始录制"
                alert.informativeText = message
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
            state = .idle
        }

        // 1. 屏幕录制权限
        guard PermissionCenter.screenCaptureGranted() else {
            PermissionCenter.openScreenCaptureSettings()
            abort("需要「屏幕录制」权限。已为你打开系统设置，请在「隐私与安全性 → 屏幕录制」中允许 Sakura-Cap，然后重新开始录制。")
            return
        }
        guard gen == generation else { return }

        // 2. 输出目录（必须由用户选择）
        guard let directory = OutputDirectoryPicker.ensureDirectory(current: settings.outputDirectory) else {
            abort("未选择输出目录，已取消录制", showAlert: false)
            return
        }
        settings.outputDirectory = directory

        // 3. 刷新可采集内容（含窗口、显示器，天然覆盖热插拔）
        let catalog = DisplayCatalog.shared
        do {
            let displays = try await catalog.refresh()
            Log.app.notice("可采集内容: \(displays.count) 台显示器")
            if displays.isEmpty {
                PermissionCenter.openScreenCaptureSettings()
                abort("没有检测到可录制的显示器。请确认已在「隐私与安全性 → 屏幕录制」中允许 Sakura-Cap 访问。")
                return
            }
        } catch {
            abort("无法获取可录制的内容。请在「隐私与安全性 → 屏幕录制」中确认已允许 Sakura-Cap 访问。")
            return
        }
        guard gen == generation else { return }

        // 4. 生成录制计划
        let specs: [StreamSpec]
        do {
            specs = try StreamPlanner.buildSpecs(settings: settings, catalog: catalog)
            for spec in specs {
                Log.app.notice("录制计划: \(spec.displayName, privacy: .public) \(spec.pixelWidth)×\(spec.pixelHeight) @\(spec.config.sourceRect.origin.x),\(spec.config.sourceRect.origin.y)+\(spec.config.sourceRect.width)x\(spec.config.sourceRect.height) 音频=\(spec.capturesSystemAudio)")
            }
        } catch {
            abort("无法开始录制：\(error.localizedDescription)")
            return
        }

        // 5. 点击指示 / 按键显示（可选功能，失败不阻断录制）
        if settings.clickIndicatorEnabled {
            IndicatorEngine.shared.beginCapture()
            if !IndicatorEngine.shared.isMonitoring {
                banner = "未获得「输入监控」权限，本次录制不含点击标记（不影响录制）。"
            }
        }
        if settings.keyDisplayEnabled {
            KeyDisplay.shared.beginCapture()
            if !KeyDisplay.shared.isMonitoring {
                banner = "未获得「输入监控」权限，本次录制不含按键提示（不影响录制）。"
            }
        }

        // 6. 麦克风：先启动并拿到实测格式（writer 建轨必须在 startWriting 之前，否则闪退）
        var micFormat: (sampleRate: Double, channels: Int)?
        if settings.recordMicrophone {
            micFormat = await startMicrophoneAndGetFormat()
        }
        guard gen == generation, state == .preparing else {
            mic?.stop(); mic = nil
            state = .idle
            return
        }

        // 7. 创建各路 writer + stream（writer 未 arm，先热身丢帧，保证倒计时不入视频）
        sessions.removeAll()
        do {
            // 麦克风音轨只加进将要接收它的那一路 writer（并行模式 = 主屏路）
            let micTargetIndex: Int? = micFormat == nil
                ? nil
                : (specs.firstIndex { $0.capturesSystemAudio } ?? specs.indices.first)
            for (index, spec) in specs.enumerated() {
                sessions.append(try StreamSession(
                    spec: spec,
                    codec: settings.codec.avCodecType,
                    quality: settings.quality,
                    frameRate: settings.fps.rawValue,
                    customBitrateMbps: settings.customBitrateMbps,
                    systemAudio: spec.capturesSystemAudio,
                    micAudio: index == micTargetIndex ? micFormat : nil))
            }
            if let capture = mic, let micTargetIndex,
               sessions.indices.contains(micTargetIndex) {
                let micWriter = sessions[micTargetIndex].writer
                capture.setOnBuffer { buffer in
                    micWriter.appendAudio(buffer, track: .microphone)
                }
            }
        } catch {
            mic?.stop(); mic = nil
            IndicatorEngine.shared.endCapture()
            KeyDisplay.shared.endCapture()
            _ = await teardownSessions(saveFiles: false)
            abort("无法启动屏幕采集。请在「隐私与安全性 → 屏幕录制」中确认已允许 Sakura-Cap 访问。")
            return
        }
        guard gen == generation, state == .preparing else {
            IndicatorEngine.shared.endCapture()
            KeyDisplay.shared.endCapture()
            mic?.stop(); mic = nil
            _ = await teardownSessions(saveFiles: false)
            state = .idle
            return
        }

        // 8. 启动采集
        do {
            for session in sessions {
                try await session.start()
            }
        } catch {
            IndicatorEngine.shared.endCapture()
            KeyDisplay.shared.endCapture()
            mic?.stop(); mic = nil
            _ = await teardownSessions(saveFiles: true)
            abort("无法启动录制，请重试。若反复失败，请在「隐私与安全性 → 屏幕录制」中确认已允许 Sakura-Cap 访问。")
            return
        }
        guard gen == generation, state == .preparing else {
            IndicatorEngine.shared.endCapture()
            KeyDisplay.shared.endCapture()
            mic?.stop(); mic = nil
            _ = await teardownSessions(saveFiles: false)
            state = .idle
            return
        }

        // 9. 倒计时（不入视频）
        if settings.countdownEnabled {
            state = .countdown
            await CountdownCoordinator.run(seconds: 3, on: countdownScreens()) {
                self.generation == gen && self.state == .countdown
            }
            guard gen == generation, state == .countdown else {
                IndicatorEngine.shared.endCapture()
                KeyDisplay.shared.endCapture()
                mic?.stop(); mic = nil
                _ = await teardownSessions(saveFiles: false)
                state = .idle
                return
            }
        }

        // 10. 正式开录
        for session in sessions { session.armWriter() }
        recordStart = Date()
        pauseStartedAt = nil
        pausedTotal = 0
        isPaused = false
        elapsed = 0
        startTimer()
        state = .recording
        SoundCue.playStart()
        if settings.dndDuringRecording { FocusMode.run(shortcut: settings.dndOnShortcut) }
        Log.app.info("开始录制：\(self.sessions.count) 路输出")
    }

    /// 先启动麦克风并等待实测格式。格式必须在创建 FileWriter 前已知——
    /// AVAssetWriter 的所有轨道必须在 startWriting() 之前添加，懒建轨会抛异常闪退。
    private func startMicrophoneAndGetFormat() async -> (sampleRate: Double, channels: Int)? {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        var granted = status == .authorized
        if status == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        }
        guard granted else {
            banner = "未获得麦克风权限，本次录制不含麦克风声音。"
            return nil
        }
        let capture = MicCapture()
        do {
            try capture.start()
        } catch {
            banner = "麦克风不可用，本次录制不含麦克风声音。"
            return nil
        }
        guard let format = await capture.waitForFormat(timeout: 1.5) else {
            capture.stop()
            banner = "麦克风未就绪，本次录制不含麦克风声音。"
            return nil
        }
        mic = capture
        return format
    }

    // MARK: - 停止流程

    private func stopFlow() async {
        let wasRecording = state == .recording
        state = .finalizing
        stopTimer()
        isPaused = false
        pauseStartedAt = nil
        if wasRecording { SoundCue.playStop() }
        IndicatorEngine.shared.endCapture()
        KeyDisplay.shared.endCapture()
        mic?.stop(); mic = nil

        let duration = elapsed
        let files = await teardownSessions(saveFiles: true)
        lastSavedFiles = files
        recordStart = nil
        elapsed = 0
        state = .idle
        if wasRecording, settings.dndDuringRecording { FocusMode.run(shortcut: settings.dndOffShortcut) }

        if wasRecording {
            if files.isEmpty {
                let message = "本次没有录到画面，文件未保存。请在「隐私与安全性 → 屏幕录制」中确认已允许 Sakura-Cap 访问，然后重试。"
                Log.app.error("录制零帧: \(message, privacy: .public)")
                banner = message
                let alert = NSAlert()
                alert.messageText = "未捕获到有效画面"
                alert.informativeText = message
                alert.addButton(withTitle: "好")
                alert.runModal()
            } else {
                for url in files {
                    CompletionNotifier.shared.postSaved(url: url, duration: duration)
                }
                // 保存/通知等原有逻辑不变，额外自动打开裁剪页处理刚保存的视频
                if let first = files.first {
                    TrimWindowController.shared.show(url: first)
                }
            }
        }
        Log.app.notice("停止录制，保存 \(files.count) 个文件，时长 \(duration)")
    }

    private func teardownSessions(saveFiles: Bool) async -> [URL] {
        let pending = sessions
        sessions.removeAll()
        var files: [URL] = []
        for session in pending {
            if let url = await session.finish(discardFiles: !saveFiles) {
                files.append(url)
            }
        }
        return files
    }

    // MARK: - 计时

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let start = recordStart else { return }
        var paused = pausedTotal
        if let pauseStart = pauseStartedAt { paused += Date().timeIntervalSince(pauseStart) }
        elapsed = max(0, Date().timeIntervalSince(start) - paused)
    }

    // MARK: - 显示器热插拔（录制中被拔屏 → 优雅停止并保存该路文件）

    private func handleScreensChanged() {
        guard state == .recording else { return }
        var activeIDs = Set<CGDirectDisplayID>()
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(32, &ids, &count) == .success {
            activeIDs = Set(ids.prefix(Int(count)))
        }
        let detached = sessions.filter { session in
            guard let id = session.spec.displayID else { return false } // 窗口模式由 SCK 跟随，不受影响
            return !activeIDs.contains(id)
        }
        guard !detached.isEmpty else { return }
        Task { [weak self] in
            for session in detached {
                if let url = await session.finish(discardFiles: false) {
                    CompletionNotifier.shared.postSaved(url: url, duration: 0)
                }
                await MainActor.run { self?.sessions.removeAll { $0 === session } }
            }
            await MainActor.run {
                if self?.sessions.isEmpty == true {
                    self?.stop()
                } else {
                    self?.banner = "检测到显示器断开，对应录像已保存"
                }
            }
        }
    }

    // MARK: - 倒计时覆盖的目标屏幕

    private func countdownScreens() -> [NSScreen] {
        var screens: [NSScreen] = []
        for session in sessions {
            guard let id = session.spec.displayID,
                  let screen = NSScreen.screens.first(where: { $0.displayID == id }),
                  !screens.contains(screen) else { continue }
            screens.append(screen)
        }
        if screens.isEmpty, let main = NSScreen.main ?? NSScreen.screens.first {
            screens = [main]
        }
        return screens
    }

    // MARK: - 退出兜底

    func emergencyFinalize() {
        guard isBusy else { return }
        for session in sessions {
            _ = session.finishSyncBestEffort()
        }
    }
}
