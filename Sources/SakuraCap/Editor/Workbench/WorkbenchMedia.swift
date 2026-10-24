import AVFoundation
import AppKit

/// 音轨元信息（trackID + 展示名），构建混音与音轨 UI 时使用
struct WorkbenchAudioTrack: Identifiable, Equatable {
    let id: CMPersistentTrackID
    let title: String
}

/// 源媒体的展示素材缓存：整源缩略图条 + 每条音轨的波形峰值。
/// 全部按【源时间】生成一次，片段块按自己的源区间切片显示，缩放时重排不重生成。
@MainActor
final class WorkbenchMedia {
    let asset: AVURLAsset
    let duration: Double
    let videoSize: CGSize
    let videoAspect: CGFloat
    let audioTracks: [WorkbenchAudioTrack]

    /// 缩略图/波形成片后的回调（ViewModel 借此触发 UI 刷新）
    var onChange: (() -> Void)?

    /// 缩略图：均匀覆盖整个源，thumbnailInterval = 每张覆盖的源秒数
    private(set) var thumbnails: [CGImage] = [] {
        didSet { onChange?() }
    }
    private(set) var thumbnailInterval: Double = 1

    /// 波形峰值：每条音轨一组，bucket = waveformBucket 秒/个，值域 0...1
    nonisolated static let waveformBucket: Double = 1.0 / 20.0
    private(set) var waveforms: [CMPersistentTrackID: [Float]] = [:] {
        didSet { onChange?() }
    }

    init(asset: AVURLAsset, duration: Double, videoSize: CGSize,
         videoAspect: CGFloat, audioTracks: [WorkbenchAudioTrack]) {
        self.asset = asset
        self.duration = duration
        self.videoSize = videoSize
        self.videoAspect = videoAspect
        self.audioTracks = audioTracks
    }

    // MARK: 缩略图（渐进生成，边生成边上屏）

    func generateThumbnails() async {
        guard duration > 0 else { return }
        let count = min(240, max(12, Int(duration / 3)))
        thumbnailInterval = duration / Double(count)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 135)
        generator.requestedTimeToleranceBefore = CMTime(seconds: thumbnailInterval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: thumbnailInterval / 2, preferredTimescale: 600)
        var images: [CGImage] = []
        for index in 0..<count {
            if Task.isCancelled { return }
            let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image {
                images.append(frame)
            } else {
                images.append(Self.placeholder())
            }
            if images.count % 8 == 0 || index == count - 1 {
                thumbnails = images
            }
        }
        thumbnails = images
    }

    private static func placeholder() -> CGImage {
        let width = 4, height = 4
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    // MARK: 波形（后台解码，每轨一次）

    func generateWaveforms() async {
        for track in audioTracks {
            if Task.isCancelled { return }
            let peaks = await Self.readPeaks(asset: asset, trackID: track.id)
            waveforms[track.id] = peaks
        }
    }

    private nonisolated static func readPeaks(asset: AVAsset, trackID: CMPersistentTrackID) async -> [Float] {
        await Task.detached(priority: .userInitiated) { () -> [Float] in
            guard let track = try? await asset.loadTrack(withTrackID: trackID),
                  let reader = try? AVAssetReader(asset: asset),
                  let output = try? AVAssetReaderTrackOutput(track: track, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                  ]) else { return [] }
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { return [] }

            var peaks: [Float] = []
            var acc: Float = 0
            var count = 0
            // 首个 buffer 读到真实采样率后确定每桶样本数；之前按 48k 估算
            var samplesPerBucket = max(1, Int(48000 * WorkbenchMedia.waveformBucket))
            while let sample = output.copyNextSampleBuffer() {
                if count == 0, peaks.isEmpty, acc == 0,
                   let desc = CMSampleBufferGetFormatDescription(sample),
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    samplesPerBucket = max(1, Int(asbd.mSampleRate * WorkbenchMedia.waveformBucket))
                }
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                if length <= 0 { continue }
                var data = [Int16](repeating: 0, count: length / 2)
                let status = data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { continue }
                for value in data {
                    let v = abs(Float(value)) / 32768
                    if v > acc { acc = v }
                    count += 1
                    if count >= samplesPerBucket {
                        peaks.append(acc)
                        acc = 0
                        count = 0
                    }
                }
            }
            if count > 0 { peaks.append(acc) }
            let normalize = max(0.001, peaks.max() ?? 1)
            return peaks.map { min(1, $0 / normalize) }
        }.value
    }
}
