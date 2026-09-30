import AppKit

/// 当前录制目标在 AppKit 全局坐标里的区域：
/// 全屏模式取所选屏幕整块；区域模式取选区矩形。按键显示、画中画等覆盖层据此定位。
enum RecordingTarget {
    static func rect() -> NSRect? {
        let settings = AppSettings.shared
        if settings.captureMode == .region, let region = settings.lastRegion,
           let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }) {
            let local = ScreenCoordinate.appKitLocalRect(fromSCKRect: region.sckRect, in: screen)
            return NSRect(x: screen.frame.minX + local.minX,
                          y: screen.frame.minY + local.minY,
                          width: local.width,
                          height: local.height)
        }
        let screen = NSScreen.screens.first { $0.displayID == settings.selectedDisplayID }
            ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.frame
    }
}
