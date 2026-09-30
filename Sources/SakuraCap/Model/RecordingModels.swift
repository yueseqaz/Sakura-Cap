import Foundation
import CoreGraphics
import AVFoundation

// MARK: - 录制配置模型

enum CaptureMode: String, CaseIterable, Identifiable {
    case display
    case region

    var id: String { rawValue }
    var label: String {
        switch self {
        case .display: return "屏幕"
        case .region: return "区域"
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }
    var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        }
    }
    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

enum FPSOption: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue) fps" }
}

/// 色彩空间选项（BGRA 直采时必须显式指定，否则录出全黑）
enum ColorSpaceOption: String, CaseIterable, Identifiable {
    case sRGB
    case displayP3

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sRGB: return "sRGB"
        case .displayP3: return "Display P3（广色域屏）"
        }
    }
}

/// 画质档位：码率 = 像素数 × 帧率 × bpp。
/// 屏幕录制优先保留文字边缘：高(0.35/0.22)/中(0.20/0.13)/低(0.12/0.08)，分别对应 H.264/HEVC。
enum VideoQuality: String, CaseIterable, Identifiable {
    case high
    case medium
    case low
    case custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .high: return "高（文字锐利，文件大）"
        case .medium: return "中（平衡）"
        case .low: return "低（文件小）"
        case .custom: return "自定义码率"
        }
    }

    func bitrate(width: Int, height: Int, fps: Int, isHEVC: Bool, customMbps: Double = 20) -> Int {
        if self == .custom {
            return Int(max(2, customMbps) * 1_000_000)
        }
        let bpp: Double
        switch self {
        case .high:
            // 系统录屏级别的码率，优先保留文字、细线和浏览器图片细节。
            bpp = isHEVC ? 0.22 : 0.35
        case .medium:
            bpp = isHEVC ? 0.13 : 0.20
        case .low:
            bpp = isHEVC ? 0.08 : 0.12
        case .custom:
            bpp = 0
        }
        // 60fps 相对 30fps 的码率收益边际递减，按 1.5× 权重（45fps 等效）
        let effectiveFps = fps <= 30 ? Double(fps) : Double(fps) * 0.75
        return Int(min(150_000_000, max(4_000_000, Double(width * height) * effectiveFps * bpp)))
    }
}

/// 输出分辨率：录制范围不变，按需缩小输出尺寸（不放大）。
enum OutputResolution: String, CaseIterable, Identifiable {
    case native
    case p1080
    case p720

    var id: String { rawValue }
    var label: String {
        switch self {
        case .native: return "原始"
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }
    /// 等比缩放的包围盒（宽 × 高）；nil = 保持原始
    var box: (width: Int, height: Int)? {
        switch self {
        case .native: return nil
        case .p1080: return (1920, 1080)
        case .p720: return (1280, 720)
        }
    }
}

/// 画中画位置（录制区域的四角）
enum PiPCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }
    var label: String {
        switch self {
        case .topLeft: return "左上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        case .bottomRight: return "右下"
        }
    }
}

/// 自定义区域：SCK 坐标（该屏左上原点、单位 pt）+ 所在显示器
struct RegionSelection: Codable, Equatable {
    let displayID: CGDirectDisplayID
    let sckRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
}

// MARK: - 错误

enum RecordingError: LocalizedError {
    case noDisplays
    case noRegion
    case displayMissing
    case noMicrophone
    case microphoneInit(String)
    case noOutputDirectory
    case noSpecs

    var errorDescription: String? {
        switch self {
        case .noDisplays: return "没有可录制的显示器"
        case .noRegion: return "请先框选录制区域"
        case .displayMissing: return "录制区域所在的显示器已不存在，请重新框选"
        case .noMicrophone: return "未找到可用的麦克风设备"
        case .microphoneInit(let reason): return "麦克风初始化失败：\(reason)"
        case .noOutputDirectory: return "未选择输出目录"
        case .noSpecs: return "未能生成任何录制任务"
        }
    }
}
