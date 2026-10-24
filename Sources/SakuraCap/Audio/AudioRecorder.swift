import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import AppKit

// MARK: - 纯音频封装（m4a，1–2 条 AAC 轨，轨元数据与录屏一致）

final class AudioFileWriter {
    private let queue = DispatchQueue(label: "com.sakura.sakuracap.audiowriter", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let inputs: [AudioTrackKind: AVAssetWriterInput]
    private let expected: [AudioTrackKind: (sampleRate: Double, channels: Int)]

    private let fileURL: URL
    private var started = false
    private var armed = false
    private var finished = false
    private var firstPTS: CMTime?
    private var lastPTS: CMTime?

    // 暂停/继续：与录屏 FileWriter 相同的 PTS 重排策略
    private var isPaused = false
    private var needsResumeAdjust = false
    private var ptsOffset = CMTime.zero
    private var lastInputPTS: CMTime?
    private var frameDuration = CMTime(value: 1, timescale: 600)
    private var warnedFormatMismatch = Set<AudioTrackKind>()
    private var warnedAppendFailure = false

    init(fileURL: URL, tracks: [AudioTrackSetup]) throws {
        self.fileURL = fileURL
        try? FileManager.default.removeItem(at: fileURL)
        writer = try AVAssetWriter(outputURL: fileURL, fileType: .m4a)
        var inputs: [AudioTrackKind: AVAssetWriterInput] = [:]
        var expected: [AudioTrackKind: (Double, Int)] = [:]
        for setup in tracks {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: setup.sampleRate,
                AVNumberOfChannelsKey: setup.channels,
                AVEncoderBitRateKey: setup.channels >= 2 ? 160_000 : 96_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let label = AVMutableMetadataItem()
            label.identifier = .commonIdentifierTitle
            label.value = (setup.kind == .system ? "sakuracap.system" : "sakuracap.microphone") as NSString
            input.metadata = [label]
            writer.add(input)
            inputs[setup.kind] = input
            expected[setup.kind] = (setup.sampleRate, setup.channels)
        }
        self.inputs = inputs
        self.expected = expected
        writer.startWriting()
    }

    func arm() { queue.async { self.armed = true } }

    func pause() { queue.async { self.isPaused = true } }

    func resume() {
        queue.async {
            self.isPaused = false
            self.needsResumeAdjust = true
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer, track: AudioTrackKind) {
        queue.async {
            guard self.armed, !self.finished, self.writer.status == .writing, !self.isPaused else { return }
            guard let input = self.inputs[track] else { return }
            if self.needsResumeAdjust { self.applyResumeOffset(inputPTS: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) }
            let buffer = self.ptsOffset == .zero ? sampleBuffer
                : AudioFileWriter.retimed(sampleBuffer, by: self.ptsOffset)
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
            if !self.started {
                self.writer.startSession(atSourceTime: pts)
                self.started = true
                self.firstPTS = pts
            } else if CMTimeCompare(pts, self.firstPTS!) < 0 {
                return
            }
            if let format = self.expected[track] {
                let matches: Bool = {
                    guard let desc = CMSampleBufferGetFormatDescription(buffer),
                          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return false }
                    return abs(asbd.mSampleRate - format.sampleRate) < 1 && Int(asbd.mChannelsPerFrame) == format.channels
                }()
                if !matches, !self.warnedFormatMismatch.contains(track) {
                    self.warnedFormatMismatch.insert(track)
                    Log.audio.error("音轨格式与预建不符，丢弃（track=\(String(describing: track), privacy: .public)）")
                    return
                }
            }
            guard input.isReadyForMoreMediaData else { return }
            if input.append(buffer) {
                self.lastInputPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if self.lastPTS == nil || CMTimeCompare(pts, self.lastPTS!) > 0 { self.lastPTS = pts }
            } else if !self.warnedAppendFailure {
                self.warnedAppendFailure = true
                Log.audio.error("音频写入失败: \(self.writer.error?.localizedDescription ?? "未知", privacy: .public)")
            }
        }
    }

    private func applyResumeOffset(inputPTS: CMTime) {
        needsResumeAdjust = false
        guard let last = lastInputPTS else { return }
        let gap = CMTimeSubtract(inputPTS, last)
        if CMTimeCompare(gap, frameDuration) > 0 {
            ptsOffset = CMTimeAdd(ptsOffset, CMTimeSubtract(gap, frameDuration))
        }
    }

    private static func retimed(_ sampleBuffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer {
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0 else { return sampleBuffer }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        let status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count,
                                                            arrayToFill: &timing, entriesNeededOut: nil)
        guard status == noErr else { return sampleBuffer }
        for i in 0..<count {
            timing[i].presentationTimeStamp = CMTimeSubtract(timing[i].presentationTimeStamp, offset)
            if timing[i].decodeTimeStamp.isValid && !timing[i].decodeTimeStamp.isIndefinite {
                timing[i].decodeTimeStamp = CMTimeSubtract(timing[i].decodeTimeStamp, offset)
            }
        }
        var out: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                                 sampleBuffer: sampleBuffer,
                                                                 sampleTimingEntryCount: count,
                                                                 sampleTimingArray: &timing,
                                                                 sampleBufferOut: &out)
        return createStatus == noErr ? (out ?? sampleBuffer) : sampleBuffer
    }

    func finish(discard: Bool) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.finished else { continuation.resume(returning: nil); return }
                self.finished = true
                self.armed = false
                for input in self.inputs.values { input.markAsFinished() }
                if discard {
                    try? FileManager.default.removeItem(at: self.fileURL)
                    continuation.resume(returning: nil)
                    return
                }
                guard self.started else {
                    try? FileManager.default.removeItem(at: self.fileURL)
                    continuation.resume(returning: nil)
                    return
                }
                if let last = self.lastPTS { self.writer.endSession(atSourceTime: last) }
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        continuation.resume(returning: self.fileURL)
                    } else {
                        try? FileManager.default.removeItem(at: self.fileURL)
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

// MARK: - 录音控制器（系统声音：SCK 音频流；麦克风：MicCapture）

/// SCK 音频回调的落点：只持有不可变的 writer 引用。
/// 回调运行在 SCK 的工作队列上，绝不能读 MainActor 可变状态（如 self.writer）——
/// 否则与主线程 cleanup() 置 nil 构成跨线程竞态（视频链路的 FileWriter 同样只碰不可变捕获）。
private final class SystemAudioSink: NSObject, SCStreamOutput {
    private let writer: AudioFileWriter
    init(writer: AudioFileWriter) { self.writer = writer }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        writer.append(sampleBuffer, track: .system)
    }
}

@MainActor
final class AudioRecorderController: NSObject, ObservableObject {
    static let shared = AudioRecorderController()

    enum State: Equatable { case idle, recording, paused }
    enum Source: String, CaseIterable, Identifiable {
        case system, microphone, both
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return L("录制系统声音")
            case .microphone: return L("录制麦克风")
            case .both: return L("系统声音 + 麦克风")
            }
        }
        var wantsSystem: Bool { self != .microphone }
        var wantsMic: Bool { self != .system }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// 最近一次成功保存的文件（调试/测试用）
    private(set) var lastSavedURL: URL?

    private(set) var source: Source = .both
    private var stream: SCStream?
    private var systemSink: SystemAudioSink?
    private var mic: MicCapture?
    private var writer: AudioFileWriter?
    private var timer: Timer?
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?

    var isBusy: Bool { state != .idle }

    // MARK: 权限

    private func permissionsSatisfied(_ source: Source) -> Bool {
        if source.wantsSystem, !PermissionCenter.screenCaptureGranted() {
            PermissionCenter.openScreenCaptureSettings()
            Toast.show(title: L("需要「屏幕录制」权限"), detail: L("系统声音采集同样依赖屏幕录制授权"))
            return false
        }
        if source.wantsMic {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                break
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    Task { @MainActor in
                        if granted { self?.start(source) }
                    }
                }
                return false
            default:
                PermissionCenter.openMicrophoneSettings()
                Toast.show(title: L("需要麦克风权限"), detail: L("请在系统设置中允许麦克风访问"))
                return false
            }
        }
        return true
    }

    // MARK: 控制

    func toggle(_ source: Source) {
        state == .idle ? start(source) : stop()
    }

    func togglePause() {
        switch state {
        case .recording:
            state = .paused
            writer?.pause()
            accumulated += Date().timeIntervalSince(segmentStart ?? Date())
            segmentStart = nil
        case .paused:
            state = .recording
            segmentStart = Date()
            writer?.resume()
        case .idle:
            break
        }
    }

    func start(_ source: Source) {
        guard state == .idle else { return }
        guard permissionsSatisfied(source) else { return }
        guard let directory = OutputDirectoryPicker.ensureDirectory(current: AppSettings.shared.outputDirectory) else { return }
        Task { await beginRecording(source: source, directory: directory) }
    }

    private func beginRecording(source: Source, directory: URL) async {
        guard state == .idle else { return }
        self.source = source
        do {
            var tracks: [AudioTrackSetup] = []
            var micFormat: (sampleRate: Double, channels: Int)?
            if source.wantsMic {
                let mic = MicCapture()
                try mic.start()
                micFormat = await mic.waitForFormat(timeout: 2) ?? (48000, 1)
                self.mic = mic
                tracks.append(AudioTrackSetup(kind: .microphone,
                                              sampleRate: micFormat!.sampleRate,
                                              channels: micFormat!.channels))
            }
            if source.wantsSystem {
                tracks.append(AudioTrackSetup(kind: .system, sampleRate: 48000, channels: 2))
            }
            let url = directory.appendingPathComponent(FileName.make(ext: "m4a"))
            let writer = try AudioFileWriter(fileURL: url, tracks: tracks)
            writer.arm()
            self.writer = writer

            if source.wantsSystem {
                try await startSystemStream()
            }
            if let mic {
                mic.setOnBuffer { [weak writer] buffer in
                    writer?.append(buffer, track: .microphone)
                }
            }

            accumulated = 0
            segmentStart = Date()
            elapsed = 0
            state = .recording
            startTimer()
            AudioHUDController.shared.show(controller: self)
            Log.audio.notice("开始录音: \(source.rawValue, privacy: .public)")
        } catch {
            Toast.show(title: L("录音失败"), detail: error.localizedDescription)
            cleanup()
        }
    }

    func stop() {
        guard state != .idle else { return }
        let duration = elapsed
        let wasPaused = state == .paused
        state = .idle
        stopTimer()
        AudioHUDController.shared.hide()
        let writer = self.writer
        Task { @MainActor in
            _ = wasPaused
            if let url = await writer?.finish(discard: false) {
                self.lastSavedURL = url
                CompletionNotifier.shared.postSaved(url: url, duration: duration)
                Toast.show(title: L("已保存录音"), detail: url.lastPathComponent)
                // 按设置自动打开音频编辑器（片段裁剪 / 淡入淡出 / 音量段）
                if AppSettings.shared.autoTrimAfterRecording {
                    AudioEditorPresenter.shared.show(url: url, origin: .recording)
                }
            } else {
                Toast.show(title: L("没有录到声音"), detail: nil)
            }
            self.cleanup()
            Log.audio.notice("停止录音，时长 \(duration)")
        }
    }

    private func startSystemStream() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { CGDisplayIsMain($0.displayID) != 0 })
            ?? content.displays.first else { throw RecordingError.noDisplays }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // 音频采集不需要画面，缓冲给最小即可
        config.width = 2
        config.height = 2
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        // 不显式设采样率：SCK 默认 48k/2ch，与预建轨一致（与录屏系统声相同行为）
        // 与录屏一致的完整配置：实测缺省配置下系统声几乎不送缓冲
        config.queueDepth = 6
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        if #available(macOS 14.0, *) {
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.captureResolution = .best
        }
        // writer 在调用方已建好：sink 持不可变引用，回调线程安全
        guard let writer else { throw RecordingError.noDisplays }
        let sink = SystemAudioSink(writer: writer)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: nil)
        // SCK 要求同时挂视频输出，否则音频一个缓冲都不会送（视频帧由 sink 丢弃）
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: nil)
        try await stream.startCapture()
        self.stream = stream
        self.systemSink = sink
    }

    // MARK: 计时

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.state == .recording, let start = self.segmentStart {
                    self.elapsed = self.accumulated + Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func cleanup() {
        if let stream {
            Task { try? await stream.stopCapture() }
        }
        stream = nil
        systemSink = nil
        mic?.stop()
        mic = nil
        writer = nil
        stopTimer()
        state = .idle
        segmentStart = nil
    }
}
