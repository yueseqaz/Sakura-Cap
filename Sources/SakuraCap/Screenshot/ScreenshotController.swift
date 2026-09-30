import AppKit
import ScreenCaptureKit

/// 单帧截图（复用屏幕录制权限）：全屏或框选区域。
/// - 截图 → 打开标注编辑器
/// - OCR → 识别文字并复制到剪贴板
@MainActor
final class ScreenshotController {
    static let shared = ScreenshotController()

    private enum ScreenshotError: LocalizedError {
        case unsupported
        case displayMissing
        var errorDescription: String? {
            switch self {
            case .unsupported: return L("截图需要 macOS 14 或更高版本")
            case .displayMissing: return L("找不到该显示器")
            }
        }
    }

    func captureDisplay(_ id: CGDirectDisplayID) {
        Task { await openEditor(displayID: id, region: nil) }
    }

    func captureRegion(_ region: RegionSelection) {
        Task { await openEditor(displayID: region.displayID, region: region) }
    }

    func ocrDisplay(_ id: CGDirectDisplayID) {
        Task { await recognize(displayID: id, region: nil) }
    }

    func ocrRegion(_ region: RegionSelection) {
        Task { await recognize(displayID: region.displayID, region: region) }
    }

    private func openEditor(displayID: CGDirectDisplayID, region: RegionSelection?) async {
        guard #available(macOS 14.0, *) else { showError(ScreenshotError.unsupported); return }
        do {
            let image = try await captureImage(displayID: displayID, region: region)
            let name = "SakuraCap \(StreamPlanner.timestamp()).png"
            AnnotationEditorController.shared.open(image: image, suggestedName: name)
        } catch {
            showError(error)
        }
    }

    private func recognize(displayID: CGDirectDisplayID, region: RegionSelection?) async {
        guard #available(macOS 14.0, *) else { showError(ScreenshotError.unsupported); return }
        do {
            let image = try await captureImage(displayID: displayID, region: region)
            guard let text = await OCR.recognize(image) else {
                showMessage(L("未识别到文字"))
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            CompletionNotifier.shared.postCopiedText(count: text.count)
            let preview = text.count > 15 ? String(text.prefix(15)) + "…" : text
            Toast.show(title: L("识别成功，已复制到剪贴板"), detail: preview)
        } catch {
            showError(error)
        }
    }

    @available(macOS 14.0, *)
    func captureImage(displayID: CGDirectDisplayID, region: RegionSelection?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotError.displayMissing
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        if let region {
            let rect = CGRect(x: region.sckRect.minX * scale,
                              y: region.sckRect.minY * scale,
                              width: region.sckRect.width * scale,
                              height: region.sckRect.height * scale).integral
            if let cropped = image.cropping(to: rect) { image = cropped }
        }
        return image
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("截图失败")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L("好"))
        runModalAlert(alert)
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: L("好"))
        runModalAlert(alert)
    }
}
