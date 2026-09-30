import Foundation
import CoreGraphics
import ScreenCaptureKit

/// 面板展示用的显示器信息（SCK 侧与 AppKit 侧按 CGDirectDisplayID 关联）
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let widthPx: Int
    let heightPx: Int
    let widthPt: CGFloat
    let heightPt: CGFloat
    let scaleFactor: CGFloat
    let isMain: Bool

    var resolutionText: String { "\(widthPx)×\(heightPx)" }
    var scaleText: String { scaleFactor > 1 ? "Retina \(Int(scaleFactor))x" : "1x" }
}
