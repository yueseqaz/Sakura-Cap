import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreVideo

/// 由设置 + 当前可采集内容，生成一或多个 StreamSpec：
/// 单屏 / 全部屏幕并行 / 自定义区域（不跨屏）。
///
/// 坐标与缩放约定（画质专项）：
/// - sourceRect 与缓冲尺寸一律以「物理像素」表达：点值 × 过滤器自带的 pointPixelScale
///   （macOS 14+，反映该过滤器真实的点→像素缩放；旧系统回退该屏 backingScaleFactor）
/// - 每路流独立换算，多屏混合 DPI 互不影响
/// - 输出分辨率 = 捕获分辨率，1:1 无中间缩放；宽高强制偶数（4:2:0 编码要求）
@MainActor
enum StreamPlanner {
    static func buildSpecs(settings: AppSettings, catalog: DisplayCatalog) throws -> [StreamSpec] {
        guard let directory = settings.outputDirectory else { throw RecordingError.noOutputDirectory }
        let stamp = timestamp()
        var specs: [StreamSpec] = []

        switch settings.captureMode {
        case .display:
            let chosen: [DisplayInfo]
            if settings.allDisplaysParallel {
                chosen = catalog.displays
                guard !chosen.isEmpty else { throw RecordingError.noDisplays }
            } else {
                guard let info = catalog.displays.first(where: { $0.id == settings.selectedDisplayID }) ?? catalog.displays.first else {
                    throw RecordingError.noDisplays
                }
                chosen = [info]
            }
            for info in chosen {
                guard let display = catalog.scDisplay(for: info.id) else { continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let (w, h) = pixelSize(filter: filter, fallback: (info.widthPx, info.heightPx))
                // 全屏过滤器已经限定了显示器范围；不传 sourceRect，避免不同 macOS 版本
                // 对 sourceRect 单位（pt/px）解释不一致，导致 Retina 画面被二次缩放。
                let source = CGRect.zero
                // 并行模式下系统音频只写进主屏文件，避免 N 份重复音轨
                let capturesAudio = settings.recordSystemAudio && (chosen.count == 1 || info.isMain)
                let suffix = chosen.count > 1 ? " - \(sanitized(info.name))" : ""
                specs.append(StreamSpec(displayID: info.id,
                                        filter: filter,
                                        config: baseConfig(settings: settings, width: w, height: h, source: source),
                                        fileURL: fileURL(in: directory, stamp: stamp, suffix: suffix),
                                        pixelWidth: w,
                                        pixelHeight: h,
                                        cropRect: nil,
                                        capturesSystemAudio: capturesAudio,
                                        displayName: info.name))
            }
        case .region:
            guard let region = settings.lastRegion else { throw RecordingError.noRegion }
            guard let info = catalog.displays.first(where: { $0.id == region.displayID }),
                  let display = catalog.scDisplay(for: region.displayID) else {
                throw RecordingError.displayMissing
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            // 用过滤器真实的「像素/点」比例换算选区；缩放分辨率下 backingScaleFactor
            // 未必等于真实比例，直接用它会造成尺寸/位置偏差。
            let scale = pointScale(filter: filter, fallback: info.scaleFactor)
            let (w, h) = evenDimensions(Int((region.sckRect.width * scale).rounded()),
                                        Int((region.sckRect.height * scale).rounded()))
            let crop = CGRect(x: region.sckRect.minX * scale,
                              y: region.sckRect.minY * scale,
                              width: CGFloat(w),
                              height: CGFloat(h))
            // 先采集整屏（原生像素），再在 StreamSession 中按像素裁剪（1:1，无缩放），保证清晰度。
            let (fullWidth, fullHeight) = pixelSize(filter: filter, fallback: (info.widthPx, info.heightPx))
            specs.append(StreamSpec(displayID: region.displayID,
                                    filter: filter,
                                    config: baseConfig(settings: settings, width: fullWidth, height: fullHeight, source: .zero),
                                    fileURL: fileURL(in: directory, stamp: stamp, suffix: " - 区域"),
                                    pixelWidth: w,
                                    pixelHeight: h,
                                    cropRect: crop,
                                    capturesSystemAudio: settings.recordSystemAudio,
                                    displayName: "区域"))
        }

        guard !specs.isEmpty else { throw RecordingError.noSpecs }
        return specs
    }

    private static func pointScale(filter: SCContentFilter, fallback: CGFloat) -> CGFloat {
        if #available(macOS 14.0, *) {
            let scale = CGFloat(filter.pointPixelScale)
            if scale > 0 { return scale }
        }
        return fallback > 0 ? fallback : 2
    }

    /// 该过滤器内容的真实像素尺寸（点 × 像素/点），保证与采样缓冲区一致。
    private static func pixelSize(filter: SCContentFilter, fallback: (Int, Int)) -> (Int, Int) {
        if #available(macOS 14.0, *) {
            let rect = filter.contentRect
            let scale = CGFloat(filter.pointPixelScale)
            if rect.width > 0, rect.height > 0, scale > 0 {
                return evenDimensions(Int((rect.width * scale).rounded()),
                                      Int((rect.height * scale).rounded()))
            }
        }
        return evenDimensions(fallback.0, fallback.1)
    }

    /// 4:2:0 编码要求宽高为偶数
    private static func evenDimensions(_ w: Int, _ h: Int) -> (Int, Int) {
        (max(2, w & ~1), max(2, h & ~1))
    }

    private static func baseConfig(settings: AppSettings, width: Int, height: Int, source: CGRect) -> SCStreamConfiguration {
        var config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.sourceRect = source
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, settings.fps.rawValue)))
        config.queueDepth = 6
        config.showsCursor = settings.showCursor
        if #available(macOS 14.0, *) {
            // BGRA 全范围 RGB 直采；实测不显式指定色彩空间会录出全黑
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = settings.colorSpace == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB
            // 关键：默认 .automatic 会按「逻辑点」分辨率采样再放大到 width/height，
            // Retina 下必然模糊。.best 让 SCK 以显示器原生像素分辨率采样。
            config.captureResolution = .best
        }
        return config
    }

    private static func fileURL(in directory: URL, stamp: String, suffix: String) -> URL {
        directory.appendingPathComponent("SakuraCap \(stamp)\(suffix).mp4")
    }

    private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}
