import AVFoundation
import CoreMedia
import os

enum AudioTrackKind: Hashable {
    case system
    case microphone
}

/// 预建音轨的格式描述。AVAssetWriter 要求所有输入必须在 startWriting() 之前 add，
/// 因此音频格式必须在创建 FileWriter 前确定（系统音=我们配置的 48k/2ch，麦克风=首样本实测）。
struct AudioTrackSetup {
    let kind: AudioTrackKind
    let sampleRate: Double
    let channels: Int
}

/// 单个输出文件的封装：AVAssetWriter + 视频轨（H.264/HEVC）+ 0..2 条 AAC 音频轨。
/// 所有调用线程安全（内部串行队列）。SCK 帧直通写入，不做任何像素转换。
final class FileWriter {
    private let queue = DispatchQueue(label: "com.sakura.sakuracap.writer", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private var audioInputs: [AudioTrackKind: AVAssetWriterInput] = [:]
    private var expectedAudioFormats: [AudioTrackKind: (sampleRate: Double, channels: Int)] = [:]
    private var warnedFormatMismatch = Set<AudioTrackKind>()
    private var warnedAppendFailure = false

    private let fileURL: URL
    private var started = false
    private var armed = false
    private var finished = false
    private var firstPTS: CMTime?
    private var lastPTS: CMTime?
    private var videoFrameCount = 0
    private var audioFrameCount = 0

    init(fileURL: URL, pixelWidth: Int, pixelHeight: Int, codec: AVVideoCodecType,
         quality: VideoQuality = .high, frameRate: Int = 30, customBitrateMbps: Double = 20,
         audioTracks: [AudioTrackSetup] = []) throws {
        self.fileURL = fileURL
        try? FileManager.default.removeItem(at: fileURL)
        writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: quality.bitrate(width: pixelWidth, height: pixelHeight,
                                                      fps: frameRate,
                                                      isHEVC: codec == AVVideoCodecType.hevc,
                                                      customMbps: customBitrateMbps),
            AVVideoExpectedSourceFrameRateKey: frameRate,
            // 屏幕内容大部分时间静止，长 GOP 显著提升画质；影响 seek 粒度，可接受
            AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
        ]
        if codec == AVVideoCodecType.h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        } // HEVC 交给 VideoToolbox 自动选择 profile/level

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: compression,
        ]
        // 色彩三元组必须显式标注（primaries/transfer/matrix），且是 videoSettings 的【顶层】键
        // （放进修 compression 字典里属于类型错误，曾导致编码会话内存损坏闪退）；
        // 缺失时播放器自行猜测 4:2:0 的范围与矩阵，表现为发灰发雾
        videoSettings[AVVideoColorPropertiesKey] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        // 音轨必须在 startWriting() 前全部 add（startWriting 后再 add 会抛 NSException 闪退）
        for setup in audioTracks {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: setup.sampleRate,
                AVNumberOfChannelsKey: setup.channels,
                AVEncoderBitRateKey: setup.channels >= 2 ? 160_000 : 96_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInputs[setup.kind] = input
            expectedAudioFormats[setup.kind] = (setup.sampleRate, setup.channels)
        }
        writer.startWriting()
    }

    /// 开始真正落盘（倒计时结束、正式开录时调用；之前的帧全部丢弃，保证倒计时不入视频）
    func arm() {
        queue.async { self.armed = true }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard self.armed, !self.finished, self.writer.status == .writing else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !self.started {
                self.writer.startSession(atSourceTime: pts)
                self.started = true
                self.firstPTS = pts
            }
            guard self.videoInput.isReadyForMoreMediaData else { return } // 过载丢帧，绝不阻塞采集
            // SCK 交付的 CMSampleBuffer（内含 CVPixelBuffer）直通写入，零转换
            if self.videoInput.append(sampleBuffer) {
                self.videoFrameCount += 1
                if self.lastPTS == nil || CMTimeCompare(pts, self.lastPTS!) > 0 { self.lastPTS = pts }
            } else if !self.warnedAppendFailure {
                // append 失败后 writer 进入 failed 状态；记录编码器给出的具体错误
                self.warnedAppendFailure = true
                Log.writer.error("视频帧写入失败: \(self.writer.error?.localizedDescription ?? "未知错误", privacy: .public)")
            }
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer, track: AudioTrackKind) {
        queue.async {
            guard self.armed, !self.finished, self.writer.status == .writing else { return }
            guard let input = self.audioInputs[track] else { return } // 未启用的轨道直接丢弃
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !self.started {
                self.writer.startSession(atSourceTime: pts)
                self.started = true
                self.firstPTS = pts
            } else if CMTimeCompare(pts, self.firstPTS!) < 0 {
                return // 会话起点之前的样本丢弃（最多零点几秒）
            }
            // 格式与建轨时不符则丢弃（避免编码器报错；正常不应发生）
            if let expected = self.expectedAudioFormats[track] {
                let matches: Bool = {
                    guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
                          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return false }
                    return abs(asbd.mSampleRate - expected.sampleRate) < 1
                        && Int(asbd.mChannelsPerFrame) == expected.channels
                }()
                if !matches {
                    if !self.warnedFormatMismatch.contains(track) {
                        self.warnedFormatMismatch.insert(track)
                        Log.writer.error("音频格式与预建轨道不符，丢弃（track=\(String(describing: track), privacy: .public)）")
                    }
                    return
                }
            }
            guard input.isReadyForMoreMediaData else { return }
            if input.append(sampleBuffer) {
                self.audioFrameCount += 1
                if self.lastPTS == nil || CMTimeCompare(pts, self.lastPTS!) > 0 { self.lastPTS = pts }
            }
        }
    }

    /// 停止并落盘。未写入任何帧时返回 nil 并删除半成品文件。
    func finish(discard: Bool) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.finalizeOnQueue(discard: discard) { url in
                    continuation.resume(returning: url)
                }
            }
        }
    }

    /// 应用即将退出时的同步尽力收尾（最多等 2 秒）
    func finishSyncBestEffort() -> URL? {
        var canFinalize = false
        queue.sync {
            guard !finished else { return }
            finished = true
            armed = false
            for input in audioInputs.values { input.markAsFinished() }
            videoInput.markAsFinished()
            if started, let last = lastPTS { writer.endSession(atSourceTime: last) }
            canFinalize = true
        }
        guard canFinalize else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var result: URL?
        writer.finishWriting { [weak self] in
            guard let self, self.writer.status == .completed, self.videoFrameCount > 0 else {
                semaphore.signal()
                return
            }
            result = self.fileURL
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 2) == .timedOut { return nil }
        return result
    }

    private func finalizeOnQueue(discard: Bool, completion: @escaping (URL?) -> Void) {
        guard !finished else { completion(nil); return }
        finished = true
        armed = false
        for input in audioInputs.values { input.markAsFinished() }
        videoInput.markAsFinished()
        if discard {
            try? FileManager.default.removeItem(at: fileURL)
            completion(nil)
            return
        }
        if started, let last = lastPTS { writer.endSession(atSourceTime: last) }
        writer.finishWriting { [weak self] in
            guard let self, self.writer.status == .completed, self.videoFrameCount > 0 else {
                Log.writer.error("落盘失败: status=\(self?.writer.status.rawValue ?? -1), videoFrames=\(self?.videoFrameCount ?? 0), error=\(self?.writer.error?.localizedDescription ?? "-")")
                try? FileManager.default.removeItem(at: self?.fileURL ?? URL(fileURLWithPath: "/dev/null"))
                completion(nil)
                return
            }
            completion(self.fileURL)
        }
    }
}
