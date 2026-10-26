import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

func L(_ key: String) -> String {
    guard ProcessInfo.processInfo.environment["SAKURA_TEST_LANGUAGE"] == "en",
          let bundle = Bundle(path: "Resources/en.lproj") else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

@main
@MainActor
enum StitchChecks {
    private static var checks = 0

    private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                try verifyModel(folder)
                try await verifyWindow(folder)
                let result = "Image stitching passed: \(checks) assertions (\(ProcessInfo.processInfo.environment["SAKURA_TEST_LANGUAGE"] ?? "zh"))"
                if let file = ProcessInfo.processInfo.environment["SAKURA_TEST_COMPLETION_FILE"] {
                    try result.write(toFile: file, atomically: true, encoding: .utf8)
                }
                print(result)
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Stitch regression failed: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        app.run()
        preconditionFailure("AppKit exited before checks completed")
    }

    private static func image(width: Int, height: Int, color: (UInt8, UInt8, UInt8, UInt8), bottom: (UInt8, UInt8, UInt8, UInt8)? = nil) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let c = y >= height / 2 ? (bottom ?? color) : color
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = c.0; pixels[i + 1] = c.1; pixels[i + 2] = c.2; pixels[i + 3] = c.3
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func write(_ image: CGImage, _ url: URL, type: UTType = .png, orientation: Int? = nil) throws {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        let properties: CFDictionary? = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        check(CGImageDestinationFinalize(destination), "Fixture encoding must succeed")
    }

    private static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pointer = context.data!.assumingMemoryBound(to: UInt8.self)
        let i = (y * image.width + x) * 4
        return [pointer[i], pointer[i + 1], pointer[i + 2], pointer[i + 3]]
    }

    private static func verifyModel(_ folder: URL) throws {
        let firstURL = folder.appendingPathComponent("first.png")
        let secondURL = folder.appendingPathComponent("second.png")
        try write(image(width: 20, height: 10, color: (255, 0, 0, 255), bottom: (0, 0, 255, 255)), firstURL)
        try write(image(width: 10, height: 20, color: (0, 255, 0, 255)), secondURL)
        let first = try StitchRenderer.load(firstURL)
        let second = try StitchRenderer.load(secondURL)
        var document = StitchDocument()
        check(document.outputBounds == .zero && !document.canExport, "Empty document cannot export")
        document.append([first, second], gap: 5)
        check(document.images[1].frame.origin == CGPoint(x: 25, y: 0), "Import appends without overlap")
        check(document.outputBounds.size == CGSize(width: 35, height: 20), "Horizontal union includes gaps")
        let horizontal = try StitchRenderer.render(document)
        check(pixel(horizontal, 2, 1) == [255, 0, 0, 255], "Source top must stay at top")
        check(pixel(horizontal, 2, 8) == [0, 0, 255, 255], "Source bottom must stay at bottom")
        check(pixel(horizontal, 22, 4)[3] == 0, "Transparent gap must remain transparent")
        check(pixel(horizontal, 28, 4) == [0, 255, 0, 255], "Second image must appear on right")
        document.arrange(vertical: true, gap: 3)
        check(document.images[1].frame.origin == CGPoint(x: 0, y: 13), "Vertical arrange uses placed sizes")
        check(document.outputBounds.size == CGSize(width: 20, height: 33), "Vertical output dimensions")
        let vertical = try StitchRenderer.render(document)
        check(pixel(vertical, 1, 1) == [255, 0, 0, 255], "Top image must not swap with bottom image")
        check(pixel(vertical, 1, 20) == [0, 255, 0, 255], "Bottom image placement")
        document.background = .white
        let white = try StitchRenderer.render(document)
        check(pixel(white, 15, 20) == [255, 255, 255, 255], "White background fills unused regions")
        document.background = .black
        let black = try StitchRenderer.render(document)
        check(pixel(black, 15, 20) == [0, 0, 0, 255], "Black background fills unused regions")
        document.images[0].frame.origin = CGPoint(x: -7.5, y: -3.5)
        document.images[1].frame.origin = CGPoint(x: -7.5, y: -3.5)
        document.background = .transparent
        check(document.outputBounds.minX == -8 && document.outputBounds.minY == -4, "Negative fractional bounds round outwards")
        let overlap = try StitchRenderer.render(document)
        check(pixel(overlap, 3, 3) == [0, 255, 0, 255], "Last image is on top")
        document.images.swapAt(0, 1)
        let reordered = try StitchRenderer.render(document)
        check(pixel(reordered, 3, 3) == [255, 0, 0, 255], "Reordering changes exported overlap")
        let resized = StitchDocument.resizedFrame(first, scale: 0.5)
        check(resized.size == CGSize(width: 10, height: 5), "Scale preserves aspect ratio")
        check(StitchDocument.resizedFrame(first, scale: -1).width == 0.2, "Scale has positive lower bound")
        check(StitchDocument.resizedFrame(first, scale: 100).width == 160, "Scale has upper bound")
        document.images[0].frame.size = CGSize(width: 6000, height: 6000)
        check(!document.canExport, "Pixel budget rejects huge bitmap allocations")
        do { _ = try StitchRenderer.render(document); preconditionFailure("Oversize render should fail") }
        catch StitchFailure.tooLarge { checks += 1 }
        document.images[0].frame.size = CGSize(width: 40000, height: 2)
        check(!document.canExport, "Single edge has a separate safety limit")
        do { _ = try StitchRenderer.load(folder.appendingPathComponent("missing.png")); preconditionFailure("Missing import should fail") }
        catch StitchFailure.unreadable { checks += 1 }

        let largeURL = folder.appendingPathComponent("large.png")
        try write(image(width: 1800, height: 900, color: (230, 100, 50, 255)), largeURL)
        let large = try StitchRenderer.load(largeURL)
        check(large.preview.width <= 640 && large.preview.height <= 640, "Editing retains a bounded thumbnail, not full decoded source")
        check(large.pixelSize == CGSize(width: 1800, height: 900), "Original dimensions remain available")
        let full = try StitchRenderer.render(StitchDocument(images: [large]))
        check(full.width == 1800 && full.height == 900, "Export reads original resolution instead of preview")
        let png = try StitchRenderer.pngData(StitchDocument(images: [first]))
        check(png.starts(with: [137, 80, 78, 71]), "Clipboard and export use actual PNG bytes")
        let rotatedURL = folder.appendingPathComponent("rotated.tiff")
        try write(image(width: 30, height: 10, color: (120, 50, 0, 255)), rotatedURL, type: .tiff, orientation: 6)
        let rotated = try StitchRenderer.load(rotatedURL)
        check(rotated.pixelSize == CGSize(width: 10, height: 30), "EXIF orientation swaps logical dimensions")
        check(rotated.preview.height > rotated.preview.width, "Preview applies EXIF orientation")
        let oriented = try StitchRenderer.render(StitchDocument(images: [rotated]))
        check(oriented.width == 10 && oriented.height == 30, "Export matches oriented canvas")
        var capped = StitchDocument()
        capped.append(Array(repeating: first, count: 40), gap: 0)
        check(capped.images.count == StitchDocument.imageLimit, "Import count is capped")
        document = StitchDocument(images: [first])
        try FileManager.default.removeItem(at: firstURL)
        do { _ = try StitchRenderer.render(document); preconditionFailure("Unavailable source must not silently export a preview") }
        catch StitchFailure.unreadable { checks += 1 }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private static func click(_ title: String, window: NSWindow) {
        let button = descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == L(title) }!
        check(button.isEnabled, "Button should be enabled: \(title)")
        button.performClick(nil)
    }

    private static func mouse(_ type: NSEvent.EventType, _ point: CGPoint, _ canvas: StitchCanvasView, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
                           windowNumber: canvas.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func key(_ code: UInt16, canvas: StitchCanvasView, flags: NSEvent.ModifierFlags = [], characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: canvas.window!.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Async operation timed out")
    }

    private static func verifyWindow(_ folder: URL) async throws {
        let tool = ImageStitchToolController.shared
        tool.show()
        let window = NSApp.windows.first { $0.title == L("图片拼接") }!
        let canvas = descendants(window.contentView!).compactMap { $0 as? StitchCanvasView }.first!
        check(window.isVisible, "Tool opens its own native window")
        check(!canvas.document.canExport, "Empty canvas starts clean")
        for size in [NSSize(width: 860, height: 548), NSSize(width: 860, height: 580), NSSize(width: 1060, height: 720), NSSize(width: 1280, height: 800)] {
            window.setContentSize(size)
            try await Task.sleep(nanoseconds: 30_000_000)
            window.contentView!.layoutSubtreeIfNeeded()
            check(abs(window.contentView!.frame.height - size.height) < 1, "Sidebar must not force the window to its preferred height")
            check(canvas.frame.width >= 600 && canvas.frame.height >= 430,
                  "Canvas remains usable at every window size: requested \(size), actual \(canvas.frame), content \(window.contentView!.bounds)")
            for control in descendants(window.contentView!).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
                let rect = control.convert(control.bounds, to: window.contentView)
                check(window.contentView!.bounds.insetBy(dx: -1, dy: -1).contains(rect), "Control must not clip: \(control)")
            }
        }
        window.setContentSize(NSSize(width: 1060, height: 720))
        window.contentView!.layoutSubtreeIfNeeded()
        let leftURL = folder.appendingPathComponent("01 — Overview.png")
        let rightURL = folder.appendingPathComponent("02 — Detail.png")
        try write(image(width: 800, height: 520, color: (32, 97, 102, 255), bottom: (230, 235, 220, 255)), leftURL)
        try write(image(width: 600, height: 520, color: (190, 100, 65, 255), bottom: (246, 226, 190, 255)), rightURL)
        tool.add(urls: [leftURL, rightURL])
        try await waitUntil { !canvas.isBusy }
        check(canvas.document.images.count == 2, "Multiple files import asynchronously")
        check(canvas.selectedID == canvas.document.images.last?.id, "Imported image is selected")
        check(canvas.zoom < 1, "Imported canvas automatically fits")
        let first = canvas.document.images[0]
        let center = CGPoint(x: canvas.viewRect(first.frame).midX, y: canvas.viewRect(first.frame).midY)
        canvas.mouseDown(with: mouse(.leftMouseDown, center, canvas))
        check(canvas.selectedID == first.id, "Click selects image")
        let end = CGPoint(x: center.x - 40, y: center.y + 30)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, end, canvas, flags: .option))
        canvas.mouseUp(with: mouse(.leftMouseUp, end, canvas))
        check(canvas.document.images[0].frame.origin.x < 0, "Canvas allows negative placement, not a fixed clipping page")
        check(canvas.history.canUndo, "Dragging registers undo")
        check(canvas.performKeyEquivalent(with: key(6, canvas: canvas, flags: .command, characters: "z")), "Command Z routes to canvas history")
        check(canvas.document.images[0].frame == first.frame, "Undo restores pre-drag placement")
        _ = canvas.performKeyEquivalent(with: key(6, canvas: canvas, flags: [.command, .shift], characters: "z"))
        check(canvas.document.images[0].frame.origin.x < 0, "Redo restores drag")
        canvas.history.undo()
        let rect = canvas.viewRect(canvas.document.images[0].frame)
        let corner = CGPoint(x: rect.maxX, y: rect.maxY)
        let target = CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.6)
        canvas.mouseDown(with: mouse(.leftMouseDown, corner, canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, target, canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, target, canvas))
        check(abs(canvas.document.images[0].frame.width - 480) < 0.1, "Corner drag scales image")
        check(abs(canvas.document.images[0].frame.width / canvas.document.images[0].frame.height - 800.0 / 520) < 0.001, "Corner drag preserves ratio")
        let beforeNudge = canvas.document.images[0].frame
        canvas.keyDown(with: key(124, canvas: canvas, flags: .shift))
        check(canvas.document.images[0].frame.minX == beforeNudge.minX + 10, "Shift arrow moves by ten pixels")
        canvas.history.undo()
        check(canvas.document.images[0].frame == beforeNudge, "Keyboard adjustment is undoable")
        click("恢复原始尺寸", window: window)
        check(canvas.document.images[0].frame.size == first.pixelSize, "Original size restores source pixels")
        verifyCanvasGestures(canvas)
        let scale = descendants(window.contentView!).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "stitchScale" }!
        scale.doubleValue = 50
        scale.sendAction(scale.action, to: scale.target)
        check(canvas.document.images[0].frame.width == 400, "Inspector changes scale")
        click("移到最前", window: window)
        check(canvas.document.images.last?.id == first.id, "Bring to front changes draw order")
        click("移到最后", window: window)
        check(canvas.document.images.first?.id == first.id, "Send to back changes draw order")
        let gap = descendants(window.contentView!).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "stitchGap" }!
        gap.doubleValue = 24
        gap.sendAction(gap.action, to: gap.target)
        click("纵向排列", window: window)
        check(canvas.document.images[1].frame.minY == canvas.document.images[0].frame.height + 24, "Vertical arrangement honors gap")
        click("横向排列", window: window)
        check(canvas.document.images[1].frame.minX == canvas.document.images[0].frame.width + 24, "Horizontal arrangement honors gap")
        let background = descendants(window.contentView!).compactMap { $0 as? NSPopUpButton }.first!
        background.selectItem(at: 1)
        background.sendAction(background.action, to: background.target)
        check(canvas.document.background == .white, "Background control updates output")
        canvas.history.undo()
        check(canvas.document.background == .transparent && background.indexOfSelectedItem == 0, "Undo synchronizes background control")
        let previousZoom = canvas.zoom
        let anchor = CGPoint(x: 200, y: 100)
        let beforeWorld = CGPoint(x: (anchor.x - canvas.offset.x) / canvas.zoom, y: (anchor.y - canvas.offset.y) / canvas.zoom)
        canvas.setZoom(previousZoom * 1.4, anchor: anchor)
        let afterWorld = CGPoint(x: (anchor.x - canvas.offset.x) / canvas.zoom, y: (anchor.y - canvas.offset.y) / canvas.zoom)
        check(hypot(beforeWorld.x - afterWorld.x, beforeWorld.y - afterWorld.y) < 0.001, "Zoom preserves point under cursor")
        canvas.fit()
        // Exercise actual AppKit drawing at several window sizes, including selected handles.
        for size in [NSSize(width: 860, height: 580), NSSize(width: 1060, height: 720)] {
            window.setContentSize(size)
            window.contentView!.layoutSubtreeIfNeeded()
            canvas.fit()
            let view = window.contentView!
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            check(bitmap.pixelsWide >= Int(size.width), "Canvas draws successfully with native controls")
            if let path = ProcessInfo.processInfo.environment["SAKURA_STITCH_PREVIEW_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let language = ProcessInfo.processInfo.environment["SAKURA_TEST_LANGUAGE"] ?? "zh"
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("stitch-\(language)-\(Int(size.width)).png"))
            }
        }
        let pasteboard = NSPasteboard.general
        let clipboard = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var saved: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { saved[type] = item.data(forType: type) }
            return saved
        } ?? []
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(clipboard.map { saved in
                let item = NSPasteboardItem()
                for (type, data) in saved { item.setData(data, forType: type) }
                return item
            })
        }
        click("复制图片", window: window)
        try await waitUntil { !canvas.isBusy }
        let copied = pasteboard.data(forType: .png)!
        let copiedSource = CGImageSourceCreateWithData(copied as CFData, nil)!
        let copiedImage = CGImageSourceCreateImageAtIndex(copiedSource, 0, nil)!
        check(copiedImage.width == Int(canvas.document.outputBounds.width), "Copy exports actual canvas resolution")
        canvas.selectedID = first.id
        click("移除图片", window: window)
        check(canvas.document.images.count == 1 && canvas.selectedID == nil, "Remove only selected image")
        canvas.history.undo()
        check(canvas.document.images.count == 2, "Removal is undoable")
        click("清空", window: window)
        check(canvas.document.images.isEmpty, "Clear empties canvas")
        canvas.history.undo()
        check(canvas.document.images.count == 2, "Clear is undoable")
        window.close()
        check(canvas.document.images.isEmpty && !canvas.history.canUndo, "Closing releases previews and undo references")
        tool.show()
        let reopened = NSApp.windows.first { $0.title == L("图片拼接") && $0.isVisible }!
        let reopenedCanvas = descendants(reopened.contentView!).compactMap { $0 as? StitchCanvasView }.first!
        check(reopenedCanvas.document.images.isEmpty, "Reopening starts with a fresh canvas")
        tool.add(urls: [leftURL, rightURL])
        reopened.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        check(reopenedCanvas.document.images.isEmpty, "Closing during import cannot repopulate the closed window")
    }

    private static func verifyCanvasGestures(_ canvas: StitchCanvasView) {
        let image = canvas.document.images[0]
        canvas.selectedID = image.id
        for corner in 0..<4 {
            let rect = canvas.viewRect(image.frame)
            let points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                          CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            let start = points[corner]
            let anchor = points[(corner + 2) % 4]
            let end = CGPoint(x: anchor.x + (start.x - anchor.x) * 0.75,
                              y: anchor.y + (start.y - anchor.y) * 0.75)
            canvas.mouseDown(with: mouse(.leftMouseDown, start, canvas))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, end, canvas))
            canvas.mouseUp(with: mouse(.leftMouseUp, end, canvas))
            check(abs(canvas.document.images[0].frame.width - image.frame.width * 0.75) < 0.1,
                  "Every corner must resize proportionally: \(corner)")
            canvas.history.undo()
            check(canvas.document.images[0].frame == image.frame, "Corner resize undo restores exact placement")
        }
        let rect = canvas.viewRect(image.frame)
        let start = CGPoint(x: rect.midX, y: rect.midY)
        let close = CGPoint(x: start.x + 3, y: start.y + 25)
        canvas.mouseDown(with: mouse(.leftMouseDown, start, canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, close, canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, close, canvas))
        check(canvas.document.images[0].frame.maxX == canvas.document.images[1].frame.minX,
              "Dragging near another image snaps edges")
        canvas.history.undo()
        let far = CGPoint(x: start.x - 25, y: start.y - 25)
        canvas.mouseDown(with: mouse(.leftMouseDown, start, canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, far, canvas, flags: .option))
        canvas.keyDown(with: key(53, canvas: canvas))
        check(canvas.document.images[0].frame == image.frame, "Escape cancels active drag without adding a change")
        let originalBounds = canvas.document.bounds
        let originalOffset = canvas.offset
        canvas.keyDown(with: key(49, canvas: canvas))
        canvas.mouseDown(with: mouse(.leftMouseDown, start, canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, far, canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, far, canvas))
        canvas.keyUp(with: key(49, canvas: canvas))
        check(canvas.offset != originalOffset, "Space drag pans viewport")
        check(canvas.document.bounds == originalBounds, "Panning never changes export coordinates")
        canvas.fit()
        canvas.isBusy = true
        canvas.keyDown(with: key(51, canvas: canvas))
        check(canvas.document.images.count == 2, "Busy canvas cannot delete images during export")
        canvas.isBusy = false
    }
}
