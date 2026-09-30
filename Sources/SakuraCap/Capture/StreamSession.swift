import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreImage

/// 一路输出的完整描述（一个 SCStream + 一个 FileWriter）
struct StreamSpec {
    let displayID: CGDirectDisplayID?      // 窗口模式为 nil（SCK 自动跨屏跟随）
    let filter: SCContentFilter
    let config: SCStreamConfiguration
    let fileURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let cropRect: CGRect?            // 全屏采集后的像素裁剪区域；区域录制使用
    let capturesSystemAudio: Bool
    let displayName: String
}

/// 单路 SCStream 会话：帧回调 → FileWriter 直通写入。
/// idle/不完整帧跳过；系统音频（若启用）走同一回调的 .audio 通道。
final class StreamSession: NSObject, SCStreamOutput {
    let spec: StreamSpec
    let writer: FileWriter

    private let stream: SCStream
    private let frameQueue: DispatchQueue
    private let cropContext = CIContext(options: [.cacheIntermediates: false])
    private var streamStarted = false
    private var loggedFirstFrame = false

    init(spec: StreamSpec, codec: AVVideoCodecType,
         quality: VideoQuality, frameRate: Int, customBitrateMbps: Double,
         systemAudio: Bool, micAudio: (sampleRate: Double, channels: Int)?) throws {
        self.spec = spec
        self.frameQueue = DispatchQueue(label: "com.sakura.sakuracap.frames", qos: .userInitiated)
        // 音轨必须在 writer.startWriting() 前确定并全部添加（懒建轨道会闪退）
        var audioTracks: [AudioTrackSetup] = []
        if systemAudio {
            audioTracks.append(AudioTrackSetup(kind: .system, sampleRate: 48000, channels: 2))
        }
        if let micAudio {
            audioTracks.append(AudioTrackSetup(kind: .microphone, sampleRate: micAudio.sampleRate, channels: micAudio.channels))
        }
        self.writer = try FileWriter(fileURL: spec.fileURL,
                                     pixelWidth: spec.pixelWidth,
                                     pixelHeight: spec.pixelHeight,
                                     codec: codec,
                                     quality: quality,
                                     frameRate: frameRate,
                                     customBitrateMbps: customBitrateMbps,
                                     audioTracks: audioTracks)
        self.stream = SCStream(filter: spec.filter, configuration: spec.config, delegate: nil)
        super.init()
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        if spec.capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: frameQueue)
        }
    }

    func start() async throws {
        try await stream.startCapture()
        streamStarted = true
        Log.capture.info("SCStream 已启动: \(self.spec.displayName, privacy: .public)")
    }

    /// 停流并收尾。discard=true 时直接删除半成品。
    func finish(discardFiles: Bool) async -> URL? {
        if streamStarted {
            try? await stream.stopCapture()
            streamStarted = false
        }
        return await writer.finish(discard: discardFiles)
    }

    /// 应用退出时的同步兜底
    func finishSyncBestEffort() -> URL? {
        writer.finishSyncBestEffort()
    }

    func armWriter() {
        writer.arm()
    }

    func pause() { writer.pause() }
    func resume() { writer.resume() }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard isCompleteFrame(sampleBuffer) else { return }
            if !loggedFirstFrame {
                loggedFirstFrame = true
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    Log.capture.info("首帧 \(CVPixelBufferGetWidth(pixelBuffer))×\(CVPixelBufferGetHeight(pixelBuffer))，期望 \(self.spec.pixelWidth)×\(self.spec.pixelHeight)（\(self.spec.displayName, privacy: .public)）")
                }
            }
            writer.appendVideo(croppedSampleBufferIfNeeded(sampleBuffer))
        case .audio:
            writer.appendAudio(sampleBuffer, track: .system)
        default:
            break
        }
    }

    /// 将整屏帧裁剪为选区帧，避免依赖 SCK sourceRect 的系统版本差异。
    private func croppedSampleBufferIfNeeded(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        guard let crop = spec.cropRect,
              let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return sampleBuffer
        }
        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)
        let top = max(0, min(sourceHeight - 2, Int(crop.minY.rounded(.down))))
        let left = max(0, min(sourceWidth - 2, Int(crop.minX.rounded(.down))))
        let width = max(2, min(sourceWidth - left, spec.pixelWidth)) & ~1
        let height = max(2, min(sourceHeight - top, spec.pixelHeight)) & ~1
        let image = CIImage(cvPixelBuffer: sourceBuffer)
        let y = CGFloat(sourceHeight - top - height)
        let cropRect = CGRect(x: CGFloat(left), y: y,
                              width: CGFloat(width), height: CGFloat(height))
        // 关键：CIContext.render(_:to:) 按图像自身坐标空间渲染。cropped(to:) 后图像 extent
        // 原点非 (0,0)，不平移回原点则整帧落在目标缓冲区之外，录出来全黑。
        let cropped = image.cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &output) == kCVReturnSuccess,
              let output else { return sampleBuffer }
        cropContext.render(cropped, to: output)
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                            imageBuffer: output,
                                                            formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return sampleBuffer }
        var timing = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: output,
                                                       formatDescription: formatDescription,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &result) == noErr,
              let result else { return sampleBuffer }
        return result
    }

    /// SCFrameStatus == .complete 才写入；idle 帧（画面无变化）跳过，避免重复编码
    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachmentsArray.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw) else { return false }
        return status == .complete
    }
}
