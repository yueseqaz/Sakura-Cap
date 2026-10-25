import AppKit
import ScreenCaptureKit

/// SCShareableContent 与 NSScreen 的关联目录（显示器部分）。
/// 每次开始录制前、面板出现时刷新，天然支持热插拔。
@MainActor
final class DisplayCatalog: ObservableObject {
    static let shared = DisplayCatalog()

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var isLoading = false

    private var scDisplays: [CGDirectDisplayID: SCDisplay] = [:]

    func scDisplay(for id: CGDirectDisplayID) -> SCDisplay? { scDisplays[id] }

    @discardableResult
    func refresh() async throws -> [DisplayInfo] {
        isLoading = true
        defer { isLoading = false }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        var infos: [DisplayInfo] = []
        var displayMap: [CGDirectDisplayID: SCDisplay] = [:]
        for (index, display) in content.displays.enumerated() {
            let screen = NSScreen.screens.first { $0.displayID == display.displayID }
            let scale = screen?.backingScaleFactor ?? 2
            // SCDisplay.width/height 是逻辑点；录制缓冲与分辨率展示都需要真实像素
            let pixels = DisplayPixelMetrics.size(display.displayID)
            // 部分外接屏 localizedName 返回空串（EDID 无名，非 nil），
            // 空串兜底到序号名，否则并行录制的文件名会出现 "… - .mp4" 空后缀
            let localName = screen?.localizedName ?? ""
            let info = DisplayInfo(id: display.displayID,
                                   name: localName.isEmpty ? String(format: L("显示器 %d"), index + 1) : localName,
                                   widthPx: pixels.width,
                                   heightPx: pixels.height,
                                   widthPt: CGFloat(display.width),
                                   heightPt: CGFloat(display.height),
                                   scaleFactor: scale,
                                   isMain: CGDisplayIsMain(display.displayID) != 0)
            infos.append(info)
            displayMap[display.displayID] = display
        }

        displays = infos
        scDisplays = displayMap
        return infos
    }
}
