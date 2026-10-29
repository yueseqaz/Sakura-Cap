// Compiled with the production tool sources by verify_tools.sh; no XCTest required.
import AppKit
import ImageIO
import Darwin

func L(_ key: String) -> String {
    guard ProcessInfo.processInfo.environment["SAKURA_TEST_LANGUAGE"] == "en",
          let bundle = Bundle(path: "Resources/en.lproj") else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

@MainActor
enum Toast {
    static func show(title: String, detail: String?) {}
    static func show(title: String, detail: String?, actionTitle: String, action: @escaping () -> Void) {}
}

@main
@MainActor
enum ToolRegressionChecks {
    private static var checks = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await verifyConversionWindow()
                try await verifyImageEncoding()
                verifyPickerCoordinates()
                verifyColorSampling()
                let result = "Tool regressions passed: \(checks) assertions (\(ProcessInfo.processInfo.environment["SAKURA_TEST_LANGUAGE"] ?? "zh"))"
                if let completion = ProcessInfo.processInfo.environment["SAKURA_TEST_COMPLETION_FILE"] {
                    try result.write(toFile: completion, atomically: true, encoding: .utf8)
                }
                print(result)
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Tool regression failed: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        // ImageIO's hardware codecs run nested CF run loops; use a real AppKit loop,
        // not async-main's drain queue, which can exit early before tests finish.
        app.run()
        preconditionFailure("AppKit run loop exited before regression checks completed")
    }

    private static func verifyConversionWindow() async throws {
        let tool = ImageConvertToolController.shared
        tool.show()
        let window = NSApp.windows.first { $0.title == L("图片格式转换") }!
        defer { window.orderOut(nil) }
        let container = window.contentView!
        let views = descendants(of: container)
        let bar = container.subviews.compactMap { $0 as? NSVisualEffectView }.first!
        let format = views.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("JPEG") }!
        let convert = views.compactMap { $0 as? NSButton }.first { $0.title == L("转换") }!
        let remove = views.compactMap { $0 as? NSButton }.first { $0.title == L("移除所选") }!
        let table = views.compactMap { $0 as? NSTableView }.first!
        let drop = views.compactMap { $0 as? ImageConvertDropView }.first!
        check(window.isVisible && window.frame.width >= 640, "Conversion window must not collapse to zero width")
        check(window.level == .normal && !window.collectionBehavior.contains(.canJoinAllSpaces), "Conversion must behave as a normal document, not a desktop overlay")
        check(!bar.translatesAutoresizingMaskIntoConstraints, "Toolbar must use Auto Layout")
        check(!convert.isEnabled, "Empty conversion list must disable Convert")
        check(format.itemTitles == ["None"] + ImageOutputFormat.available.map(\.title), "Offer every supported output format, but no unsupported encoders")
        check(format.numberOfItems >= 7, "Common TIFF, BMP, GIF, and JPEG 2000 formats must be offered")
        check(format.itemTitles.contains("WebP"), "Bundled WebP encoder must always be available, even without ImageIO encoding support")
        check(format.titleOfSelectedItem == "None", "Default output format must preserve the source format")
        check(views.compactMap { $0 as? NSPopUpButton }.count == 1, "Remove the long-edge selector")

        for size in [NSSize(width: 760, height: 480), NSSize(width: 640, height: 400), NSSize(width: 1000, height: 600)] {
            window.setContentSize(size)
            for index in 0..<format.numberOfItems {
                format.selectItem(at: index)
                format.sendAction(format.action, to: format.target)
                container.layoutSubtreeIfNeeded()
                check(abs(container.bounds.width - size.width) < 1, "Window content must keep its requested width")
                check(bar.frame.height == 136 && drop.frame.height > 200, "Toolbar and image list must have usable height")
                for control in descendants(of: bar).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
                    let frame = control.convert(control.bounds, to: container)
                    check(container.bounds.insetBy(dx: -1, dy: -1).contains(frame), "Visible control is clipped: \(control)")
                }
            }
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = folder.appendingPathComponent("fixture.png")
        try writeFixture(encodingFixture(), to: fixture)
        format.selectItem(withTitle: "JPEG")
        format.sendAction(format.action, to: format.target)
        drop.onDrop?([fixture, fixture])
        check(table.numberOfRows == 1 && convert.isEnabled, "Adding an image must populate the table without duplicates")
        let slider = views.compactMap { $0 as? NSSlider }.first!
        let summary = views.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "conversionEstimateSummary" }!
        let noCompression = views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "conversionNoCompression" }!
        check(slider.isContinuous, "Output sizes must update while dragging, not just on mouse up")
        check(slider.minValue == 0 && slider.maxValue == 100, "Quality must span the full 0–100 range")
        var updatedDuringDrag = false
        for value in 20..<30 {
            slider.doubleValue = Double(value)
            slider.sendAction(slider.action, to: slider.target)
            try await Task.sleep(nanoseconds: 50_000_000)
            if estimatedCell(tool: tool, table: table) != "…" { updatedDuringDrag = true }
        }
        check(updatedDuringDrag, "Continuous slider events must not defer all previews until the drag stops")
        for value in [0.0, 0.25, 1.0] {
            slider.doubleValue = value * 100
            slider.sendAction(slider.action, to: slider.target)
            try await waitForEstimate(tool: tool, table: table)
            let data = try ImageConversionWorker.encodedData(source: fixture,
                options: ImageConversionOptions(format: .jpeg, quality: value))
            check(estimatedCell(tool: tool, table: table) == byteString(data.count), "Slider preview must reflect the actual encoder's output")
            check(summary.stringValue.contains(byteString(data.count)), "Summary must show the estimated total")
        }
        for value in [0.1, 0.95, 0.4] {
            slider.doubleValue = value * 100
            slider.sendAction(slider.action, to: slider.target)
        }
        try await waitForEstimate(tool: tool, table: table)
        let latest = try ImageConversionWorker.encodedData(source: fixture,
            options: ImageConversionOptions(format: .jpeg, quality: 0.4))
        check(estimatedCell(tool: tool, table: table) == byteString(latest.count), "Rapid slider changes must not publish stale estimates")
        format.selectItem(withTitle: "PNG")
        format.sendAction(format.action, to: format.target)
        try await waitForEstimate(tool: tool, table: table)
        check(!slider.isHidden && slider.isEnabled, "PNG must offer real color-precision compression")
        let png = try ImageConversionWorker.encodedData(source: fixture,
            options: ImageConversionOptions(format: .png, quality: 0.4))
        check(estimatedCell(tool: tool, table: table) == byteString(png.count), "Changing formats must recompute the output size")
        let previewColumn = table.tableColumns.first { $0.identifier.rawValue == "preview" }!
        check((tool.tableView(table, viewFor: previewColumn, row: 0) as? NSImageView)?.image != nil,
              "Image rows must show the encoded output, not only its byte count")
        noCompression.performClick(nil)
        try await waitForEstimate(tool: tool, table: table)
        check(!slider.isEnabled && !slider.isHidden, "Quality None disables, but does not hide, the slider")
        let originalSize = try Data(contentsOf: fixture).count
        check(estimatedCell(tool: tool, table: table) == byteString(originalSize), "Same-format Quality None must retain original data")
        noCompression.performClick(nil)
        format.selectItem(withTitle: "WebP")
        format.sendAction(format.action, to: format.target)
        check(!slider.isHidden && slider.isEnabled, "WebP must support the compression quality slider")
        try await waitForEstimate(tool: tool, table: table)
        let webp = try ImageConversionWorker.encodedData(source: fixture,
            options: ImageConversionOptions(format: .webp, quality: 0.4))
        check(estimatedCell(tool: tool, table: table) == byteString(webp.count), "WebP size preview must use the actual bundled encoder")
        let secondFixture = folder.appendingPathComponent("second.jpg")
        let jpeg = try ImageConversionWorker.encodedData(source: fixture,
            options: ImageConversionOptions(format: .jpeg, quality: 0.3))
        try jpeg.write(to: secondFixture)
        drop.onDrop?([secondFixture])
        format.selectItem(withTitle: "None")
        format.sendAction(format.action, to: format.target)
        for value in [10.0, 95.0, 55.0] {
            slider.doubleValue = value
            slider.sendAction(slider.action, to: slider.target)
        }
        try await waitForEstimate(tool: tool, table: table)
        check(table.numberOfRows == 2, "Batch compression must retain both files")
        var total = 0
        for (row, source) in [fixture, secondFixture].enumerated() {
            let result = try ImageConversionWorker.encodedData(source: source,
                options: ImageConversionOptions(format: nil, quality: 0.55))
            total += result.count
            check(estimatedCell(tool: tool, table: table, row: row) == byteString(result.count),
                  "Every row must reflect the latest quality using its own source format")
            let sourceSize = try Data(contentsOf: source).count
            check(result.count <= sourceSize, "Compression must not inflate any batch item")
        }
        check(summary.stringValue.contains(byteString(total)), "Batch summary must add every output size")
        if let directory = ProcessInfo.processInfo.environment["SAKURA_TEST_RENDER_DIR"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            format.selectItem(withTitle: "JPEG")
            format.sendAction(format.action, to: format.target)
            try await waitForEstimate(tool: tool, table: table)
            window.setContentSize(NSSize(width: 760, height: 480))
            container.layoutSubtreeIfNeeded()
            let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
            container.cacheDisplay(in: container.bounds, to: bitmap)
            let language = ProcessInfo.processInfo.environment["SAKURA_TEST_LANGUAGE"] ?? "zh"
            try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("conversion-\(language).png"))
        }
        table.selectRowIndexes(IndexSet(integersIn: 0..<table.numberOfRows), byExtendingSelection: false)
        remove.performClick(nil)
        check(table.numberOfRows == 0 && !convert.isEnabled, "Removing the image must update Convert")
        check(summary.stringValue == L("添加图片以预览输出大小"), "Removing all images must clear the size summary")
        window.close()
        tool.show()
        check(window.isVisible && window.frame.width >= 640, "Closed conversion window must reopen")
    }

    private static func byteString(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private static func estimatedCell(tool: ImageConvertToolController, table: NSTableView, row: Int = 0) -> String {
        let column = table.tableColumns.first { $0.identifier.rawValue == "estimated" }!
        return (tool.tableView(table, viewFor: column, row: row) as! NSTextField).stringValue
    }

    private static func waitForEstimate(tool: ImageConvertToolController, table: NSTableView) async throws {
        for _ in 0..<300 {
            if (0..<table.numberOfRows).allSatisfy({ estimatedCell(tool: tool, table: table, row: $0) != "…" }) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        preconditionFailure("Background size estimate timed out")
    }

    private static func verifyPickerCoordinates() {
        let session = ColorPickerSession()
        for screen in NSScreen.screens {
            let before = NSCursor.current
            let window = ColorPickerOverlayWindow(screen: screen, session: session)
            let view = window.overlayView
            check(NSCursor.current === before, "Creating an overlay must not push a cursor onto the global stack")
            check(view.acceptsFirstMouse(for: nil) && !window.ignoresMouseEvents, "Picker must accept the first click")
            check(window.makeFirstResponder(view), "Picker must accept keyboard focus for Esc")
            check(view.pickerCursor === NSCursor.crosshair, "Picker must use the built-in crosshair instead of a custom cursor image")
            view.updateTrackingAreas()
            view.updateTrackingAreas()
            check(view.trackingAreas.count == 1 && view.trackingAreas[0].options.contains(.cursorUpdate), "Cursor tracking must be active without leaking tracking areas")
            let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            NSCursor.arrow.set()
            view.mouseMoved(with: event)
            check(NSCursor.current === view.pickerCursor, "Mouse movement must restore an overridden picker cursor")
            NSCursor.arrow.set()
            view.ensurePickerCursor()
            check(NSCursor.current === view.pickerCursor, "Polling must restore the cursor after menu dismissal or window activation")
            // Include a secondary display left of and below the primary, even on single-screen CI.
            for origin in [screen.frame.origin, NSPoint(x: -1800, y: -1000)] {
                window.setFrameOrigin(origin)
                let frame = window.frame
                let global = NSPoint(x: frame.minX + 25, y: frame.maxY - 40)
                let local = view.convert(window.convertPoint(fromScreen: global), from: nil)
                check(abs(local.x - 25) < 0.01 && abs(local.y - 40) < 0.01,
                      "Screen-to-overlay conversion must use a top-left origin, including negative display origins")
            }
            view.setFrameSize(NSSize(width: 240, height: 200))
            view.cursorPoint = NSPoint(x: 20, y: 20)
            let marker = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: marker)
            let markerScale = CGFloat(marker.pixelsWide) / view.bounds.width
            check(marker.colorAt(x: Int(20 * markerScale), y: Int(20 * markerScale))!.alphaComponent > 0.9,
                  "Overlay must draw a visible crosshair even before sampling and independent of the system cursor")
            view.color = .red
            view.hex = "#FF0000"
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            let swatch = bitmap.colorAt(x: Int(50 * scale), y: Int(50 * scale))!.usingColorSpace(.sRGB)!
            // AppKit's cached display image uses the current monitor's color profile.
            check(swatch.redComponent > 0.7 && swatch.greenComponent < 0.4 && swatch.blueComponent < 0.4,
                  "Color swatch must appear next to the cursor")
            let background = bitmap.colorAt(x: 0, y: 0)!
            check(background.alphaComponent > 0, "Overlay background must remain hit-testable outside the swatch")
            window.orderOut(nil)
            NSCursor.arrow.set()
        }
    }

    private static func writeFixture(_ image: CGImage, to url: URL, orientation: Int = 1) throws {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        check(CGImageDestinationFinalize(destination), "Test fixture must encode")
    }

    private static func encodingFixture() -> CGImage {
        let width = 256, height = 192
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 42
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                for channel in 0..<3 {
                    seed = seed &* 1664525 &+ 1013904223
                    pixels[offset + channel] = UInt8(truncatingIfNeeded: seed >> 16)
                }
                let alpha = y < 16 ? (x < 16 ? 0 : (x < 32 ? 128 : 255)) : 255
                pixels[offset + 3] = UInt8(alpha)
                for channel in 0..<3 { pixels[offset + channel] = UInt8(Int(pixels[offset + channel]) * alpha / 255) }
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func verifyImageEncoding() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.png")
        try writeFixture(encodingFixture(), to: source)
        let original = try Data(contentsOf: source)
        let worker = ImageConversionWorker()
        for format in ImageOutputFormat.available {
            let settings = ImageConversionOptions(format: format, quality: 0.7)
            let estimate = try await worker.estimatedSize(source: source, options: settings)
            let output = try await worker.convert(source: source, options: settings)
            let data = try Data(contentsOf: output)
            check(abs(data.count - estimate) < 100, "Preview and export must share the same encoder for \(format.title)")
            let decoded = CGImageSourceCreateWithURL(output as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
            check(image.width == 256 && image.height == 192, "Quality must not change pixel dimensions")
            check(CGImageSourceGetCount(decoded) == 1, "GIF and multipage conversions must explicitly export a still image")
            check(CGImageSourceGetType(decoded) as String? == format.rawValue, "Export must use the selected file format")
            if format == .webp {
                check(data.prefix(4) == Data("RIFF".utf8) && data.subdata(in: 8..<12) == Data("WEBP".utf8),
                      "WebP output must be a real WebP container, not a renamed PNG")
                let transparent = ScreenCapturer.color(in: image, at: .zero, viewSize: NSSize(width: 256, height: 192))!
                let translucent = ScreenCapturer.color(in: image, at: NSPoint(x: 24, y: 2), viewSize: NSSize(width: 256, height: 192))!
                check(transparent.alphaComponent < 0.05, "WebP must preserve transparent pixels and image orientation")
                check(abs(translucent.alphaComponent - 128.0 / 255) < 0.02, "WebP must preserve partial transparency")
            }
            if format.requiresOpaqueImage {
                let color = ScreenCapturer.color(in: image, at: .zero, viewSize: NSSize(width: 256, height: 192))!
                check(color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95,
                      "JPEG/BMP must flatten transparency onto white, not black")
            }
        }
        let low = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: .jpeg, quality: 0.2))
        let high = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: .jpeg, quality: 0.95))
        check(low.count < high.count, "Quality slider must change real encoded bytes")
        let webpLow = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: .webp, quality: 0.2))
        let webpHigh = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: .webp, quality: 0.95))
        check(webpLow.count < webpHigh.count, "WebP quality slider must affect the encoded size")
        let unchanged = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: nil, quality: nil))
        check(unchanged == original, "Both None options must preserve every source byte")
        let losslessWebP = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: .webp, quality: nil))
        // VP8L is the lossless bitstream; it must not silently fall back to lossy quality 100.
        check(losslessWebP.subdata(in: 12..<16) == Data("VP8L".utf8), "Quality None must use true lossless WebP")
        let pngLow = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: nil, quality: 0))
        let pngHigh = try ImageConversionWorker.encodedData(source: source,
            options: ImageConversionOptions(format: nil, quality: 1))
        check(pngLow.count < pngHigh.count && pngHigh.count <= original.count, "PNG quality must affect compression without inflating files")
        let pngSource = CGImageSourceCreateWithData(pngLow as CFData, nil)!
        check(CGImageSourceGetType(pngSource) as String? == ImageOutputFormat.png.rawValue, "Format None must not disguise another format as PNG")
        let pngImage = CGImageSourceCreateImageAtIndex(pngSource, 0, nil)!
        let translucentPNG = ScreenCapturer.color(in: pngImage, at: NSPoint(x: 24, y: 2), viewSize: NSSize(width: 256, height: 192))!
        check(abs(translucentPNG.alphaComponent - 128.0 / 255) < 0.02, "PNG compression must preserve partial transparency")
        let jpegSource = folder.appendingPathComponent("small.jpg")
        try low.write(to: jpegSource)
        let recompressed = try ImageConversionWorker.encodedData(source: jpegSource,
            options: ImageConversionOptions(format: nil, quality: 1))
        check(recompressed == low, "High quality must keep an already-small JPEG instead of making it larger")
        let sameFormat = try ImageConversionWorker.encodedData(source: jpegSource,
            options: ImageConversionOptions(format: .jpeg, quality: 1))
        check(sameFormat == low, "Explicit same-format compression also needs the size safeguard")
        let bmp = try ImageConversionWorker.encodedData(source: jpegSource,
            options: ImageConversionOptions(format: .bmp, quality: nil))
        check(bmp.count > low.count, "A requested format conversion must not be replaced by the original just because it is larger")
        let animation = folder.appendingPathComponent("animated.gif")
        let gif = CGImageDestinationCreateWithURL(animation as CFURL, ImageOutputFormat.gif.rawValue as CFString, 2, nil)!
        CGImageDestinationAddImage(gif, encodingFixture(), nil)
        CGImageDestinationAddImage(gif, encodingFixture(), nil)
        check(CGImageDestinationFinalize(gif), "Animated fixture must encode")
        let animationOriginal = try Data(contentsOf: animation)
        for quality: Double? in [nil, 0.5] {
            let result = try ImageConversionWorker.encodedData(source: animation,
                options: ImageConversionOptions(format: nil, quality: quality))
            check(result == animationOriginal, "Keep-format mode must not destroy animation or additional pages")
        }
        let originalExport = try await worker.convert(source: source,
            options: ImageConversionOptions(format: nil, quality: nil))
        let exportedOriginal = try Data(contentsOf: originalExport)
        check(originalExport.pathExtension == "png" && exportedOriginal == original,
              "Keep-format export must retain both the source extension and original bytes")
        let rotated = folder.appendingPathComponent("rotated.png")
        try writeFixture(encodingFixture(), to: rotated, orientation: 6)
        let rotatedData = try ImageConversionWorker.encodedData(source: rotated,
            options: ImageConversionOptions(format: .jpeg, quality: nil))
        let rotatedSource = CGImageSourceCreateWithData(rotatedData as CFData, nil)!
        let rotatedImage = CGImageSourceCreateImageAtIndex(rotatedSource, 0, nil)!
        check(rotatedImage.width == 192 && rotatedImage.height == 256, "Conversion must apply camera orientation without resizing")
        let oversized = folder.appendingPathComponent("wide.png")
        let wideContext = CGContext(data: nil, width: 16384, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        try writeFixture(wideContext.makeImage()!, to: oversized)
        do {
            _ = try ImageConversionWorker.encodedData(source: oversized,
                options: ImageConversionOptions(format: .webp, quality: 0.8))
            preconditionFailure("Oversized WebP dimensions must report a useful error")
        } catch ImageConversionWorker.ConversionError.webpDimensions {
            check(true, "Oversized WebP input reports the format limit")
        }
        let settings = ImageConversionOptions(format: .jpeg, quality: 0.9)
        let first = try await worker.convert(source: source, options: settings)
        let second = try await worker.convert(source: source, options: settings)
        check(first != second, "Existing output files must never be overwritten")
        let preserved = try Data(contentsOf: source)
        check(preserved == original, "Original image must remain unchanged")
        let missing = Task { try await worker.estimatedSize(source: folder.appendingPathComponent("missing.png"), options: settings) }
        do {
            _ = try await missing.value
            preconditionFailure("Missing source must report an error")
        } catch { check(true, "Missing source reports an error") }
        let cancelled = Task { try await worker.estimatedSize(source: source, options: settings) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled estimate must not publish a result")
        } catch is CancellationError { check(true, "Cancelled estimate exits cleanly") }
    }

    private static func fixtureImage() -> CGImage {
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for y in 0..<4 {
            for x in 0..<4 {
                let offset = (y * 4 + x) * 4
                pixels[offset] = UInt8(x * 80)
                pixels[offset + 1] = UInt8(y * 80)
                pixels[offset + 2] = 64
                pixels[offset + 3] = 255
            }
        }
        return CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func verifyColorSampling() {
        let image = fixtureImage()
        for size in [NSSize(width: 4, height: 4), NSSize(width: 2, height: 2), NSSize(width: 400, height: 240)] {
            for y in 0..<4 {
                for x in 0..<4 {
                    let point = NSPoint(x: (CGFloat(x) + 0.5) * size.width / 4, y: (CGFloat(y) + 0.5) * size.height / 4)
                    let color = ScreenCapturer.color(in: image, at: point, viewSize: size)!.usingColorSpace(.sRGB)!
                    check(abs(color.redComponent * 255 - CGFloat(x * 80)) < 1 &&
                          abs(color.greenComponent * 255 - CGFloat(y * 80)) < 1,
                          "Sampling must return the exact clicked pixel, independent of display scale")
                }
            }
        }
        for point in [NSPoint(x: 0, y: 0), NSPoint(x: 4, y: 4), NSPoint(x: -1, y: -1)] {
            check(ScreenCapturer.color(in: image, at: point, viewSize: NSSize(width: 4, height: 4)) != nil,
                  "Display edges must clamp to valid pixels")
        }
        check(ScreenCapturer.color(in: image, at: .zero, viewSize: .zero) == nil, "Empty views cannot be sampled")
    }
}
