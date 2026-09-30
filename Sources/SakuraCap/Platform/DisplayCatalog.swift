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
        for display in content.displays {
            let screen = NSScreen.screens.first { $0.displayID == display.displayID }
            let scale = screen?.backingScaleFactor ?? 2
            let info = DisplayInfo(id: display.displayID,
                                   name: screen?.localizedName ?? (L("显示器") + " \(display.displayID)"),
                                   widthPx: display.width,
                                   heightPx: display.height,
                                   widthPt: CGFloat(display.width) / scale,
                                   heightPt: CGFloat(display.height) / scale,
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
