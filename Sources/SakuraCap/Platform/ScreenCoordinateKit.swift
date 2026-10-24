import AppKit
import CoreGraphics

extension NSScreen {
    /// 该屏对应的 CGDirectDisplayID
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// 「点→像素」换算的唯一入口。
/// 关键陷阱：SCDisplay.width/height 与 CGDisplayPixelsWide/High 在现代 macOS 上
/// 返回的都是逻辑点（Retina 屏上恰好等于 frame 宽高），拿它们当像素会把 HiDPI 屏
/// 按 1x 采集，录屏整体发糊；只有 CGDisplayMode 的 pixelWidth/pixelHeight 是
/// 该屏真实的采样像素（HiDPI 缩放模式下即合成器实际渲染的缓冲尺寸）。
enum DisplayPixelMetrics {
    static func size(_ displayID: CGDirectDisplayID) -> (width: Int, height: Int) {
        if let mode = CGDisplayCopyDisplayMode(displayID),
           mode.pixelWidth > 0, mode.pixelHeight > 0 {
            return (mode.pixelWidth, mode.pixelHeight)
        }
        return (CGDisplayPixelsWide(displayID), CGDisplayPixelsHigh(displayID))
    }

    static func scale(_ displayID: CGDirectDisplayID) -> (x: CGFloat, y: CGFloat) {
        if let mode = CGDisplayCopyDisplayMode(displayID),
           mode.width > 0, mode.height > 0, mode.pixelWidth > 0, mode.pixelHeight > 0 {
            return (CGFloat(mode.pixelWidth) / CGFloat(mode.width),
                    CGFloat(mode.pixelHeight) / CGFloat(mode.height))
        }
        let s = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
        return (s, s)
    }
}

/// 四套坐标系换算的唯一入口（AppKit / CG 全局 / SCK / 像素）。
/// 纯函数，便于单元测试；任何散落的坐标运算都应收拢到这里。
enum ScreenCoordinate {
    /// 主屏（原点所在屏）的高度，用于 AppKit ↔ CG 翻转
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// CG 全局点（左上原点）→ AppKit 全局点（左下原点）
    static func appKitPoint(fromCG point: CGPoint) -> CGPoint {
        appKitPoint(fromCG: point, primaryHeight: primaryScreenHeight)
    }

    /// 纯函数版本（便于单测）：给定主屏高度做翻转
    static func appKitPoint(fromCG point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// NSScreen 的 frame（AppKit 坐标）转 CG 全局 frame（左上原点）
    static func cgFrame(of screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryScreenHeight - f.maxY, width: f.width, height: f.height)
    }

    /// CG 全局点落在哪块屏上（多屏、副屏负坐标均正确）
    static func screen(containingCGPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { cgFrame(of: $0).contains(point) } ?? NSScreen.screens.first
    }

    /// 某屏本地 AppKit 矩形（该屏左下原点，pt）→ SCK sourceRect（该屏左上原点，pt）
    static func sckSourceRect(fromAppKitLocalRect rect: CGRect, in screen: NSScreen) -> CGRect {
        sckSourceRect(fromAppKitLocalRect: rect, screenHeight: screen.frame.height)
    }

    /// 纯函数版本（便于单测）：给定该屏高度做翻转
    static func sckSourceRect(fromAppKitLocalRect rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: screenHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// 某屏本地 SCK 矩形（该屏左上原点，pt）→ 该屏本地 AppKit 矩形（左下原点，pt）
    static func appKitLocalRect(fromSCKRect rect: CGRect, in screen: NSScreen) -> CGRect {
        appKitLocalRect(fromSCKRect: rect, screenHeight: screen.frame.height)
    }

    /// 纯函数版本（便于单测）：给定该屏高度做翻转，与 sckSourceRect 互逆
    static func appKitLocalRect(fromSCKRect rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: screenHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// CG 全局矩形（左上原点）→ 某屏本地 AppKit 矩形（左下原点），超出该屏的部分被裁掉；无交集返回 nil
    static func appKitLocalRect(fromCGRect cgRect: CGRect, in screen: NSScreen) -> CGRect? {
        let screenCG = cgFrame(of: screen)
        let clipped = cgRect.intersection(screenCG)
        guard !clipped.isEmpty, !clipped.isNull else { return nil }
        let localX = clipped.minX - screenCG.minX
        let localTop = clipped.minY - screenCG.minY
        return CGRect(x: localX,
                      y: screen.frame.height - localTop - clipped.height,
                      width: clipped.width,
                      height: clipped.height)
    }
}
