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

    func qrRegion(_ region: RegionSelection) {
        Task { await recognizeCode(displayID: region.displayID, region: region) }
    }

    func compareRegion(_ region: RegionSelection) {
        Task {
            guard #available(macOS 14.0, *) else { return }
            if let image = try? await captureImage(displayID: region.displayID, region: region) {
                CompareController.shared.deliver(image)
            }
        }
    }

    func translateRegion(_ region: RegionSelection) {
        Task { await translate(displayID: region.displayID, region: region) }
    }

    private func translate(displayID: CGDirectDisplayID, region: RegionSelection?) async {
        guard #available(macOS 14.0, *) else { showError(ScreenshotError.unsupported); return }
        do {
            let image = try await captureImage(displayID: displayID, region: region)
            guard let original = await OCR.recognize(image) else {
                showMessage(L("未识别到文字"))
                return
            }
            let model = TranslationPresenter.shared.present(original: original)
            model.isLoading = true
            do {
                model.translation = try await TranslationService.translate(original, config: AppSettings.shared.translationConfig)
                model.isLoading = false
            } catch {
                model.error = error.localizedDescription
                model.isLoading = false
            }
        } catch {
            showError(error)
        }
    }

    private func openEditor(displayID: CGDirectDisplayID, region: RegionSelection?) async {
        guard #available(macOS 14.0, *) else { showError(ScreenshotError.unsupported); return }
        do {
            let image = try await captureImage(displayID: displayID, region: region)
            let name = FileName.make(ext: "png")
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

    private func recognizeCode(displayID: CGDirectDisplayID, region: RegionSelection?) async {
        guard #available(macOS 14.0, *) else { showError(ScreenshotError.unsupported); return }
        do {
            let image = try await captureImage(displayID: displayID, region: region)
            let codes = await Barcode.detect(image)
            guard !codes.isEmpty else {
                showMessage(L("未识别到二维码 / 条形码"))
                return
            }
            let text = codes.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            CompletionNotifier.shared.postCopiedText(count: text.count)

            // 单个 http(s) 链接时，toast 末尾给一个「打开」按钮
            let link = codes.compactMap { Self.webURL(from: $0) }.first
            Log.app.notice("二维码识别: count=\(codes.count, privacy: .public) link=\(link?.absoluteString ?? "nil", privacy: .public)")
            if let link {
                Toast.show(title: L("识别成功，已复制到剪贴板"), detail: codes[0], actionTitle: L("打开")) {
                    NSWorkspace.shared.open(link)
                }
            } else {
                Toast.show(title: L("识别成功，已复制到剪贴板"), detail: codes[0])
            }
        } catch {
            showError(error)
        }
    }

    /// 从二维码内容里解析出可打开的 http(s) 链接（容忍首尾空白 / 缺 scheme）
    private static func webURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        let host = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        if host.contains("."), let url = URL(string: "https://" + trimmed), url.host != nil {
            return url
        }
        return nil
    }

    @available(macOS 14.0, *)
    func captureImage(displayID: CGDirectDisplayID, region: RegionSelection?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotError.displayMissing
        }
        if let region, let image = Self.nativeDisplayImage(displayID: displayID, region: region) {
            Log.app.debug("区域截图原生像素: \(image.width)x\(image.height, privacy: .public)")
            return image
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        if let region {
            // Capture the same local point rect used by the selection overlay.
            // Keeping the crop in ScreenCaptureKit's coordinate space avoids
            // the global/local origin mismatch that caused region drift.
            config.sourceRect = region.sckRect
            config.width = max(2, region.pixelWidth)
            config.height = max(2, region.pixelHeight)
        } else {
            config.width = Int((filter.contentRect.width * scale).rounded())
            config.height = Int((filter.contentRect.height * scale).rounded())
        }
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func nativeDisplayImage(displayID: CGDirectDisplayID,
                                           region: RegionSelection) -> CGImage? {
        guard region.sckRect.width > 0, region.sckRect.height > 0 else { return nil }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { return nil }
        let scaleX = CGFloat(CGDisplayPixelsWide(displayID)) / max(screen.frame.width, 1)
        let scaleY = CGFloat(CGDisplayPixelsHigh(displayID)) / max(screen.frame.height, 1)
        guard scaleX > 0, scaleY > 0 else { return nil }
        let rect = CGRect(x: region.sckRect.minX * scaleX,
                          y: region.sckRect.minY * scaleY,
                          width: region.sckRect.width * scaleX,
                          height: region.sckRect.height * scaleY).integral
        return CGDisplayCreateImage(displayID, rect: rect)
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
