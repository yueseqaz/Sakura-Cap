import AVFoundation
import Foundation
import Speech

/// 字幕条：时间与工作台「当前合成」的时间轴对齐（含剪辑/静音效果），start/end 单位秒。
struct SubtitleCue: Equatable {
    var start: Double
    var end: Double
    let text: String
}

/// 语音转写：把工作台当前合成的音轨导出为临时 m4a，再用系统 SFSpeechRecognizer 识别。
/// 优先设备端离线识别（语音不上传）；结果按识别分段切成字幕条。
enum SubtitleTranscriber {
    enum TranscribeError: LocalizedError {
        case unauthorized
        case recognizerUnavailable
        case modelUnavailable(String)
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return L("未获得「语音识别」权限，请在系统设置 → 隐私与安全性中允许。")
            case .recognizerUnavailable:
                return L("当前语言不支持语音识别。")
            case .modelUnavailable(let message):
                return String(format: L("离线语音模型不可用：%@"), message)
            case .recognitionFailed(let message):
                return message
            }
        }
    }

    /// 把合成时间线的音频（应用音量/静音混音）导出为 m4a，供识别器读取。
    static func exportTimelineAudio(asset: AVAsset, audioMix: AVAudioMix?, to url: URL) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SubtitleTranscriberError.exportSessionUnavailable
        }
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = true
        if #available(macOS 15.0, *) {
            try await exporter.export(to: url, as: .m4a)
        } else {
            exporter.outputURL = url
            exporter.outputFileType = .m4a
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    if let error = exporter.error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
    }

    /// 申请「语音识别」权限（首次调用会弹系统授权框）。
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    /// 分块时长：旧引擎（macOS 13–15）对长音频有约 1 分钟的可靠上限，
    /// 长音频按 24 秒切块（0.5 秒重叠防切词），逐块识别后按时间合并。
    private static let chunkLength: Double = 24
    private static let chunkOverlap: Double = 0.5

    /// 识别整条音频，返回按时间升序的字幕条。progress 传入已识别到的秒数（任意线程回调）。
    /// macOS 26+ 走 SpeechAnalyzer（全离线、全程时间索引、实测完整覆盖长音频，
    /// 且无需「语音识别」权限）；旧系统退回 SFSpeechRecognizer 分块识别。
    static func recognize(audioURL: URL, locale: Locale,
                          progress: @escaping @Sendable (Double) -> Void) async throws -> [SubtitleCue] {
        if #available(macOS 26.0, *), SpeechTranscriber.isAvailable {
            return try await recognizeWithAnalyzer(audioURL: audioURL, locale: locale, progress: progress)
        }
        return try await recognizeLegacy(audioURL: audioURL, locale: locale, progress: progress)
    }

    // MARK: SpeechAnalyzer（macOS 26+）

    @available(macOS 26.0, *)
    private static func recognizeWithAnalyzer(audioURL: URL, locale: Locale,
                                              progress: @escaping @Sendable (Double) -> Void) async throws -> [SubtitleCue] {
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(resolved) else { throw TranscribeError.recognizerUnavailable }

        let transcriber = SpeechTranscriber(locale: resolved, preset: .timeIndexedTranscriptionWithAlternatives)
        do {
            // 语言模型未就绪时现场下载（首次使用某语言才会发生）
            if await AssetInventory.status(forModules: [transcriber]) != .installed,
               let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw TranscribeError.modelUnavailable(error.localizedDescription)
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: audioURL)
        } catch {
            throw TranscribeError.recognitionFailed(error.localizedDescription)
        }
        let totalSeconds = max(0.1, Double(file.length) / file.processingFormat.sampleRate)

        // 消费结果流：每个 result 自带音频时间范围，正好当字幕条
        let collector = Task { () -> [SubtitleCue] in
            var cues: [SubtitleCue] = []
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let start = max(0, result.range.start.seconds)
                    let end = min(totalSeconds, max(start + 0.4, result.range.end.seconds))
                    guard end > start else { continue }
                    cues.append(SubtitleCue(start: start, end: end, text: text))
                    progress(end)
                }
            } catch {
                Log.app.error("字幕识别流中断: \(error.localizedDescription, privacy: .public)")
            }
            return cues
        }
        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        } catch {
            collector.cancel()
            throw TranscribeError.recognitionFailed(error.localizedDescription)
        }
        return await collector.value
    }

    // MARK: SFSpeechRecognizer 分块（macOS 13–15 兜底）

    private static func recognizeLegacy(audioURL: URL, locale: Locale,
                                        progress: @escaping @Sendable (Double) -> Void) async throws -> [SubtitleCue] {
        guard await requestAuthorization() else { throw TranscribeError.unauthorized }
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw TranscribeError.recognitionFailed(L("无法读取音频时长"))
        }

        if duration <= chunkLength + 1 {
            return try await recognizeRange(audioURL: audioURL, locale: locale, offset: 0, progress: progress)
        }

        let step = chunkLength - chunkOverlap
        let chunkCount = Int(((duration - chunkOverlap) / step).rounded(.up))
        var cues: [SubtitleCue] = []
        var lastEnd = 0.0
        var chunkStart = 0.0
        var failedChunks = 0
        var index = 0
        while chunkStart < duration - 0.2 {
            let chunkIndex = index
            let chunkEnd = min(duration, chunkStart + chunkLength)
            let range = CMTimeRange(start: CMTime(seconds: chunkStart, preferredTimescale: 600),
                                    end: CMTime(seconds: chunkEnd, preferredTimescale: 600))
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sakuracap-chunk-\(UUID().uuidString).m4a")
            do {
                try await exportAudioChunk(asset: asset, range: range, to: chunkURL)
                let chunkDuration = max(0.1, chunkEnd - chunkStart)
                let chunkCues = try await recognizeRange(audioURL: chunkURL, locale: locale, offset: chunkStart) { seconds in
                    let local = min(1, seconds / chunkDuration)
                    progress((Double(chunkIndex) + local) / Double(chunkCount) * duration)
                }
                // 重叠区去重：起点已被上一块覆盖的条目丢弃
                for cue in chunkCues where cue.start >= lastEnd - 0.02 {
                    cues.append(cue)
                    lastEnd = max(lastEnd, cue.end)
                }
            } catch {
                failedChunks += 1
                Log.app.error("字幕分段转写失败 @\(chunkStart, privacy: .public)s: \(error.localizedDescription, privacy: .public)")
            }
            try? FileManager.default.removeItem(at: chunkURL)
            index += 1
            chunkStart += step
        }
        guard !cues.isEmpty else {
            throw TranscribeError.recognitionFailed(
                String(format: L("分段识别失败（成功 %d / 共 %d 段）"), chunkCount - failedChunks, chunkCount))
        }
        return cues
    }

    /// 识别一段音频：先设备端（语音不出本机），失败降级服务端重试一次。
    private static func recognizeRange(audioURL: URL, locale: Locale, offset: Double,
                                       progress: @escaping @Sendable (Double) -> Void) async throws -> [SubtitleCue] {
        do {
            return try await runRecognition(audioURL: audioURL, locale: locale, onDevice: true,
                                            offset: offset, progress: progress)
        } catch {
            Log.app.error("设备端识别失败，改用服务端重试: \(error.localizedDescription, privacy: .public)")
            return try await runRecognition(audioURL: audioURL, locale: locale, onDevice: false,
                                            offset: offset, progress: progress)
        }
    }

    private static func runRecognition(audioURL: URL, locale: Locale, onDevice: Bool, offset: Double,
                                       progress: @escaping @Sendable (Double) -> Void) async throws -> [SubtitleCue] {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscribeError.recognizerUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        if onDevice, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { cont in
            var settled = false
            recognizer.recognitionTask(with: request) { result, error in
                if settled { return }
                if let result {
                    let cues = Self.cues(from: result.bestTranscription, offset: offset)
                    if let last = cues.last { progress(last.end - offset) }
                    if result.isFinal {
                        settled = true
                        cont.resume(returning: cues)
                    }
                    return
                }
                if let error {
                    settled = true
                    cont.resume(throwing: TranscribeError.recognitionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// 把音频的一小段导出为 m4a（分块识别用）。
    private static func exportAudioChunk(asset: AVAsset, range: CMTimeRange, to url: URL) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SubtitleTranscriberError.exportSessionUnavailable
        }
        exporter.timeRange = range
        exporter.shouldOptimizeForNetworkUse = true
        if #available(macOS 15.0, *) {
            try await exporter.export(to: url, as: .m4a)
        } else {
            exporter.outputURL = url
            exporter.outputFileType = .m4a
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    if let error = exporter.error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
    }

    /// SFTranscription 分段 → 字幕条；修掉最后一段 duration 缺失/过短的问题。
    private static func cues(from transcription: SFTranscription, offset: Double) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for segment in transcription.segments where !segment.substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let start = segment.timestamp + offset
            let end = start + max(segment.duration, 0.4)
            if var previous = cues.last {
                if start < previous.end {
                    previous.end = start
                    cues[cues.count - 1] = previous
                }
            }
            cues.append(SubtitleCue(start: start, end: end, text: segment.substring))
        }
        return cues
    }
}

private enum SubtitleTranscriberError: LocalizedError {
    case exportSessionUnavailable
    var errorDescription: String? { L("无法创建导出任务") }
}
