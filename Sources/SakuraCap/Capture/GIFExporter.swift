import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// GIF 导出尺寸（按最长边限制；原始则等比不缩放）。
enum GIFSize: Int, CaseIterable {
    case original, w1280, w960, w640

    var label: String {
        switch self {
        case .original: return L("原始尺寸")
        case .w1280: return L("宽 1280")
        case .w960: return L("宽 960")
        case .w640: return L("宽 640")
        }
    }

    var maxPixel: CGFloat? {
        switch self {
        case .original: return nil
        case .w1280: return 1280
        case .w960: return 960
        case .w640: return 640
        }
    }
}

/// 把视频的一段区间导出为动图 GIF（可选尺寸）。
enum GIFExporter {
    enum GIFError: LocalizedError {
        case createFailed
        case noFrames
        case finalizeFailed
        var errorDescription: String? {
            switch self {
            case .createFailed: return L("无法创建 GIF 文件")
            case .noFrames: return L("无法解码视频帧")
            case .finalizeFailed: return L("GIF 写入失败")
            }
        }
    }

    /// - fps：GIF 帧率，默认 12（越大越流畅也越大）
    static func export(source: URL,
                       timeRange: CMTimeRange,
                       size: GIFSize,
                       fps: Int = 12,
                       to outputURL: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        // 允许半帧误差，提升部分编码/可变帧率视频的解码成功率
        let tolerance = CMTime(value: 1, timescale: CMTimeScale(max(1, fps * 2)))
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        if let maxPixel = size.maxPixel {
            generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        }

        let duration = max(0, CMTimeGetSeconds(timeRange.duration))
        let frameCount = max(1, Int((duration * Double(fps)).rounded()))
        guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL,
                                                         UTType.gif.identifier as CFString,
                                                         frameCount, nil) else {
            throw GIFError.createFailed
        }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProps = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)],
        ] as CFDictionary

        let startSeconds = CMTimeGetSeconds(timeRange.start)
        var added = 0
        for i in 0..<frameCount {
            let seconds = startSeconds + Double(i) / Double(fps)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let decoded = try await generator.image(at: time).image
                guard let frame = normalize(decoded) else { continue }
                CGImageDestinationAddImage(dest, frame, frameProps)
                added += 1
            } catch {
                Log.app.error("GIF 取帧失败 t=\(seconds, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard added > 0 else { throw GIFError.noFrames }
        guard CGImageDestinationFinalize(dest) else { throw GIFError.finalizeFailed }
    }

    /// 统一转成 8 位 sRGB：GIF 不支持 10 位 / 宽色域，直接写入部分源会失败
    private static func normalize(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
