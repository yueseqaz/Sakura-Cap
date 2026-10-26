import AppKit

@main
@MainActor
enum InlineScreenshotChecks {
    private static var checks = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            verifySetting()
            verifyGeometry()
            verifySelectionAndAnnotations()
            verifySelectionCursorRects()
            verifyCropScaling()
            await verifySession()
            let result = "In-place screenshot regressions passed: \(checks) assertions"
            if let completion = ProcessInfo.processInfo.environment["SAKURA_UI_TEST_COMPLETION"] {
                try! result.write(toFile: completion, atomically: true, encoding: .utf8)
            }
            print(result)
            exit(0)
        }
        app.run()
        preconditionFailure("AppKit exited before regression checks completed")
    }

    private static func verifySetting() {
        let defaults = UserDefaults.standard
        let key = "screenshotAnnotationMode"
        let previous = defaults.object(forKey: key)
        defer {
            AppSettings.shared.screenshotAnnotationMode = ScreenshotAnnotationMode(rawValue: previous as? String ?? "") ?? .window
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        if previous == nil {
            check(AppSettings.shared.screenshotAnnotationMode == .window, "Existing users retain the window workflow")
        }
        AppSettings.shared.screenshotAnnotationMode = .inline
        check(defaults.string(forKey: key) == "inline", "Persist in-place preference")
        AppSettings.shared.screenshotAnnotationMode = .window
        check(defaults.string(forKey: key) == "window", "Persist switching back to the old workflow")
        check(ScreenshotAnnotationMode(rawValue: "invalid") == nil, "Invalid modes fall back to the default")
    }

    private static func verifyGeometry() {
        let view = CGSize(width: 400, height: 300)
        let image = CGSize(width: 800, height: 600)
        check(InlineScreenshotView.pixelRect(CGRect(x: 20, y: 30, width: 50, height: 40), viewSize: view, imageSize: image)
              == CGRect(x: 40, y: 60, width: 100, height: 80), "Retina selection preserves native pixel size and top-left origin")
        check(InlineScreenshotView.pixelRect(CGRect(x: -10, y: -10, width: 500, height: 500), viewSize: view, imageSize: image)
              == CGRect(origin: .zero, size: image), "Clamp crop to the image, including selections at display edges")
        check(InlineScreenshotView.pixelRect(CGRect(x: 500, y: 500, width: 20, height: 20), viewSize: view, imageSize: image) == nil,
              "Reject crops outside the image")
        check(InlineScreenshotView.pixelRect(.zero, viewSize: .zero, imageSize: image) == nil, "Reject zero-size views")
        check(InlineScreenshotView.pixelRect(CGRect(x: 0.2, y: 0.4, width: 10.3, height: 20.2), viewSize: view, imageSize: image)
              == CGRect(x: 0, y: 0, width: 21, height: 42), "Round outward without losing edge pixels")
    }

    private static func image(width: Int = 800, height: Int = 600) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        return context.makeImage()!
    }

    private static func event(_ type: NSEvent.EventType, _ point: CGPoint, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                          windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func drag(_ view: InlineScreenshotView, from start: CGPoint, to end: CGPoint) {
        view.mouseDown(with: event(.leftMouseDown, start, in: view))
        view.mouseDragged(with: event(.leftMouseDragged, end, in: view))
        view.mouseUp(with: event(.leftMouseUp, end, in: view))
    }

    private static func verifySelectionAndAnnotations() {
        let view = InlineScreenshotView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), image: image())
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        var changes = 0
        view.onSelectionChanged = { changes += 1 }
        drag(view, from: CGPoint(x: 180, y: 160), to: CGPoint(x: 20, y: 30))
        check(view.selection == CGRect(x: 20, y: 30, width: 160, height: 130), "Reverse drags create a normalized selection")
        check(changes > 0, "Selection remains editable and reports changes after mouse-up")
        drag(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 120, y: 110))
        check(view.selection == CGRect(x: 40, y: 40, width: 160, height: 130), "Move the selected rectangle")
        drag(view, from: CGPoint(x: 200, y: 170), to: CGPoint(x: 250, y: 200))
        check(view.selection == CGRect(x: 40, y: 40, width: 210, height: 160), "Resize using the bottom-right handle")
        drag(view, from: CGPoint(x: 250, y: 70), to: CGPoint(x: 270, y: 70))
        check(view.selection?.width == 230, "Resize by dragging the edge away from its midpoint")
        drag(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: -500, y: -500))
        check(view.selection?.origin == .zero, "Moving a selection cannot leave the display")
        view.setSelection(CGRect(x: 20, y: 30, width: 160, height: 130))
        view.adjustingSelection = false
        func hit(_ point: CGPoint) -> NSView? { view.hitTest(view.convert(point, to: view.superview)) }
        check(hit(CGPoint(x: 100, y: 100)) === view.canvas, "Annotation mode sends interior clicks to the canvas")
        check(hit(CGPoint(x: 20, y: 30)) === view, "Selection handles remain accessible while annotating")
        check(hit(CGPoint(x: 390, y: 290)) === view, "Outside clicks never reach the live desktop")
        view.canvas.tool = .rectangle
        view.canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 60, y: 60), in: view.canvas))
        view.canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 120, y: 100), in: view.canvas))
        view.canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 120, y: 100), in: view.canvas))
        check(view.canvas.annotations.count == 1, "Reuse rectangle annotation on the frozen screenshot")
        let points = view.canvas.annotations[0].points
        check(points.first == CGPoint(x: 120, y: 120), "Annotations use original image-pixel coordinates")
        view.canvas.undo()
        check(view.canvas.annotations.isEmpty && view.canvas.canRedo, "Undo annotations without undoing the selected area")
        view.canvas.redo()
        check(view.canvas.annotations.count == 1, "Redo annotations")
        view.setSelection(CGRect(x: 30, y: 40, width: 180, height: 150))
        check(view.canvas.annotations[0].points == points, "Resizing the crop does not move existing annotations")
        view.canvas.tool = .text
        view.canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 90, y: 110), in: view.canvas))
        let textField = view.canvas.subviews.compactMap { $0 as? NSTextField }.first!
        textField.stringValue = "Frozen screenshot"
        let rendered = view.renderedSelection()!
        check(view.canvas.annotations.last?.text == "Frozen screenshot", "Export commits text still being edited")
        check(rendered.width == 360 && rendered.height == 300, "Export only the selected pixels, at native resolution")
        let pixel = NSBitmapImageRep(cgImage: rendered).colorAt(x: 0, y: 0)!.usingColorSpace(.sRGB)!
        check(pixel.redComponent > 0.95 && pixel.greenComponent > 0.95,
              "Export excludes dimming, selection border, and resize handles")
        view.setSelection(CGRect(x: 0, y: 200, width: 100, height: 80))
        let bottom = NSBitmapImageRep(cgImage: view.renderedSelection()!).colorAt(x: 20, y: 20)!.usingColorSpace(.sRGB)!
        check(bottom.blueComponent > bottom.redComponent, "Crop uses top-left origin, not an inverted display rectangle")
        view.setSelection(nil)
        check(view.renderedSelection() == nil, "No export without a selected area")
        view.setSelection(CGRect(x: 100, y: 80, width: 180, height: 140))
        let originalPixels = view.pixelSelection!
        let zoom = view.canvas.zoom
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 100, wheel2: 0, wheel3: 0)!
        view.canvas.scrollWheel(with: NSEvent(cgEvent: scroll)!)
        check(view.canvas.zoom != zoom, "In-place annotation supports the regular editor's zoom")
        check(view.pixelSelection == originalPixels, "Zoom does not change the selected image pixels")
        check(view.selection != CGRect(x: 100, y: 80, width: 180, height: 140), "Selection follows the canvas transform")
        check(view.renderedSelection()?.width == Int(originalPixels.width), "Zoom does not resample export")
        let anchor = view.canvas.viewPoint(CGPoint(x: originalPixels.midX, y: originalPixels.midY))
        check(abs(view.canvas.imagePoint(anchor).x - originalPixels.midX) < 0.001, "View/image transforms round-trip after zoom")
        view.canvas.resetZoom()
        view.canvas.tool = .crop
        let beforeCrop = view.pixelSelection!
        view.canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 130, y: 110), in: view.canvas))
        view.canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 220, y: 170), in: view.canvas))
        view.canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 220, y: 170), in: view.canvas))
        check(view.pixelSelection == CGRect(x: 260, y: 220, width: 180, height: 120), "Crop narrows the export area using native coordinates")
        check(view.canvas.baseImage?.width == 800 && view.canvas.annotations[0].points == points,
              "In-place crop preserves the frozen source and annotation positions")
        check(view.renderedSelection()?.width == 180, "Crop exports exactly once, without a second offset")
        view.canvas.undo()
        check(view.pixelSelection == beforeCrop, "Undo crop restores the earlier selection")
        view.canvas.redo()
        check(view.renderedSelection()?.height == 120, "Redo crop restores its pixel size")
        view.canvas.undo()
        view.setSelection(CGRect(x: 60, y: 60, width: 200, height: 160))
        view.canvas.undo()
        check(view.pixelSelection == CGRect(x: 120, y: 120, width: 400, height: 320), "Undoing annotations does not rewind subsequent manual frame adjustments")
        check(AnnotationCanvas(frame: .zero).allowsImageNavigation, "Independent editors retain their zoom behavior")
    }

    private static func verifySelectionCursorRects() {
        let view = InlineScreenshotView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), image: image())
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        // Exercise actual AppKit registration, not only selection geometry. A drag
        // passes through narrow rectangles before it reaches its final size.
        let selections: [CGRect?] = [nil, .zero,
            CGRect(x: 20, y: 20, width: 2, height: 2),
            CGRect(x: 20, y: 20, width: 4, height: 40),
            CGRect(x: 20, y: 20, width: 40, height: 4),
            CGRect(x: 20, y: 20, width: 14, height: 14),
            CGRect(x: 20, y: 20, width: 15, height: 15),
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 360, y: 260, width: 40, height: 40), view.bounds]
        for adjusting in [true, false] {
            view.adjustingSelection = adjusting
            for selection in selections {
                view.setSelection(selection)
                view.resetCursorRects()
                window.resetCursorRects()
                check(true, "Register safe cursor rectangles for \(String(describing: selection)), adjusting=\(adjusting)")
            }
        }
        view.setSelection(CGRect(x: 20, y: 20, width: 10, height: 10))
        view.canvas.zoom(at: .zero, factor: 20)
        check(!view.selection!.intersects(view.bounds), "Zoom can move the selection and all its handles offscreen")
        view.resetCursorRects()
        window.resetCursorRects()
        check(true, "Offscreen selection handles do not register null cursor rectangles")
    }

    private static func verifyCropScaling() {
        for size in [CGSize(width: 400, height: 300), CGSize(width: 601, height: 427), CGSize(width: 763, height: 501)] {
            let canvas = AnnotationCanvas(frame: CGRect(origin: .zero, size: size))
            canvas.baseImage = image()
            let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.tool = .crop
            let start = canvas.viewPoint(CGPoint(x: 100.25, y: 100.25))
            let end = canvas.viewPoint(CGPoint(x: 499.75, y: 399.75))
            canvas.mouseDown(with: event(.leftMouseDown, start, in: canvas))
            canvas.mouseDragged(with: event(.leftMouseDragged, end, in: canvas))
            canvas.mouseUp(with: event(.leftMouseUp, end, in: canvas))
            check(canvas.baseImage?.width == 400 && canvas.baseImage?.height == 300,
                  "Outward crop rounding is stable at fit size \(size)")
            canvas.undo()
            check(canvas.baseImage?.width == 800, "Undo crop at fit size \(size)")
            canvas.redo()
            check(canvas.renderedImage()?.height == 300, "Export redo crop at fit size \(size)")
            window.close()
        }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private static func verifyAnnotationInteractions(_ view: InlineScreenshotView) async {
        let controller = InlineScreenshotController.shared
        let canvas = view.canvas
        let toolbar = NSApp.windows.first { $0.identifier?.rawValue == "inline.tools" && $0.isVisible }!
        let properties = NSApp.windows.first { $0.identifier?.rawValue == "inline.properties" }!
        let controls = descendants(toolbar.contentView!)
        let picker = controls.compactMap { $0 as? NSSegmentedControl }.first!
        let propertyControls = descendants(properties.contentView!)
        let color = propertyControls.compactMap { $0 as? AnnotationColorPicker }.first!
        let width = propertyControls.compactMap { $0 as? NSSlider }.first { $0.maxValue == 20 }!
        let styles = propertyControls.compactMap { $0 as? NSSegmentedControl }.first!
        func tap(_ title: String) {
            let button = controls.compactMap { $0 as? NSButton }.first { $0.toolTip == L(title) }!
            button.sendAction(button.action!, to: button.target)
        }
        func tool(_ tool: AnnotationTool) {
            if tool == .magnifier { tap("放大镜：拖出圆形区域，将其中的图片放大 2 倍"); return }
            picker.selectedSegment = tool.rawValue
            picker.sendAction(picker.action!, to: picker.target)
        }
        func refresh(_ operation: String) async {
            // Let AppKit process each intermediate state, including deferred
            // tracking-area updates after toolbar and property callbacks.
            view.window!.resetCursorRects()
            view.window!.displayIfNeeded()
            for panel in [toolbar, properties] { panel.contentView!.layoutSubtreeIfNeeded() }
            try? await Task.sleep(nanoseconds: 5_000_000)
            check(controller.isActive, "Annotation session survives \(operation)")
        }
        let original = CGRect(x: 60, y: 60, width: 240, height: 180)
        view.setSelection(original)
        let pixels = view.pixelSelection!
        for drawingTool in [AnnotationTool.pen, .arrow, .rectangle, .text, .number, .mosaic, .magnifier] {
            tap("清空")
            tool(drawingTool)
            let start = CGPoint(x: 110, y: 100), end = CGPoint(x: 180, y: 140)
            canvas.mouseDown(with: event(.leftMouseDown, start, in: canvas))
            if drawingTool == .text {
                canvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "In-place text"
            } else {
                canvas.mouseDragged(with: event(.leftMouseDragged, end, in: canvas))
                canvas.mouseUp(with: event(.leftMouseUp, end, in: canvas))
            }
            await refresh("drawing \(drawingTool)")
            tool(.select)
            await refresh("switching from \(drawingTool) to select")
            check(canvas.annotations.count == 1 && canvas.selectedAnnotation?.tool == drawingTool,
                  "Drawing and text commit select exactly one \(drawingTool) annotation; got \(canvas.annotations.count): \(canvas.annotations.map { $0.text })")
            if drawingTool == .mosaic {
                for style in MosaicStyle.allCases {
                    styles.selectedSegment = style.rawValue
                    styles.sendAction(styles.action!, to: styles.target)
                    await refresh("changing mosaic style to \(style)")
                    check(canvas.selectedAnnotation?.mosaicStyle == style, "Mosaic property callback edits the selected annotation")
                    check(view.renderedSelection()?.width == Int(pixels.width), "Mosaic style \(style) renders at native crop size")
                }
            } else if drawingTool != .magnifier {
                color.onSelect?(.systemGreen)
                width.doubleValue = 9
                width.sendAction(width.action!, to: width.target)
                await refresh("editing color and width of \(drawingTool)")
                check(canvas.selectedAnnotation?.color == .systemGreen && canvas.selectedAnnotation?.lineWidth == 9,
                      "Selected \(drawingTool) supports shared color and width callbacks")
            }
            tap("删除选中标注")
            await refresh("deleting \(drawingTool)")
            check(canvas.annotations.isEmpty, "Delete removes the selected \(drawingTool)")
            tap("撤销")
            await refresh("undoing deletion of \(drawingTool)")
            check(canvas.annotations.count == 1, "Undo restores \(drawingTool)")
            tap("下一步")
            await refresh("redoing deletion of \(drawingTool)")
            check(canvas.annotations.isEmpty && view.pixelSelection == pixels, "Redo preserves the capture frame for \(drawingTool)")
        }
        view.setSelection(CGRect(x: 60, y: 60, width: 40, height: 40))
        let zoomPixels = view.pixelSelection
        tool(.pen)
        for _ in 0..<9 { tap("缩小"); await refresh("zooming a selection below the cursor inset size") }
        check(view.selection!.width < 14 && view.pixelSelection == zoomPixels, "Zoom can make an existing selection narrower than the cursor inset")
        tap("适应")
        for _ in 0..<14 { tap("放大"); await refresh("zooming selection handles outside the screen") }
        check(!view.selection!.intersects(view.bounds) && view.pixelSelection == zoomPixels,
              "Offscreen handles during toolbar zoom do not change the capture pixels")
        tap("适应")

        let handles = [CGPoint(x: original.minX, y: original.minY), CGPoint(x: original.midX, y: original.minY),
                       CGPoint(x: original.maxX, y: original.minY), CGPoint(x: original.maxX, y: original.midY),
                       CGPoint(x: original.maxX, y: original.maxY), CGPoint(x: original.midX, y: original.maxY),
                       CGPoint(x: original.minX, y: original.maxY), CGPoint(x: original.minX, y: original.midY)]
        for (index, handle) in handles.enumerated() {
            view.setSelection(original)
            var end = handle
            if [0, 6, 7].contains(index) { end.x = original.maxX - 2 }
            if [2, 3, 4].contains(index) { end.x = original.minX + 2 }
            if [0, 1, 2].contains(index) { end.y = original.maxY - 2 }
            if [4, 5, 6].contains(index) { end.y = original.minY + 2 }
            drag(view, from: handle, to: end)
            await refresh("shrinking annotation frame with handle \(index)")
            check(view.selection!.width == 2 || view.selection!.height == 2,
                  "Every resize handle can safely shrink the frame below cursor inset size")
        }
        view.setSelection(original)
        tap("吸管：点击图片取色并复制 HEX")
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 110, y: 100), in: canvas))
        await refresh("sampling a color")
        check(!canvas.isPickingColor && NSPasteboard.general.string(forType: .string)?.hasPrefix("#") == true,
              "Eyedropper completes and copies HEX without leaving the session")
        tap("测量：点击两个点量距离（像素）")
        for point in [CGPoint(x: 110, y: 100), CGPoint(x: 180, y: 140)] {
            canvas.mouseDown(with: event(.leftMouseDown, point, in: canvas))
            canvas.mouseUp(with: event(.leftMouseUp, point, in: canvas))
            await refresh("placing measurement endpoints")
        }
        check(canvas.hasMeasurement && !canvas.isMeasuring, "Two measurement clicks complete in-place")
        canvas.cancelOperation(nil)
        check(!canvas.hasMeasurement, "Completed measurements can be cancelled")
    }

    private static func verifyStandaloneEditor() {
        var closed = false
        let editor = AnnotationEditorWindow(image: image(), suggestedName: "regression.png", source: .newCapture) { _ in closed = true }
        editor.makeKeyAndOrderFront(nil)
        let content = editor.contentView!
        content.layoutSubtreeIfNeeded()
        let views = descendants(content)
        let canvas = views.compactMap { $0 as? AnnotationCanvas }.first!
        let picker = views.compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == AnnotationTool.allCases.count - 1 }!
        check(!canvas.usesExportCrop && canvas.exportRegion == nil, "Independent editors keep their original crop model")
        for tool in AnnotationTool.allCases.filter({ $0 != .magnifier }) {
            picker.selectedSegment = tool.rawValue
            picker.sendAction(picker.action!, to: picker.target)
            check(canvas.tool == tool, "Independent editor tool remains connected: \(tool)")
        }
        let buttons = views.compactMap { $0 as? NSButton }
        let ocr = buttons.first { $0.toolTip == L("拖拽框选图片中的文字并复制到剪贴板") }!
        ocr.sendAction(ocr.action!, to: ocr.target)
        check(canvas.recognitionAction == .ocr, "Independent editor routes OCR through the shared commands")
        ocr.sendAction(ocr.action!, to: ocr.target)
        check(canvas.recognitionAction == nil, "Independent editor can cancel OCR selection")
        canvas.tool = .crop
        // Keep endpoints away from integer boundaries: outward pixel rounding must
        // not depend on floating-point round trips through the runner's fit scale.
        let start = canvas.viewPoint(CGPoint(x: 100.25, y: 100.25))
        let end = canvas.viewPoint(CGPoint(x: 499.75, y: 399.75))
        canvas.mouseDown(with: event(.leftMouseDown, start, in: canvas))
        canvas.mouseDragged(with: event(.leftMouseDragged, end, in: canvas))
        canvas.mouseUp(with: event(.leftMouseUp, end, in: canvas))
        check(canvas.baseImage?.width == 400 && canvas.baseImage?.height == 300, "Independent editor crop still changes the base image")
        canvas.undo()
        check(canvas.baseImage?.width == 800, "Independent crop undo restores the original image")
        canvas.redo()
        check(canvas.baseImage?.width == 400, "Independent crop redo remains functional")
        canvas.tool = .text
        let textPoint = canvas.viewPoint(CGPoint(x: 30, y: 40))
        canvas.mouseDown(with: event(.leftMouseDown, textPoint, in: canvas))
        let field = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        field.stringValue = "Shared editor actions"
        let copy = buttons.first { $0.title == L("拷贝") }!
        copy.sendAction(copy.action!, to: copy.target)
        check(canvas.annotations.last?.text == "Shared editor actions", "Independent editor copy commits active text")
        check(canvas.annotations.count == 1, "Independent editor copy commits a focused text field exactly once")
        let bitmap = NSBitmapImageRep(data: NSPasteboard.general.data(forType: .tiff)!)!
        check(bitmap.pixelsWide == 400 && bitmap.pixelsHigh == 300, "Independent editor copy preserves cropped native dimensions")
        check(closed && !editor.isVisible, "Shared copy command retains the independent window close lifecycle")
    }

    private static func verifySession() async {
        let controller = InlineScreenshotController.shared
        let screens = NSScreen.screens
        let snapshots = screens.map { screen in
            (screen, image(width: Int(screen.frame.width * 2), height: Int(screen.frame.height * 2)))
        }
        let screen = screens[0]
        controller.present(snapshots: snapshots, intent: .displayOnly, pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        check(controller.isActive, "Open a frozen screenshot session")
        for _ in 0..<3 { try? await Task.sleep(nanoseconds: 50_000_000) }
        let overlays = NSApp.windows.filter { $0.isVisible && $0.contentView is InlineScreenshotView }
        check(overlays.count == screens.count, "Freeze every display, including displays with negative origins")
        let view = overlays.first { $0.frame == screen.frame }!.contentView as! InlineScreenshotView
        check(view.selection == view.bounds, "Full-screen capture starts with the whole target display selected: \(String(describing: view.selection)) vs \(view.bounds), canvas=\(view.canvas.bounds)")
        view.setSelection(CGRect(x: 60, y: 60, width: 360, height: 240))
        let panel = NSApp.windows.first { window in
            window.isVisible && window.identifier?.rawValue == "inline.tools"
        }!
        check(screen.visibleFrame.contains(panel.frame), "Toolbar stays inside the selected display")
        check(abs(panel.frame.minY - screen.visibleFrame.minY - 18) < 1, "Main toolbar docks to screen bottom")
        let initialFrame = panel.frame
        view.setSelection(CGRect(x: 100, y: 100, width: 260, height: 200))
        check(panel.frame == initialFrame, "Resizing selection does not make the toolbar chase it")
        view.setSelection(CGRect(x: 60, y: 60, width: 360, height: 240))
        let rail = NSApp.windows.first { $0.identifier?.rawValue == "inline.quick" && $0.isVisible }!
        check(abs(rail.frame.maxX - screen.visibleFrame.maxX + 18) < 1, "Quick actions dock to the screen's right side")
        check(descendants(rail.contentView!).compactMap { $0 as? NSButton }.count == 5,
              "OCR, QR, translation, AI and upload all appear on the quick rail")
        let picker = descendants(panel.contentView!).compactMap { $0 as? NSSegmentedControl }.first!
        check(picker.segmentCount == AnnotationTool.allCases.count - 1, "All regular tools, including crop, are available")
        for tool in AnnotationTool.allCases.filter({ $0 != .magnifier }) {
            picker.selectedSegment = tool.rawValue
            picker.sendAction(picker.action!, to: picker.target)
            check(view.canvas.tool == tool, "Tool parity: \(tool)")
        }
        picker.selectedSegment = 1
        picker.sendAction(picker.action!, to: picker.target)
        check(view.canvas.tool == .pen && !view.adjustingSelection, "Toolbar switches from selection to drawing")
        let railButtons = descendants(rail.contentView!).compactMap { $0 as? NSButton }.sorted { $0.tag < $1.tag }
        for (index, action) in [AnnotationCanvas.RecognitionAction.ocr, .barcode, .translate].enumerated() {
            let button = railButtons[index]
            button.sendAction(button.action!, to: button.target)
            check(view.canvas.recognitionAction == action && !view.adjustingSelection, "Quick action reuses region recognition: \(action)")
            button.sendAction(button.action!, to: button.target)
            check(view.canvas.recognitionAction == nil, "Pressing the active recognition tool cancels it")
        }

        panel.contentView!.layoutSubtreeIfNeeded()
        let controls = descendants(panel.contentView!).compactMap { $0 as? NSControl }
        check(controls.allSatisfy { control in
            panel.contentView!.bounds.insetBy(dx: 8, dy: 4).contains(control.convert(control.bounds, to: panel.contentView))
        }, "Toolbar controls and dimension label fit without clipping")
        let propertyPanel = NSApp.windows.first { $0.identifier?.rawValue == "inline.properties" && $0.isVisible }!
        let magnifier = controls.compactMap { $0 as? NSButton }.first { $0.toolTip == L("放大镜：拖出圆形区域，将其中的图片放大 2 倍") }!
        magnifier.sendAction(magnifier.action!, to: magnifier.target)
        check(view.canvas.tool == .magnifier && !view.adjustingSelection, "Magnifier uses the shared canvas tool")
        check(!propertyPanel.isVisible, "Tools without configurable drawing properties hide the property strip")
        let eyedropper = controls.compactMap { $0 as? NSButton }.first { $0.toolTip == L("吸管：点击图片取色并复制 HEX") }!
        eyedropper.sendAction(eyedropper.action!, to: eyedropper.target)
        check(view.canvas.isPickingColor, "Eyedropper is available in-place")
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: view.window!.windowNumber, context: nil,
                                     characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        check(controller.handleKeyDown(escape) == nil, "The session consumes transient Escape commands")
        check(!view.canvas.isPickingColor && controller.isActive, "Escape cancels a transient operation before closing the session")
        let measure = controls.compactMap { $0 as? NSButton }.first { $0.toolTip == L("测量：点击两个点量距离（像素）") }!
        measure.sendAction(measure.action!, to: measure.target)
        check(view.canvas.isMeasuring, "Measurement is available in-place")
        view.canvas.cancelOperation(nil)
        let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: view.window!.windowNumber, context: nil,
                                  characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        check(controller.handleKeyDown(tab) == nil, "The session consumes Tab commands")
        check(!panel.isVisible && !rail.isVisible, "Tab hides the docks without ending annotation")
        check(controller.handleKeyDown(tab) == nil, "The session consumes Tab commands")
        check(panel.isVisible && rail.isVisible, "Tab restores the docks")
        let colors = descendants(propertyPanel.contentView!).compactMap { $0 as? AnnotationColorPicker }.first!
        check(colors.willPresentDialog != nil && colors.didDismissDialog != nil, "Custom HEX dialogs have overlay suspension hooks")
        colors.willPresentDialog?()
        check(!panel.isVisible && !view.window!.isVisible, "Dialogs hide both frozen screen and controls")
        view.canvas.zoomIn()
        check(!panel.isVisible, "Canvas callbacks cannot reveal controls while a dialog is active")
        colors.didDismissDialog?()
        check(panel.isVisible && view.window!.isVisible, "Dismissing a dialog restores the frozen editing session")
        view.canvas.resetZoom()
        picker.selectedSegment = AnnotationTool.pen.rawValue
        picker.sendAction(picker.action!, to: picker.target)

        check(propertyPanel.frame.minY > panel.frame.maxY, "Drawing properties float above the bottom dock")
        picker.selectedSegment = AnnotationTool.rectangle.rawValue
        picker.sendAction(picker.action!, to: picker.target)
        view.canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 120, y: 110), in: view.canvas))
        view.canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 230, y: 190), in: view.canvas))
        view.canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 230, y: 190), in: view.canvas))
        picker.selectedSegment = AnnotationTool.select.rawValue
        picker.sendAction(picker.action!, to: picker.target)
        check(propertyPanel.isVisible && view.canvas.selectedAnnotation?.tool == .rectangle,
              "Selecting an existing annotation retains editable contextual properties")
        let widthControl = descendants(propertyPanel.contentView!).compactMap { $0 as? NSSlider }.first { $0.maxValue == 20 }!
        widthControl.doubleValue = 7
        widthControl.sendAction(widthControl.action!, to: widthControl.target)
        check(view.canvas.selectedAnnotation?.lineWidth == 7, "Contextual properties edit existing annotations, not only new drawings")
        picker.selectedSegment = AnnotationTool.mosaic.rawValue
        picker.sendAction(picker.action!, to: picker.target)
        let styles = descendants(propertyPanel.contentView!).compactMap { $0 as? NSSegmentedControl }.first!
        check(styles.segmentCount == MosaicStyle.allCases.count, "Every mosaic style is available")
        for style in MosaicStyle.allCases {
            styles.selectedSegment = style.rawValue
            styles.sendAction(styles.action!, to: styles.target)
            check(view.canvas.mosaicStyle == style, "Mosaic style parity: \(style)")
        }
        picker.selectedSegment = AnnotationTool.pen.rawValue
        picker.sendAction(picker.action!, to: picker.target)
        if let destination = ProcessInfo.processInfo.environment["SAKURA_INLINE_PREVIEW_DIR"], !destination.isEmpty {
            try! FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            for (name, content) in [("toolbar", panel.contentView!), ("quick", rail.contentView!),
                                    ("properties", propertyPanel.contentView!), ("selection", view)] {
                content.layoutSubtreeIfNeeded()
                let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent("\(name).png"))
            }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for window in overlays + [panel, rail, propertyPanel] { window.appearance = NSAppearance(named: appearance) }
                let composite = NSImage(size: view.bounds.size, flipped: true) { _ in
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size).draw(in: view.bounds)
                    for dock in [panel, rail, propertyPanel] {
                        let content = dock.contentView!
                        content.layoutSubtreeIfNeeded()
                        let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                        content.cacheDisplay(in: content.bounds, to: rep)
                        let frame = dock.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                        let rect = CGRect(x: frame.minX, y: view.bounds.height - frame.maxY, width: frame.width, height: frame.height)
                        NSImage(cgImage: rep.cgImage!, size: rect.size).draw(in: rect)
                    }
                    return true
                }
                let bitmap = NSBitmapImageRep(data: composite.tiffRepresentation!)!
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent("layout-\(appearance.rawValue).png"))
            }
        }
        let pasteboard = NSPasteboard.general
        let previousItems = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            let restored = previousItems.map { entries in
                let item = NSPasteboardItem()
                entries.forEach { item.setData($0.1, forType: $0.0) }
                return item
            }
            pasteboard.writeObjects(restored)
        }
        let copy = controls.compactMap { $0 as? NSButton }.first { $0.title == L("拷贝") }!
        copy.sendAction(copy.action!, to: copy.target)
        let copied = NSBitmapImageRep(data: pasteboard.data(forType: .tiff)!)!
        check(copied.pixelsWide == 720 && copied.pixelsHigh == 480, "Copy exports the selected image at native resolution")
        check(!controller.isActive, "Closing clears the session")
        check(!overlays.contains(where: \.isVisible) && !panel.isVisible && !rail.isVisible && !propertyPanel.isVisible, "Closing removes all overlays and the toolbar")
        controller.present(snapshots: snapshots, intent: .regionOnly, pointer: .zero)
        let fresh = NSApp.windows.compactMap { $0.isVisible ? $0.contentView as? InlineScreenshotView : nil }
        check(fresh.allSatisfy { $0.selection == nil && $0.canvas.annotations.isEmpty }, "Region capture starts fresh, without an editor window")
        let region = fresh[0]
        let anchor = CGPoint(x: 100, y: 100)
        for direction in [CGFloat(1), -1] {
            region.setSelection(nil)
            region.mouseDown(with: event(.leftMouseDown, anchor, in: region))
            for distance in [CGFloat(0), 1, 2, 4, 8, 13, 14, 20, 60] {
                let point = CGPoint(x: anchor.x + distance * direction, y: anchor.y + distance * direction)
                region.mouseDragged(with: event(.leftMouseDragged, point, in: region))
                region.resetCursorRects()
                region.window!.resetCursorRects()
                try? await Task.sleep(nanoseconds: 10_000_000)
                check(controller.isActive, "Region capture survives cursor refresh during a \(distance)-point drag")
            }
            region.mouseUp(with: event(.leftMouseUp, CGPoint(x: anchor.x + 60 * direction, y: anchor.y + 60 * direction), in: region))
            check(region.selection?.width == 60 && region.selection?.height == 60,
                  "Forward and reverse region drags still complete after small intermediate selections")
        }
        await verifyAnnotationInteractions(region)
        let clipboardChange = pasteboard.changeCount
        controller.close()
        check(pasteboard.changeCount == clipboardChange, "Cancel does not change the clipboard")
        verifyStandaloneEditor()
    }
}
