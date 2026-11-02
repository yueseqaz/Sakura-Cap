import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 模型

enum AnnotationTool: Int, CaseIterable, Identifiable {
    case select = 0, pen = 1, arrow = 2, rectangle = 3, ellipse = 4, text = 5,
         number = 6, mosaic = 7, crop = 8, magnifier = 9

    var id: Int { rawValue }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "text.alignleft"
        case .number: return "1.circle"
        case .mosaic: return "square.grid.3x3.fill"
        case .crop: return "crop"
        case .magnifier: return "plus.magnifyingglass"
        }
    }

    var label: String {
        switch self {
        case .select: return L("选择标注")
        case .pen: return L("画笔")
        case .arrow: return L("箭头")
        case .rectangle: return L("矩形")
        case .text: return L("文字")
        case .number: return L("序号")
        case .mosaic: return L("马赛克")
        case .crop: return L("裁剪")
        case .magnifier: return L("放大镜")
        case .ellipse: return L("椭圆")
        }
    }

    /// Shared order keeps the shape tools together in every toolbar.
    static let toolbarCases: [AnnotationTool] = [
        .select, .pen, .arrow, .rectangle, .ellipse, .text, .number, .mosaic, .crop, .magnifier
    ]

    /// 直播覆盖层可用（裁剪只用于图片编辑）
    var availableLive: Bool { self != .crop && self != .magnifier }
}

enum MosaicStyle: Int, CaseIterable, Identifiable {
    case pixelate, blur, hexagon

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .pixelate: return L("像素块")
        case .blur: return L("模糊")
        case .hexagon: return L("六边形")
        }
    }
}

/// 一条标注，坐标一律用「图片坐标（像素，左上原点）」，与显示缩放无关。
struct Annotation: Equatable {
    var tool: AnnotationTool
    var points: [CGPoint]
    var text: String = ""
    /// Width of a text box in source-image coordinates. Keeping this width
    /// with the annotation preserves the editor's soft wrapping after commit.
    var textWidth: CGFloat? = nil
    /// Explicit font size in source-image points. Older annotations fall back
    /// to their historical lineWidth-derived size when this is nil.
    var fontSize: CGFloat? = nil
    var color: NSColor
    var mosaicStyle: MosaicStyle = .pixelate
    var mosaicStrength: CGFloat = 4
    var lineWidth: CGFloat = 4
    /// Solid rectangle/ellipse mode. Old annotations default to outline.
    var isFilled: Bool = false

    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.tool == rhs.tool && lhs.points == rhs.points && lhs.text == rhs.text
            && lhs.textWidth == rhs.textWidth && lhs.fontSize == rhs.fontSize
            && lhs.mosaicStyle == rhs.mosaicStyle
            && lhs.mosaicStrength == rhs.mosaicStrength && lhs.lineWidth == rhs.lineWidth
            && lhs.isFilled == rhs.isFilled
            && lhs.color.isEqual(rhs.color)
    }
}

// MARK: - 画布

/// 通用标注画布：可带底图（图片编辑）或不带（直播覆盖层）。
/// 支持 画笔/箭头/矩形/文字/序号/马赛克/裁剪，以及撤销、重做。
final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    var tool: AnnotationTool = .select {
        didSet {
            // A direct toolbar switch should keep the requested tool. Text
            // commits triggered by focus loss switch back to selection below.
            commitActiveField(switchToSelection: false)
            // 切换到绘制工具时清掉选中，避免下一个图形先被当成“编辑旧标注”
            if tool != .select {
                endWatermarkEditing()
                selectedIndex = nil
                // A toolbar switch is an explicit new action, so it should
                // not consume its first click as text-selection confirmation.
                awaitingTextSelectionClick = false
            }
            cancelTransient()
            needsDisplay = true
        }
    }
    var color: NSColor = .systemRed
    var mosaicStyle: MosaicStyle = .pixelate
    var mosaicStrength: CGFloat = 4
    var lineWidth: CGFloat = 4
    var shapeFilled: Bool = false
    var textFontSize: CGFloat = 28
    var measurementScale: CGFloat = 1
    var allowCrop = true
    var allowsImageNavigation = true
    // In-place captures keep the frozen desktop and its coordinates intact when cropping.
    var usesExportCrop = false
    var exportRegion: CGRect?
    /// Video annotation uses this canvas over an AVPlayer frame, so the frame
    /// supplies dimensions and mosaic samples without being painted twice.
    var showsBaseImage = true

    /// 底图（图片编辑时提供；直播覆盖层为 nil）
    var baseImage: CGImage? {
        didSet {
            if oldValue?.width != baseImage?.width || oldValue?.height != baseImage?.height {
                zoom = 1
                panOffset = .zero
            }
            needsDisplay = true
        }
    }
    /// 直播覆盖层用：截取某区域「本窗口之下」的画面，供马赛克取样
    var captureSource: ((CGRect) -> CGImage?)?
    /// Optional watermark rendered above the base image and below drawing annotations.
    var watermark: WatermarkConfiguration? {
        didSet {
            updateWatermarkFieldFrame()
            needsDisplay = true
        }
    }

    /// 变更回调（用于刷新撤销/重做按钮状态、编辑器脏标记）
    var onChange: (() -> Void)?
    var onMeasurementCompleted: (() -> Void)?

    private(set) var annotations: [Annotation] = []
    private var current: Annotation?
    private struct Snapshot {
        let baseImage: CGImage?
        let annotations: [Annotation]
        let watermark: WatermarkConfiguration?
        let exportRegion: CGRect?
        let restoresExportRegion: Bool
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var activeField: NSTextField?
    private var watermarkField: NSTextField?
    private var watermarkFieldImageRect: CGRect?
    private var pendingTextPoint: CGPoint = .zero
    private var awaitingTextSelectionClick = false
    private(set) var cropRect: CGRect? // 图片坐标
    private var cropAnchor: CGPoint?

    // 一次性识别框选（图片坐标）
    enum RecognitionAction: Int { case ocr, barcode, translate }
    var onRecognitionSelection: ((RecognitionAction, CGRect) -> Void)?
    private(set) var recognitionAction: RecognitionAction?
    private var ocrRect: CGRect?
    private var ocrAnchor: CGPoint?

    // 吸管 / 测量（一次性）
    var onColorPicked: ((NSColor) -> Void)?
    private(set) var isPickingColor = false
    private(set) var isMeasuring = false
    private var measureStart: CGPoint?
    private var measureEnd: CGPoint?
    private enum MeasureDrag { case start, end }
    private var measureDrag: MeasureDrag?
    var hasMeasurement: Bool { measureStart != nil }
    private var hoverColor: NSColor?
    private var hoverPoint: CGPoint?

    // 选中/编辑
    private var selectedIndex: Int?
    private var dragState: DragState = .none
    private var dragLast: CGPoint = .zero
    private struct TextResizeStart {
        let index: Int
        let handle: Int
        let rect: CGRect
        let fontSize: CGFloat
        let textWidth: CGFloat
    }
    private var textResizeStart: TextResizeStart?
    private var panning = false
    private var panStartView: CGPoint = .zero
    private var panStartOffset: CGPoint = .zero
    private enum DragState: Equatable { case none, move, handle(Int) }
    private enum WatermarkDrag { case move, rotate, resize(Int), sphere }
    private var watermarkEditing = false
    private var watermarkDrag: WatermarkDrag?
    private var watermarkDragOffset: CGPoint = .zero
    private var watermarkDragStartScale: CGFloat = 1
    private var watermarkDragStartDistance: CGFloat = 1
    private var watermarkSphereStartPoint: CGPoint = .zero
    private var watermarkSphereStartRotation: CGFloat = 0
    private var watermarkSphereStartTilt: CGFloat = 0
    private var watermarkSphereStartSpacing: CGFloat = 1.8

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedAnnotation: Annotation? {
        guard let selectedIndex else { return nil }
        return annotations[safe: selectedIndex]
    }

    var currentTextFontSize: CGFloat {
        if let selected = selectedAnnotation, selected.tool == .text {
            return min(112, selected.fontSize ?? selected.lineWidth * 7)
        }
        return min(112, textFontSize)
    }

    static let textFontSizes: [CGFloat] = [12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 72,
                                            84, 96, 112]

    /// 当前应显示的马赛克程度：选中的马赛克优先，否则用工具默认值
    var currentMosaicStrength: CGFloat {
        if let index = selectedIndex, annotations.indices.contains(index), annotations[index].tool == .mosaic {
            return annotations[index].mosaicStrength
        }
        return mosaicStrength
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        if recognitionAction != nil || isPickingColor || isMeasuring || measureStart != nil { addCursorRect(bounds, cursor: .crosshair) }
    }

    override func cancelOperation(_ sender: Any?) { cancelTransient() }

    override func keyDown(with event: NSEvent) {
        // 53 = Esc
        if event.keyCode == 53, recognitionAction != nil || isPickingColor || isMeasuring || measureStart != nil {
            cancelTransient()
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if modifiers.contains(.shift) { redo() } else { undo() }
            return
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "y" {
            redo()
            return
        }
        super.keyDown(with: event)
    }

    private func cancelTransient() {
        endRecognitionSelection()
        endColorPick()
        endMeasure()
    }

    // MARK: 识别框选

    func beginRecognitionSelection(_ action: RecognitionAction) {
        leaveMagnifierMode()
        cancelTransient()
        recognitionAction = action
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func endRecognitionSelection() {
        guard recognitionAction != nil || ocrRect != nil else { return }
        recognitionAction = nil
        ocrRect = nil
        ocrAnchor = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: 吸管 / 测量

    func beginColorPick() {
        leaveMagnifierMode()
        cancelTransient()
        isPickingColor = true
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func endColorPick() {
        guard isPickingColor || hoverPoint != nil else { return }
        isPickingColor = false
        hoverColor = nil
        hoverPoint = nil
        window?.acceptsMouseMovedEvents = false
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func beginMeasure() {
        leaveMagnifierMode()
        cancelTransient()
        isMeasuring = true
        measureStart = nil
        measureEnd = nil
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    /// Utility modes take over the canvas, so the magnifier must not remain
    /// visually selected while color picking, measuring, or selecting OCR.
    func leaveMagnifierMode() {
        if tool == .magnifier { tool = .select }
    }

    func endMeasure() {
        guard isMeasuring || measureStart != nil else { return }
        isMeasuring = false
        measureStart = nil
        measureEnd = nil
        measureDrag = nil
        window?.acceptsMouseMovedEvents = false
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// 读取底图某点的像素颜色（图片坐标）
    private func colorAt(imagePoint point: CGPoint) -> NSColor? {
        guard let baseImage else { return nil }
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < baseImage.width, y < baseImage.height else { return nil }
        let rep = NSBitmapImageRep(cgImage: baseImage)
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
    }

    // MARK: 坐标换算（图片像素 ↔ 视图）

    /// 缩放倍数（1 = 适应窗口）；滚轮/按钮调整
    var zoom: CGFloat = 1
    private var panOffset: CGPoint = .zero

    private var imageSize: CGSize {
        if let baseImage { return CGSize(width: baseImage.width, height: baseImage.height) }
        return bounds.size
    }

    private var textBounds: CGRect {
        // Keep text layout independent from the live crop rectangle. Resizing
        // a selection must not reflow or hide characters that are already on
        // the canvas; export cropping clips the final bitmap afterward.
        CGRect(origin: .zero, size: imageSize)
    }

    private var fitScale: CGFloat {
        let size = imageSize
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        // Never enlarge a small region screenshot in the editor. It is a
        // preview choice only; export remains at the source pixel dimensions.
        return min(1, min(bounds.width / size.width, bounds.height / size.height))
    }

    private var displayScale: CGFloat { fitScale * zoom }

    private var baseDisplayOrigin: CGPoint {
        let size = imageSize
        let scale = displayScale
        return CGPoint(x: (bounds.width - size.width * scale) / 2,
                       y: (bounds.height - size.height * scale) / 2)
    }

    private var displayOrigin: CGPoint {
        CGPoint(x: baseDisplayOrigin.x + panOffset.x, y: baseDisplayOrigin.y + panOffset.y)
    }

    func zoomIn() { zoomBy(1.25) }
    func zoomOut() { zoomBy(0.8) }
    func resetZoom() {
        finishTextEditing()
        zoom = 1
        panOffset = .zero
        needsDisplay = true
        onChange?()
    }

    private func zoomBy(_ factor: CGFloat) {
        zoom(at: CGPoint(x: bounds.midX, y: bounds.midY), factor: factor)
    }

    /// 以某个视图点为锚点缩放（保持该点下的图像不动）
    func zoom(at viewPoint: CGPoint, factor: CGFloat) {
        finishTextEditing()
        // Keep zoom centered on the image rather than following the cursor.
        // This makes toolbar, trackpad and wheel zoom behave consistently.
        zoom = min(20, max(0.2, zoom * factor))
        panOffset = .zero
        needsDisplay = true
        onChange?()
    }

    override func scrollWheel(with event: NSEvent) {
        guard allowsImageNavigation else { return }
        if event.modifierFlags.contains(.command) {
            finishTextEditing()
            // ⌘ + 滚轮：平移画面
            panOffset.x += event.scrollingDeltaX
            panOffset.y += event.scrollingDeltaY
            needsDisplay = true
            onChange?()
        } else {
            // 单独滚轮：缩放
            let factor = min(1.18, max(0.85, pow(1.02, event.scrollingDeltaY)))
            zoom(at: CGPoint(x: bounds.midX, y: bounds.midY), factor: factor)
        }
    }

    override func magnify(with event: NSEvent) {
        guard allowsImageNavigation else { return }
        zoom(at: CGPoint(x: bounds.midX, y: bounds.midY), factor: 1 + event.magnification)
    }

    func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
        let scale = displayScale
        let origin = displayOrigin
        return CGPoint(x: (viewPoint.x - origin.x) / scale, y: (viewPoint.y - origin.y) / scale)
    }

    private func isInsideImage(_ point: CGPoint) -> Bool {
        let size = imageSize
        return point.x >= 0 && point.y >= 0 && point.x <= size.width && point.y <= size.height
    }

    func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        let scale = displayScale
        let origin = displayOrigin
        return CGPoint(x: imagePoint.x * scale + origin.x, y: imagePoint.y * scale + origin.y)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        if showsBaseImage, let baseImage {
            NSImage(cgImage: baseImage, size: imageSize)
                .draw(in: NSRect(origin: displayOrigin, size: CGSize(width: imageSize.width * displayScale,
                                                                     height: imageSize.height * displayScale)))
        }
        if let watermark, let image = WatermarkRenderer.image(for: watermark, size: imageSize),
           let canvasImage = WatermarkRenderer.verticallyFlipped(image) {
            NSImage(cgImage: canvasImage, size: imageSize)
                .draw(in: NSRect(origin: displayOrigin, size: CGSize(width: imageSize.width * displayScale,
                                                                     height: imageSize.height * displayScale)),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }
        if watermarkEditing, watermark != nil { drawWatermarkSelection() }
        var all = annotations
        if let current { all.append(current) }
        for annotation in all { draw(annotation) }
        if let index = selectedIndex, annotations.indices.contains(index) {
            drawSelection(annotations[index])
        }
        if let cropRect, tool == .crop { drawCropOverlay(cropRect) }
        if recognitionAction != nil { drawOCRSelection() }
        if let a = measureStart, let b = measureEnd { drawMeasure(from: a, to: b) }
        if isPickingColor { drawColorPickOverlay() }
    }

    private func draw(_ annotation: Annotation) {
        switch annotation.tool {
        case .pen:
            guard annotation.points.count > 1 else { return }
            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: viewPoint(annotation.points[0]))
            for point in annotation.points.dropFirst() { path.line(to: viewPoint(point)) }
            annotation.color.setStroke()
            path.stroke()
        case .arrow:
            guard annotation.points.count >= 2 else { return }
            drawArrow(from: viewPoint(annotation.points[0]), to: viewPoint(annotation.points[1]),
                      color: annotation.color, lineWidth: annotation.lineWidth)
        case .rectangle, .ellipse:
            guard annotation.points.count >= 2 else { return }
            let a = viewPoint(annotation.points[0]), b = viewPoint(annotation.points[1])
            let rect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            let path = annotation.tool == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            if annotation.isFilled {
                annotation.color.setFill()
                path.fill()
            } else {
                path.lineWidth = annotation.lineWidth
                annotation.color.setStroke()
                path.stroke()
            }
        case .text:
            guard let point = annotation.points.first else { return }
            let layout = textLayout(for: annotation.text, at: point, lineWidth: annotation.lineWidth,
                                    textWidth: annotation.textWidth, fontSize: annotation.fontSize)
            guard !layout.rect.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: layout.font,
                .foregroundColor: annotation.color,
                .paragraphStyle: textParagraphStyle,
            ]
            let viewRect = NSRect(origin: viewPoint(layout.rect.origin),
                                   size: CGSize(width: layout.rect.width * displayScale,
                                                height: layout.rect.height * displayScale))
            // Keep annotation text inside the source image, including when a
            // user starts typing close to an edge or drags it past the edge.
            NSGraphicsContext.saveGraphicsState()
            let imageRect = NSRect(origin: viewPoint(.zero),
                                    size: CGSize(width: imageSize.width * displayScale,
                                                 height: imageSize.height * displayScale))
            NSBezierPath(rect: imageRect).addClip()
            // In a flipped view AppKit lays the first line's glyphs slightly
            // above the drawing rect. Give it a real screen-space safety area
            // (small source fonts still need a few pixels when zoomed out),
            // then keep that expanded rect inside the image clip.
            let topPadding = max(4, ceil(layout.font.ascender * 0.18))
            let bottomPadding = max(4, ceil(abs(layout.font.descender) * 0.35))
            var contentRect = viewRect.offsetBy(dx: 0, dy: topPadding)
            contentRect.size.height += topPadding + bottomPadding
            if contentRect.maxY > imageRect.maxY {
                contentRect.origin.y -= contentRect.maxY - imageRect.maxY
            }
            if contentRect.minY < imageRect.minY {
                contentRect.origin.y = imageRect.minY
            }
            NSAttributedString(string: annotation.text, attributes: attributes)
                .draw(with: contentRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()
        case .number:
            guard let point = annotation.points.first else { return }
            drawNumber(annotation.text, at: viewPoint(point), color: annotation.color)
        case .mosaic:
            drawMosaic(annotation)
        case .magnifier:
            drawMagnifier(annotation)
        case .crop, .select:
            break
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        color.setStroke()
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(14, lineWidth * 5)
        let spread: CGFloat = .pi / 7
        let head = NSBezierPath()
        head.lineWidth = lineWidth
        head.lineCapStyle = .round
        head.move(to: CGPoint(x: end.x - cos(angle - spread) * length, y: end.y - sin(angle - spread) * length))
        head.line(to: end)
        head.line(to: CGPoint(x: end.x - cos(angle + spread) * length, y: end.y - sin(angle + spread) * length))
        color.setStroke()
        head.stroke()
    }

    private func drawNumber(_ text: String, at point: CGPoint, color: NSColor) {
        let radius: CGFloat = 18
        let circle = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius,
                                                 width: radius * 2, height: radius * 2))
        color.setFill()
        circle.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

    private func drawMosaic(_ annotation: Annotation) {
        guard annotation.points.count >= 2 else { return }
        let region = imageRect(annotation.points[0], annotation.points[1])
        let viewRect = NSRect(origin: viewPoint(region.origin),
                              size: CGSize(width: region.width * displayScale, height: region.height * displayScale))
        if let image = mosaicImage(region: region, style: annotation.mosaicStyle, strength: annotation.mosaicStrength) {
            image.draw(in: viewRect)
        } else {
            // 取不到取样时画一层半透明遮盖，至少挡住内容
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(rect: viewRect).fill()
        }
    }

    private func drawMagnifier(_ annotation: Annotation) {
        guard let baseImage, annotation.points.count >= 2 else { return }
        let region = imageRect(annotation.points[0], annotation.points[1])
        let diameter = min(region.width, region.height)
        guard diameter >= 2 else { return }
        let circle = CGRect(x: region.minX, y: region.minY, width: diameter, height: diameter)
        let viewRect = NSRect(origin: viewPoint(circle.origin),
                              size: CGSize(width: diameter * displayScale, height: diameter * displayScale))
        let sampleSize = diameter / 2
        let sample = CGRect(x: circle.midX - sampleSize / 2, y: circle.midY - sampleSize / 2,
                            width: sampleSize, height: sampleSize)
            .intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        guard let pixels = baseImage.cropping(to: sample.integral) else { return }
        let path = NSBezierPath(ovalIn: viewRect)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSImage(cgImage: pixels, size: sample.size).draw(in: viewRect)
        NSGraphicsContext.restoreGraphicsState()
        path.lineWidth = max(2, annotation.lineWidth * displayScale)
        annotation.color.setStroke()
        path.stroke()
    }

    private func drawCropOverlay(_ rect: CGRect) {
        let viewRect = NSRect(origin: viewPoint(rect.origin),
                              size: CGSize(width: rect.width * displayScale, height: rect.height * displayScale))
        let mask = NSBezierPath(rect: bounds)
        mask.append(NSBezierPath(rect: viewRect))
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        mask.fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: viewRect)
        border.lineWidth = 1.5
        border.stroke()
    }

    private func drawColorPickOverlay() {
        guard let hover = hoverPoint else { return }
        let vp = viewPoint(hover)
        let hex = hoverColor.map { hexString($0) } ?? "--"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: hex, attributes: attrs)
        let textSize = text.size()
        let pad: CGFloat = 8
        let swatch: CGFloat = 18
        let boxW = swatch + textSize.width + pad * 2 + 6
        let boxH = max(swatch, textSize.height) + pad
        var box = NSRect(x: vp.x + 14, y: vp.y - boxH / 2, width: boxW, height: boxH)
        if box.maxX > bounds.maxX - 4 { box.origin.x = vp.x - 14 - boxW }
        if box.minY < 4 { box.origin.y = 4 }
        if box.maxY > bounds.maxY - 4 { box.origin.y = bounds.maxY - 4 - boxH }
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        if let color = hoverColor {
            let swatchRect = NSRect(x: box.minX + pad, y: box.minY + (box.height - swatch) / 2, width: swatch, height: swatch)
            color.setFill()
            NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).fill()
            NSColor.white.withAlphaComponent(0.45).setStroke()
            let border = NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4)
            border.lineWidth = 0.5
            border.stroke()
        }
        text.draw(at: NSPoint(x: box.minX + pad + swatch + 6, y: box.minY + (box.height - textSize.height) / 2))
    }

    private func hexString(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    private func drawMeasure(from a: CGPoint, to b: CGPoint) {
        let pa = viewPoint(a), pb = viewPoint(b)
        let line = NSBezierPath()
        line.move(to: pa)
        line.line(to: pb)
        line.lineWidth = 2
        line.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        line.stroke()

        for p in [pa, pb] {
            let dot = NSBezierPath(ovalIn: NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            NSColor.white.setFill()
            dot.fill()
            NSColor.controlAccentColor.setStroke()
            dot.lineWidth = 2
            dot.stroke()
        }

        let dx = Int((abs(b.x - a.x) * measurementScale).rounded())
        let dy = Int((abs(b.y - a.y) * measurementScale).rounded())
        let distance = Int((hypot(b.x - a.x, b.y - a.y) * measurementScale).rounded())
        let mainAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ]
        let main = NSAttributedString(string: "\(distance) px", attributes: mainAttrs)
        let sub = NSAttributedString(string: "Δx \(dx)  Δy \(dy)", attributes: subAttrs)
        let mainSize = main.size(), subSize = sub.size()
        let pad: CGFloat = 7
        let boxW = max(mainSize.width, subSize.width) + pad * 2
        let boxH = mainSize.height + subSize.height + pad * 1.4
        let mid = NSPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
        var box = NSRect(x: mid.x + 12, y: mid.y - boxH / 2, width: boxW, height: boxH)
        if box.maxX > bounds.maxX - 4 { box.origin.x = mid.x - 12 - boxW }
        if box.minY < 4 { box.origin.y = 4 }
        if box.maxY > bounds.maxY - 4 { box.origin.y = bounds.maxY - 4 - boxH }
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        main.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad * 0.7))
        sub.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad * 0.7 + mainSize.height))
    }

    private func drawOCRSelection() {
        // 顶部提示
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: L("拖拽框选要识别的文字（Esc 取消）"), attributes: attrs)
        let textSize = string.size()
        let pad: CGFloat = 8
        let box = NSRect(x: bounds.midX - textSize.width / 2 - pad, y: 10,
                         width: textSize.width + pad * 2, height: textSize.height + pad * 1.5)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        string.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad * 0.75))

        // 选区边框
        if let ocrRect {
            let viewRect = NSRect(origin: viewPoint(ocrRect.origin),
                                  size: CGSize(width: ocrRect.width * displayScale, height: ocrRect.height * displayScale))
            let border = NSBezierPath(rect: viewRect)
            border.lineWidth = 1.5
            let pattern: [CGFloat] = [5, 3]
            border.setLineDash(pattern, count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            border.stroke()
        }
    }

    private func imageRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: 选中 / 编辑

    private func handlePoints(_ a: Annotation) -> [CGPoint] {
        switch a.tool {
        case .pen, .select, .crop: return []
        case .text:
            guard let point = a.points.first else { return [] }
            let rect = textLayout(for: a.text, at: point, lineWidth: a.lineWidth,
                                  textWidth: a.textWidth, fontSize: a.fontSize).rect
            return [CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.maxY)]
        case .number: return a.points.first.map { [$0] } ?? []
        default: return a.points.count >= 2 ? [a.points[0], a.points[1]] : []
        }
    }

    private func boundingBox(_ a: Annotation) -> CGRect {
        switch a.tool {
        case .pen:
            guard let first = a.points.first else { return .zero }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in a.points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -8, dy: -8)
        case .text:
            guard let p = a.points.first else { return .zero }
            return textLayout(for: a.text, at: p, lineWidth: a.lineWidth,
                              textWidth: a.textWidth, fontSize: a.fontSize)
                .rect.insetBy(dx: -4, dy: -4)
        case .number:
            guard let p = a.points.first else { return .zero }
            return CGRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40)
        default:
            guard a.points.count >= 2 else { return .zero }
            return imageRect(a.points[0], a.points[1]).insetBy(dx: -8, dy: -8)
        }
    }

    private enum EditHit { case handle(Int), body, miss }

    /// 命中当前选中标注的可编辑区域：先看控制点，再看图形本体。
    private func editHit(on annotation: Annotation, at point: CGPoint) -> EditHit {
        let radius = 12 / max(displayScale, 0.01)
        for (h, hp) in handlePoints(annotation).enumerated()
        where hypot(hp.x - point.x, hp.y - point.y) <= radius {
            return .handle(h)
        }
        let slack = max(8 / max(displayScale, 0.01), annotation.lineWidth)
        return bodyContains(annotation, point: point, slack: slack) ? .body : .miss
    }

    /// 图形本体的命中判断（贴着线条/边框才命中，图形内部留空方便继续画新标注）
    private func bodyContains(_ a: Annotation, point: CGPoint, slack: CGFloat) -> Bool {
        switch a.tool {
        case .pen:
            guard a.points.count >= 2 else { return false }
            for i in 0..<(a.points.count - 1)
            where distanceToSegment(point, a.points[i], a.points[i + 1]) <= slack {
                return true
            }
            return false
        case .arrow:
            guard a.points.count >= 2 else { return false }
            return distanceToSegment(point, a.points[0], a.points[1]) <= slack
        case .rectangle, .ellipse:
            guard a.points.count >= 2 else { return false }
            let rect = imageRect(a.points[0], a.points[1])
            if a.isFilled {
                return rect.contains(point)
            }
            let outer = rect.insetBy(dx: -slack, dy: -slack)
            let inner = rect.insetBy(dx: slack, dy: slack)
            if !outer.contains(point) { return false }
            if a.tool == .rectangle {
                return !(inner.width > 0 && inner.height > 0 && inner.contains(point))
            }
            return ellipseContains(point, in: outer) && !ellipseContains(point, in: inner)
        case .mosaic:
            guard a.points.count >= 2 else { return false }
            return imageRect(a.points[0], a.points[1]).contains(point)
        case .magnifier:
            guard a.points.count >= 2 else { return false }
            let rect = imageRect(a.points[0], a.points[1])
            let diameter = min(rect.width, rect.height)
            guard diameter > 0 else { return false }
            return hypot(point.x - (rect.minX + diameter / 2), point.y - (rect.minY + diameter / 2)) <= diameter / 2 + slack
        case .text, .number:
            return boundingBox(a).contains(point)
        case .crop, .select:
            return false
        }
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func ellipseContains(_ point: CGPoint, in rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let dx = (point.x - rect.midX) / (rect.width / 2)
        let dy = (point.y - rect.midY) / (rect.height / 2)
        return dx * dx + dy * dy <= 1
    }

    private func annotationHit(at point: CGPoint) -> (index: Int, handle: Int)? {
        let radius = 10 / max(displayScale, 0.01)
        for index in annotations.indices.reversed() {
            for (h, hp) in handlePoints(annotations[index]).enumerated()
            where hypot(hp.x - point.x, hp.y - point.y) <= radius {
                return (index, h)
            }
        }
        for index in annotations.indices.reversed() where boundingBox(annotations[index]).contains(point) {
            return (index, -1)
        }
        return nil
    }

    private func drawSelection(_ a: Annotation) {
        let box = boundingBox(a)
        let viewRect = NSRect(origin: viewPoint(box.origin),
                              size: CGSize(width: box.width * displayScale, height: box.height * displayScale))
        let border = NSBezierPath(rect: viewRect)
        border.lineWidth = 1
        let pattern: [CGFloat] = [4, 3]
        border.setLineDash(pattern, count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        border.stroke()
        // A number's handle is its body. Drawing the usual white handle on top
        // of it hides the digit until the next repaint. Text uses four corner
        // handles so its wrapping width can be adjusted directly.
        let handles = a.tool == .number ? [] : handlePoints(a)
        for hp in handles {
            let vp = viewPoint(hp)
            let handle = NSBezierPath(ovalIn: NSRect(x: vp.x - 5, y: vp.y - 5, width: 10, height: 10))
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.lineWidth = 1.5
            handle.stroke()
        }
    }

    private func watermarkRect(_ config: WatermarkConfiguration) -> CGRect {
        let size = WatermarkRenderer.markSize(config)
        let anchor = config.customPosition ?? config.position.normalizedPoint
        return CGRect(x: anchor.x * imageSize.width - size.width * anchor.x,
                      y: anchor.y * imageSize.height - size.height * anchor.y,
                      width: size.width, height: size.height)
    }

    private func watermarkRotatedPoint(_ point: CGPoint, around center: CGPoint, degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians),
                       y: center.y + dx * sin(radians) + dy * cos(radians))
    }

    private func watermarkCorners(_ rect: CGRect, rotation: CGFloat) -> [CGPoint] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            .map { watermarkRotatedPoint($0, around: center, degrees: rotation) }
    }

    private func watermarkRotationHandle(_ rect: CGRect, rotation: CGFloat) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let top = CGPoint(x: rect.midX, y: rect.minY - 28 / max(displayScale, 0.01))
        return watermarkRotatedPoint(top, around: center, degrees: rotation)
    }

    private func drawWatermarkSphere(at point: CGPoint) {
        let radius = 16 / max(displayScale, 0.01)
        let viewPoint = self.viewPoint(point)
        let sphere = NSRect(x: viewPoint.x - radius * displayScale,
                            y: viewPoint.y - radius * displayScale,
                            width: radius * 2 * displayScale,
                            height: radius * 2 * displayScale)
        let gradient = NSGradient(colors: [NSColor.white.withAlphaComponent(0.95),
                                            NSColor.controlAccentColor,
                                            NSColor.controlAccentColor.withAlphaComponent(0.45)])
        gradient?.draw(in: sphere, relativeCenterPosition: CGPoint(x: -0.35, y: -0.4))
        let clip = NSBezierPath(ovalIn: sphere)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let latitude = NSBezierPath(ovalIn: sphere.insetBy(dx: 2 * displayScale,
                                                            dy: radius * 0.7 * displayScale))
        latitude.lineWidth = max(0.7, displayScale)
        latitude.stroke()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        let longitude = NSBezierPath(ovalIn: sphere.insetBy(dx: radius * 0.62 * displayScale,
                                                             dy: 2 * displayScale))
        longitude.lineWidth = max(0.7, displayScale)
        longitude.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: sphere.minX + sphere.width * 0.23,
                                    y: sphere.minY + sphere.height * 0.22,
                                    width: sphere.width * 0.16,
                                    height: sphere.height * 0.16)).fill()
        NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(ovalIn: sphere)
        border.lineWidth = max(1, displayScale)
        border.stroke()
    }

    private func drawWatermarkSelection() {
        guard let config = watermark else { return }
        let rect = watermarkRect(config)
        let corners = watermarkCorners(rect, rotation: config.rotation).map(viewPoint)
        let border = NSBezierPath()
        border.move(to: corners[0])
        for corner in corners.dropFirst() { border.line(to: corner) }
        border.close()
        border.lineWidth = 1
        border.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        border.stroke()
        let top = viewPoint(watermarkRotatedPoint(CGPoint(x: rect.midX, y: rect.minY),
                                                  around: CGPoint(x: rect.midX, y: rect.midY),
                                                  degrees: config.rotation))
        let handle = viewPoint(watermarkRotationHandle(rect, rotation: config.rotation))
        let stem = NSBezierPath()
        stem.move(to: top)
        stem.line(to: handle)
        stem.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        stem.stroke()
        drawWatermarkSphere(at: watermarkRotationHandle(rect, rotation: config.rotation))
        for corner in corners {
            let point = corner
            let cornerKnob = NSBezierPath(ovalIn: NSRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            NSColor.white.setFill()
            cornerKnob.fill()
            NSColor.controlAccentColor.setStroke()
            cornerKnob.stroke()
        }
    }

    func applyColor(_ c: NSColor) {
        color = c
        var didChange = false
        if var currentWatermark = watermark, currentWatermark.colorHex != c.hexString {
            currentWatermark.colorHex = c.hexString
            pushUndo()
            watermark = currentWatermark
            didChange = true
        }
        if let index = selectedIndex, annotations.indices.contains(index) {
            pushUndo()
            annotations[index].color = c
            didChange = true
        }
        if didChange {
            needsDisplay = true
            onChange?()
        }
    }

    func applyLineWidth(_ w: CGFloat) {
        lineWidth = w
        if var currentWatermark = watermark, watermarkEditing {
            // Reuse the existing 粗细 control for watermark text. The slider
            // range is intentionally broad enough to reach both light and
            // black system font weights.
            currentWatermark.fontWeight = max(-1, min(1, -0.5 + (w - 1) / 19 * 1.5))
            pushUndo()
            watermark = currentWatermark
            onChange?()
        }
        if let index = selectedIndex, annotations.indices.contains(index) {
            annotations[index].lineWidth = w
            needsDisplay = true
            onChange?()
        }
    }

    func applyShapeFilled(_ filled: Bool) {
        shapeFilled = filled
        guard let index = selectedIndex, annotations.indices.contains(index),
              annotations[index].tool == .rectangle || annotations[index].tool == .ellipse else {
            needsDisplay = true
            return
        }
        guard annotations[index].isFilled != filled else { return }
        pushUndo()
        annotations[index].isFilled = filled
        needsDisplay = true
        onChange?()
    }

    func applyTextFontSize(_ size: CGFloat) {
        let value = min(112, max(8, size))
        textFontSize = value
        if let index = selectedIndex, annotations.indices.contains(index), annotations[index].tool == .text {
            pushUndo()
            annotations[index].fontSize = value
            needsDisplay = true
            onChange?()
        }
    }

    func applyMosaicStyle(_ s: MosaicStyle) {
        mosaicStyle = s
        if let index = selectedIndex, annotations.indices.contains(index), annotations[index].tool == .mosaic {
            annotations[index].mosaicStyle = s
            needsDisplay = true
            onChange?()
        }
    }

    func applyMosaicStrength(_ s: CGFloat) {
        let clamped = min(10, max(1, s))
        mosaicStrength = clamped
        if let index = selectedIndex, annotations.indices.contains(index), annotations[index].tool == .mosaic {
            annotations[index].mosaicStrength = clamped
            needsDisplay = true
            onChange?()
        }
    }

    func deleteSelected() {
        guard let index = selectedIndex, annotations.indices.contains(index) else { return }
        pushUndo()
        annotations.remove(at: index)
        selectedIndex = nil
        needsDisplay = true
        onChange?()
    }

    // MARK: 马赛克

    private func mosaicImage(region: CGRect, style: MosaicStyle, strength: CGFloat) -> NSImage? {
        guard region.width >= 4, region.height >= 4, let source = sourceImage(for: region) else { return nil }
        guard let cg = Self.mosaicCGImage(source: source, style: style, strength: strength,
                                          context: ciContext) else { return nil }
        return NSImage(cgImage: cg, size: region.size)
    }

    private static func mosaicCGImage(source: CGImage, style: MosaicStyle, strength: CGFloat,
                                      context: CIContext) -> CGImage? {
        guard let output = mosaicCIImage(source: CIImage(cgImage: source), style: style, strength: strength) else {
            return nil
        }
        return context.createCGImage(output, from: output.extent)
    }

    static func mosaicImage(source: CIImage, style: MosaicStyle, strength: CGFloat) -> CIImage? {
        mosaicCIImage(source: source, style: style, strength: strength)
    }

    private static func mosaicCIImage(source: CIImage, style: MosaicStyle, strength: CGFloat) -> CIImage? {
        let extent = source.extent
        let factor = min(10, max(1, strength))
        let output: CIImage?
        switch style {
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = source
            filter.scale = Float(max(4, extent.width * factor / 96))
            filter.center = CGPoint(x: extent.midX, y: extent.midY)
            output = filter.outputImage
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = source.clampedToExtent()
            filter.radius = Float(max(2, extent.width * factor / 120))
            output = filter.outputImage?.cropped(to: extent)
        case .hexagon:
            let filter = CIFilter.hexagonalPixellate()
            filter.inputImage = source
            filter.scale = Float(max(4, extent.width * factor / 96))
            filter.center = CGPoint(x: extent.midX, y: extent.midY)
            output = filter.outputImage
        }
        return output?.cropped(to: extent)
    }

    /// Renders annotations into a transparent image for video composition.
    /// Coordinates are source-image pixels, matching the normal editor model.
    static func renderedAnnotationsImage(annotations: [Annotation], size: CGSize) -> CGImage? {
        guard size.width >= 1, size.height >= 1,
              annotations.contains(where: { $0.tool != .mosaic }) else { return nil }
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let canvas = AnnotationCanvas(frame: NSRect(x: 0, y: 0, width: width, height: height))
        canvas.showsBaseImage = false
        canvas.annotations = annotations.filter { $0.tool != .mosaic }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bitmapFormat: .alphaFirst, bytesPerRow: width * 4,
                                            bitsPerPixel: 32) else { return nil }
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        return bitmap.cgImage
    }

    func loadAnnotations(_ saved: [Annotation]) {
        finishTextEditing()
        annotations = saved
        selectedIndex = nil
        undoStack.removeAll()
        redoStack.removeAll()
        needsDisplay = true
    }

    func applyWatermark(_ value: WatermarkConfiguration?) {
        guard watermark != value else { return }
        pushUndo()
        watermark = value
        onChange?()
    }

    func beginWatermarkEditing() {
        watermarkEditing = true
        selectedIndex = nil
        needsDisplay = true
    }

    func endWatermarkEditing() {
        commitWatermarkText()
        watermarkEditing = false
        watermarkDrag = nil
        watermarkDragOffset = .zero
        needsDisplay = true
    }

    /// Updates the visible watermark while a settings control is being dragged.
    /// Live previews intentionally do not add one undo snapshot per slider tick.
    func previewWatermark(_ value: WatermarkConfiguration) {
        watermark = value
        onChange?()
    }

    func beginWatermarkTextEditing() {
        guard let config = watermark else { return }
        commitActiveField(switchToSelection: false)
        commitWatermarkText()
        watermarkEditing = true
        selectedIndex = nil
        window?.makeKey()
        let rect = watermarkRect(config)
        watermarkFieldImageRect = rect
        let field = NSTextField(frame: watermarkFieldFrame(rect))
        field.stringValue = config.text
        field.font = NSFont.systemFont(ofSize: max(12, config.fontSize * displayScale),
                                       weight: NSFont.Weight(rawValue: max(-1, min(1, config.fontWeight))))
        field.textColor = config.color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.16)
        field.isBordered = true
        field.focusRingType = .none
        field.alignment = .center
        field.placeholderString = L("输入水印文字")
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        watermarkField = field
        window?.makeFirstResponder(field)
        field.selectText(nil)
        updateWatermarkFieldFrame()
        needsDisplay = true
    }

    private func watermarkFieldFrame(_ rect: CGRect) -> NSRect {
        let viewRect = NSRect(origin: viewPoint(rect.origin),
                              size: CGSize(width: rect.width * displayScale,
                                           height: rect.height * displayScale))
        return viewRect.insetBy(dx: 2, dy: 2)
    }

    private func updateWatermarkFieldFrame() {
        guard let watermarkField, let config = watermark else { return }
        let rect = watermarkFieldImageRect ?? watermarkRect(config)
        watermarkField.frame = watermarkFieldFrame(rect)
        watermarkField.font = NSFont.systemFont(ofSize: max(12, config.fontSize * displayScale),
                                                weight: NSFont.Weight(rawValue: max(-1, min(1, config.fontWeight))))
        watermarkField.textColor = config.color
    }

    private func commitWatermarkText() {
        guard let field = watermarkField else { return }
        let text = field.stringValue
        watermarkField = nil
        watermarkFieldImageRect = nil
        field.delegate = nil
        field.removeFromSuperview()
        guard var config = watermark else { return }
        config.text = text
        watermark = config
        onChange?()
        needsDisplay = true
    }

    /// 取区域像素：优先底图裁剪；否则向覆盖层要「窗口之下」的截图。
    private func sourceImage(for region: CGRect) -> CGImage? {
        let rect = region.integral
        if let baseImage {
            // CGImage.cropping 为左上原点，与图片坐标一致，不要翻转
            return baseImage.cropping(to: rect)
        }
        return captureSource?(rect)
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        if watermarkField != nil {
            commitWatermarkText()
            return
        }
        if activeField != nil {
            commitActiveField()
            // The click that ends editing only commits the text. Do not let
            // the same event continue into selection hit-testing and clear
            // the newly selected annotation again.
            return
        }
        textResizeStart = nil
        // The first click after finishing text only confirms its selection.
        // A subsequent click can select or move other annotations.
        if awaitingTextSelectionClick {
            awaitingTextSelectionClick = false
            needsDisplay = true
            return
        }
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        let viewPoint = convert(event.locationInWindow, from: nil)
        if tool == .select, zoom > 1, event.buttonNumber == 2 {
            panning = true
            panStartView = viewPoint
            panStartOffset = panOffset
            return
        }
        if watermarkEditing, let config = watermark {
            let rect = watermarkRect(config)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let handle = watermarkRotationHandle(rect, rotation: config.rotation)
            let sphereRadius = 20 / max(displayScale, 0.01)
            if hypot(point.x - handle.x, point.y - handle.y) <= sphereRadius {
                pushUndo()
                watermarkDrag = .sphere
                watermarkSphereStartPoint = point
                watermarkSphereStartRotation = config.rotation
                watermarkSphereStartTilt = config.tilt
                watermarkSphereStartSpacing = config.spacing
                return
            }
            let radius = 14 / max(displayScale, 0.01)
            let corners = watermarkCorners(rect, rotation: config.rotation)
            if let corner = corners.enumerated().first(where: {
                hypot(point.x - $0.element.x, point.y - $0.element.y) <= radius
            }) {
                pushUndo()
                watermarkDrag = .resize(corner.offset)
                watermarkDragStartScale = config.scale
                watermarkDragStartDistance = max(1, hypot(point.x - rect.midX, point.y - rect.midY))
                return
            }
            let unrotatedPoint = watermarkRotatedPoint(point, around: center, degrees: -config.rotation)
            if rect.insetBy(dx: -radius, dy: -radius).contains(unrotatedPoint) {
                if event.clickCount >= 2 {
                    beginWatermarkTextEditing()
                    return
                }
                pushUndo()
                watermarkDrag = .move
                watermarkDragOffset = CGPoint(x: point.x - rect.midX, y: point.y - rect.midY)
                return
            }
            endWatermarkEditing()
        }
        // The canvas may be larger than a small screenshot. Do not create
        // annotations in the editor's empty area outside the source image.
        guard isInsideImage(point) else {
            selectedIndex = nil
            needsDisplay = true
            return
        }
        // OCR 取字框选（一次性）
        if recognitionAction != nil {
            ocrAnchor = point
            ocrRect = CGRect(origin: point, size: .zero)
            needsDisplay = true
            return
        }
        // 吸管：取像素色后回调（一次性）
        if isPickingColor {
            let picked = colorAt(imagePoint: point)
            endColorPick()
            if let picked { onColorPicked?(picked) }
            return
        }
        // 测量：点第一个点，再点第二个点
        if isMeasuring {
            if measureStart == nil {
                measureStart = point
                measureEnd = point
                onChange?()
            } else {
                measureEnd = point
                isMeasuring = false
                window?.acceptsMouseMovedEvents = false
                window?.invalidateCursorRects(for: self)
                onChange?()
                onMeasurementCompleted?()
            }
            needsDisplay = true
            return
        }
        // 测量完成后：拖动两个端点调整
        if !isMeasuring, let s = measureStart, let e = measureEnd {
            let radius = 14 / max(displayScale, 0.01)
            if hypot(point.x - s.x, point.y - s.y) <= radius {
                measureDrag = .start
                return
            }
            if hypot(point.x - e.x, point.y - e.y) <= radius {
                measureDrag = .end
                return
            }
        }
        // 刚画完的标注仍处于选中态：无需切回选择工具，直接拖拽它就能调整
        if tool != .select, tool != .crop,
           let index = selectedIndex, annotations.indices.contains(index) {
            switch editHit(on: annotations[index], at: point) {
            case .handle(let h):
                pushUndo()
                textResizeStart = textResizeStart(at: index, handle: h)
                dragState = .handle(h)
                dragLast = point
                onChange?()
                return
            case .body:
                pushUndo()
                dragState = .move
                dragLast = point
                onChange?()
                return
            case .miss:
                selectedIndex = nil
            }
        }
        switch tool {
        case .select:
            if let hit = annotationHit(at: point) {
                selectedIndex = hit.index
                pushUndo()
                textResizeStart = textResizeStart(at: hit.index, handle: hit.handle)
                dragState = hit.handle >= 0 ? .handle(hit.handle) : .move
                dragLast = point
                onChange?()
            } else {
                selectedIndex = nil
                dragState = .none
                // When zoomed in, dragging an empty area pans the image so its
                // corners can be inspected without changing annotation tools.
                if zoom > 1 {
                    panning = true
                    panStartView = viewPoint
                    panStartOffset = panOffset
                }
            }
        case .pen:
            current = Annotation(tool: .pen, points: [point], color: color, lineWidth: lineWidth)
        case .arrow, .rectangle, .ellipse, .mosaic, .magnifier:
            current = Annotation(tool: tool, points: [point, point], color: color,
                                 mosaicStyle: mosaicStyle, mosaicStrength: mosaicStrength,
                                 lineWidth: lineWidth, isFilled: shapeFilled)
        case .text:
            beginTextInput(at: point)
        case .number:
            commit(Annotation(tool: .number, points: [point], text: "\(nextNumber())", color: color))
        case .crop:
            cropAnchor = point
            cropRect = CGRect(origin: point, size: .zero)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if panning {
            let viewPoint = convert(event.locationInWindow, from: nil)
            panOffset = CGPoint(x: panStartOffset.x + viewPoint.x - panStartView.x,
                                y: panStartOffset.y + viewPoint.y - panStartView.y)
            onChange?()
            needsDisplay = true
            return
        }
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        if let drag = watermarkDrag, var config = watermark {
            let rect = watermarkRect(config)
            switch drag {
            case .move:
                let center = CGPoint(x: point.x - watermarkDragOffset.x,
                                     y: point.y - watermarkDragOffset.y)
                config.customPosition = CGPoint(x: max(0, min(1, center.x / max(imageSize.width, 1))),
                                                y: max(0, min(1, center.y / max(imageSize.height, 1))))
            case .rotate:
                let angle = atan2(point.y - rect.midY, point.x - rect.midX) * 180 / .pi + 90
                config.rotation = max(-180, min(180, angle))
            case .resize:
                let distance = hypot(point.x - rect.midX, point.y - rect.midY)
                let ratio = max(0.25, min(6, distance / watermarkDragStartDistance))
                config.scale = max(0.25, min(6, watermarkDragStartScale * ratio))
            case .sphere:
                let dx = point.x - watermarkSphereStartPoint.x
                let dy = point.y - watermarkSphereStartPoint.y
                config.rotation = max(-180, min(180, watermarkSphereStartRotation + dx * 0.7))
                config.tilt = max(-45, min(45, watermarkSphereStartTilt + dy * 0.45))
                if config.mode == .tiled {
                    config.spacing = max(1, min(4, watermarkSphereStartSpacing + dy * 0.012))
                }
            }
            watermark = config
            onChange?()
            needsDisplay = true
            return
        }
        if let drag = measureDrag {
            switch drag {
            case .start: measureStart = point
            case .end: measureEnd = point
            }
            needsDisplay = true
            return
        }
        if recognitionAction != nil {
            if let anchor = ocrAnchor {
                let end = CGPoint(x: min(max(0, point.x), imageSize.width),
                                  y: min(max(0, point.y), imageSize.height))
                ocrRect = imageRect(anchor, end)
            }
            needsDisplay = true
            return
        }
        if tool == .crop {
            if let anchor = cropAnchor { cropRect = imageRect(anchor, point) }
        } else if dragState != .none, let index = selectedIndex, annotations.indices.contains(index) {
            switch dragState {
            case .move:
                let dx = point.x - dragLast.x
                let dy = point.y - dragLast.y
                for k in annotations[index].points.indices {
                    annotations[index].points[k].x += dx
                    annotations[index].points[k].y += dy
                }
                dragLast = point
            case .handle(let h):
                if annotations[index].tool == .text {
                    resizeTextAnnotation(at: index, handle: h, to: point)
                    onChange?()
                } else if annotations[index].points.indices.contains(h) {
                    annotations[index].points[h] = annotations[index].tool == .magnifier
                        ? CGPoint(x: min(max(0, point.x), imageSize.width),
                                  y: min(max(0, point.y), imageSize.height)) : point
                }
            case .none:
                break
            }
        } else if var active = current {
            if active.tool == .pen { active.points.append(point) }
            else if active.points.count >= 2 {
                active.points[1] = active.tool == .magnifier
                    ? CGPoint(x: min(max(0, point.x), imageSize.width),
                              y: min(max(0, point.y), imageSize.height)) : point
            }
            current = active
        }
        needsDisplay = true
    }

    private func textResizeStart(at index: Int, handle: Int) -> TextResizeStart? {
        guard annotations.indices.contains(index), annotations[index].tool == .text,
              (0..<4).contains(handle), let point = annotations[index].points.first else { return nil }
        let annotation = annotations[index]
        let rect = textLayout(for: annotation.text, at: point, lineWidth: annotation.lineWidth,
                              textWidth: annotation.textWidth, fontSize: annotation.fontSize).rect
        let fontSize = min(112, annotation.fontSize ?? annotation.lineWidth * 7)
        return TextResizeStart(index: index, handle: handle, rect: rect, fontSize: fontSize,
                               textWidth: annotation.textWidth ?? rect.width)
    }

    /// Corner dragging scales the text box and its font together. This keeps
    /// the visual proportions intact while the changed width still controls
    /// the same character wrapping behavior as normal text editing.
    private func resizeTextAnnotation(at index: Int, handle: Int, to point: CGPoint) {
        guard let start = textResizeStart, start.index == index, start.handle == handle,
              annotations.indices.contains(index), annotations[index].points.first != nil else { return }
        let bounds = textBounds
        let minimumWidth = min(24, max(1, bounds.width))
        let horizontalScale: CGFloat
        let verticalScale: CGFloat
        if handle == 0 || handle == 3 {
            horizontalScale = (start.rect.maxX - point.x) / max(1, start.rect.width)
        } else {
            horizontalScale = (point.x - start.rect.minX) / max(1, start.rect.width)
        }
        if handle == 0 || handle == 1 {
            verticalScale = (start.rect.maxY - point.y) / max(1, start.rect.height)
        } else {
            verticalScale = (point.y - start.rect.minY) / max(1, start.rect.height)
        }
        // Use the axis that moved farther from its starting size so either
        // horizontal or vertical corner dragging can enlarge or shrink it.
        let rawScale = abs(horizontalScale - 1) >= abs(verticalScale - 1)
            ? horizontalScale : verticalScale
        let scale = min(4, max(0.25, rawScale))
        let fontSize = min(112, max(8, start.fontSize * scale))
        let scaledWidth = min(bounds.width, max(minimumWidth, start.textWidth * scale))
        let anchorX = (handle == 0 || handle == 3) ? start.rect.maxX : start.rect.minX
        let anchorY = (handle == 0 || handle == 1) ? start.rect.maxY : start.rect.minY
        let previewHeight = textLayout(for: annotations[index].text, at: .zero,
                                       lineWidth: annotations[index].lineWidth,
                                       textWidth: scaledWidth, fontSize: fontSize).rect.height
        let left = (handle == 0 || handle == 3) ? anchorX - scaledWidth : anchorX
        let top = (handle == 0 || handle == 1) ? anchorY - previewHeight : anchorY
        let clampedLeft = min(max(bounds.minX, left), max(bounds.minX, bounds.maxX - scaledWidth))
        let clampedTop = min(max(bounds.minY, top), max(bounds.minY, bounds.maxY - previewHeight))
        annotations[index].textWidth = scaledWidth
        annotations[index].fontSize = fontSize
        annotations[index].points[0].x = clampedLeft
        annotations[index].points[0].y = clampedTop
    }

    override func mouseMoved(with event: NSEvent) {
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        if isPickingColor {
            hoverPoint = point
            hoverColor = colorAt(imagePoint: point)
            needsDisplay = true
            return
        }
        // 测量第一个点已确定时，线随光标预览
        if isMeasuring, measureStart != nil {
            measureEnd = point
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if panning {
            panning = false
            onChange?()
            needsDisplay = true
            return
        }
        if watermarkDrag != nil {
            watermarkDrag = nil
            watermarkDragOffset = .zero
            onChange?()
            needsDisplay = true
            return
        }
        measureDrag = nil
        if let action = recognitionAction {
            let point = imagePoint(convert(event.locationInWindow, from: nil))
            let end = CGPoint(x: min(max(0, point.x), imageSize.width),
                              y: min(max(0, point.y), imageSize.height))
            let rect = ocrAnchor.map { imageRect($0, end) }
            endRecognitionSelection()
            if let rect, rect.width >= 2, rect.height >= 2 { onRecognitionSelection?(action, rect) }
            return
        }
        if tool == .crop {
            cropAnchor = nil
            if let rect = cropRect, rect.width >= 8, rect.height >= 8 { applyCrop(rect) }
            cropRect = nil
            needsDisplay = true
            return
        }
        if dragState != .none {
            dragState = .none
            textResizeStart = nil
            onChange?()
            needsDisplay = true
            return
        }
        if tool == .select {
            onChange?()
            needsDisplay = true
            return
        }
        if let active = current {
            let validMagnifier = active.tool != .magnifier ||
                (active.points.count >= 2 && min(abs(active.points[1].x - active.points[0].x),
                                                  abs(active.points[1].y - active.points[0].y)) >= 8)
            if validMagnifier && (active.tool != .pen || active.points.count > 1) { commit(active) }
            current = nil
        }
        needsDisplay = true
    }

    private func commit(_ annotation: Annotation) {
        pushUndo()
        annotations.append(annotation)
        // 自动选中新标注，画完即可直接调整（拖控制点/本体），无需切回选择工具
        selectedIndex = annotations.count - 1
        needsDisplay = true
        onChange?()
    }

    private func nextNumber() -> Int {
        let used = annotations.filter { $0.tool == .number }.count
        return used + 1
    }

    // MARK: 撤销 / 重做

    private func snapshot(restoringExportRegion: Bool = false) -> Snapshot {
        Snapshot(baseImage: baseImage, annotations: annotations, watermark: watermark,
                 exportRegion: exportRegion,
                 restoresExportRegion: restoringExportRegion)
    }

    private func pushUndo(restoringExportRegion: Bool = false) {
        undoStack.append(snapshot(restoringExportRegion: restoringExportRegion))
        redoStack.removeAll()
    }

    private func restore(_ state: Snapshot) {
        baseImage = state.baseImage
        annotations = state.annotations
        watermark = state.watermark
        if state.restoresExportRegion { exportRegion = state.exportRegion }
        selectedIndex = nil
        needsDisplay = true
        onChange?()
    }

    /// 裁剪：立即把底图换成裁剪区域；标注随之平移，完全落在外面的丢掉，剩下的夹到边界内
    private func applyCrop(_ rect: CGRect) {
        guard let baseImage else { return }
        if usesExportCrop {
            let bounds = exportRegion ?? CGRect(origin: .zero, size: imageSize)
            let clipped = rect.integral.intersection(bounds)
            guard !clipped.isNull, clipped.width >= 4, clipped.height >= 4 else { return }
            pushUndo(restoringExportRegion: true)
            exportRegion = clipped
            selectedIndex = nil
            onChange?()
            return
        }
        let integral = rect.integral
        let region = CGRect(origin: .zero, size: CGSize(width: integral.width, height: integral.height))
        guard integral.width >= 4, integral.height >= 4,
              let cropped = baseImage.cropping(to: integral) else { return }
        pushUndo()
        annotations = annotations.compactMap { annotation in
            var updated = annotation
            updated.points = updated.points.map { CGPoint(x: $0.x - integral.minX, y: $0.y - integral.minY) }
            guard boundingBox(updated).intersects(region) else { return nil }
            updated.points = updated.points.map {
                CGPoint(x: min(max(0, $0.x), region.width), y: min(max(0, $0.y), region.height))
            }
            return updated
        }
        self.baseImage = cropped
        selectedIndex = nil
        onChange?()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(snapshot(restoringExportRegion: last.restoresExportRegion))
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot(restoringExportRegion: next.restoresExportRegion))
        restore(next)
    }

    func clearAll() {
        pushUndo()
        annotations.removeAll()
        cropRect = nil
        needsDisplay = true
        onChange?()
    }

    // MARK: 文字（原地输入）

    private struct TextLayout {
        let rect: CGRect
        let font: NSFont
    }

    private var textParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.lineSpacing = 0
        return style
    }

    private let textVerticalPadding: CGFloat = 8

    /// Measures text in image coordinates and constrains it to the source
    /// image. The same layout is used by drawing, hit testing, and editing so
    /// a wrapped annotation cannot be painted outside the screenshot.
    private func measuredTextSize(_ text: String, font: NSFont, width: CGFloat) -> CGSize {
        let attributed = NSAttributedString(string: text,
                                             attributes: [.font: font, .paragraphStyle: textParagraphStyle])
        let measured = attributed.boundingRect(
            with: CGSize(width: max(1, width), height: 10_000_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        // Keep the extra space in the shared measurement used by both the
        // editor field and the committed drawing. It prevents ascenders and
        // descenders from being clipped at the text box edge.
        return CGSize(width: max(1, ceil(measured.width)),
                      height: max(1, ceil(measured.height) + textVerticalPadding))
    }

    private func textMetrics(for text: String, lineWidth: CGFloat, textWidth: CGFloat) -> (fontSize: CGFloat, size: CGSize) {
        let requested = min(112, max(8, lineWidth * 7))
        let bounds = textBounds
        let availableHeight = max(1, bounds.height)
        var effective = requested
        var measured = measuredTextSize(text,
                                        font: NSFont.systemFont(ofSize: effective, weight: .bold),
                                        width: textWidth)
        if measured.height > availableHeight {
            var low: CGFloat = 6
            var high = requested
            for _ in 0..<12 {
                let candidate = (low + high) / 2
                let candidateSize = measuredTextSize(text,
                                                     font: NSFont.systemFont(ofSize: candidate, weight: .bold),
                                                     width: textWidth)
                if candidateSize.height <= availableHeight {
                    low = candidate
                } else {
                    high = candidate
                }
            }
            effective = low
            measured = measuredTextSize(text,
                                        font: NSFont.systemFont(ofSize: effective, weight: .bold),
                                        width: textWidth)
        }
        return (effective, measured)
    }

    private func textLayout(for text: String, at point: CGPoint, lineWidth: CGFloat? = nil,
                            textWidth: CGFloat? = nil, fontSize: CGFloat? = nil) -> TextLayout {
        let bounds = textBounds
        let anchor = CGPoint(x: min(max(bounds.minX, point.x), max(bounds.minX, bounds.maxX - 1)),
                             y: min(max(bounds.minY, point.y), max(bounds.minY, bounds.maxY - 1)))
        // A committed annotation uses the same box width as its editor. Older
        // annotations have no stored width and continue to use the full image.
        let availableWidth = min(max(1, bounds.width), max(1, textWidth ?? bounds.width))
        let metrics = textMetrics(for: text, lineWidth: fontSize.map { $0 / 7 } ?? lineWidth ?? self.lineWidth,
                                  textWidth: availableWidth)

        // Keep the full text-box width for drawing. Using measured.width here
        // would make AppKit reflow the text with a narrower rectangle and lose
        // the exact soft wraps that were visible while editing.
        let size = CGSize(width: availableWidth,
                          height: min(max(1, bounds.height), metrics.size.height))
        let origin = CGPoint(x: min(anchor.x, max(bounds.minX, bounds.maxX - size.width)),
                             y: min(anchor.y, max(bounds.minY, bounds.maxY - size.height)))
        let font = NSFont.systemFont(ofSize: metrics.fontSize * displayScale, weight: .bold)
        return TextLayout(rect: CGRect(origin: origin, size: size), font: font)
    }

    private func editingFrame(for text: String) -> NSRect {
        let scale = max(displayScale, 0.01)
        let point = pendingTextPoint
        let bounds = textBounds
        let widthInImage = min(320 / scale, max(1, bounds.width))
        let metrics = textMetrics(for: text.isEmpty ? " " : text,
                                  lineWidth: textFontSize / 7, textWidth: widthInImage)
        let width = widthInImage * scale
        // Width is expressed in image points and can scale with the canvas,
        // but the field still needs a real screen-space minimum height. If the
        // canvas is fitted below 100%, scaling the old 38pt minimum made the
        // field shorter than its own glyphs and clipped half of a line.
        let screenFont = NSFont.systemFont(ofSize: metrics.fontSize * scale, weight: .bold)
        let topPadding = max(4, ceil(screenFont.ascender * 0.18))
        let bottomPadding = max(4, ceil(abs(screenFont.descender) * 0.35))
        let height = max(44, metrics.size.height * scale + topPadding + bottomPadding)
        let imageViewRect = NSRect(origin: displayOrigin,
                                   size: CGSize(width: bounds.width * scale, height: bounds.height * scale))
        let origin = viewPoint(point)
        let fieldHeight = min(height, imageViewRect.height)
        let clampedX = min(max(imageViewRect.minX, origin.x), max(imageViewRect.minX, imageViewRect.maxX - width))
        let clampedY = min(max(imageViewRect.minY, origin.y + topPadding),
                           max(imageViewRect.minY, imageViewRect.maxY - fieldHeight))
        return NSRect(x: clampedX, y: clampedY, width: width, height: fieldHeight)
    }

    private func beginTextInput(at point: CGPoint) {
        awaitingTextSelectionClick = false
        window?.makeKey()
        pendingTextPoint = point
        let field = NSTextField(frame: editingFrame(for: ""))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        let scale = max(displayScale, 0.01)
        let widthInImage = min(320 / scale, max(1, textBounds.width))
        let metrics = textMetrics(for: " ", lineWidth: textFontSize / 7, textWidth: widthInImage)
        field.font = NSFont.systemFont(ofSize: metrics.fontSize * scale, weight: .bold)
        field.textColor = color
        field.placeholderString = L("输入文字")
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byCharWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.lineBreakMode = .byCharWrapping
        field.delegate = self
        addSubview(field)
        activeField = field
        window?.makeFirstResponder(field)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let watermarkField, obj.object as? NSTextField === watermarkField,
           var config = watermark {
            config.text = watermarkField.stringValue
            watermark = config
            updateWatermarkFieldFrame()
            needsDisplay = true
            return
        }
        guard let field = activeField else { return }
        field.frame = editingFrame(for: field.stringValue)
        let scale = max(displayScale, 0.01)
        let widthInImage = max(1, field.bounds.width / scale)
        let metrics = textMetrics(for: field.stringValue.isEmpty ? " " : field.stringValue,
                                  lineWidth: textFontSize / 7, textWidth: widthInImage)
        field.font = NSFont.systemFont(ofSize: metrics.fontSize * scale, weight: .bold)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === watermarkField {
            commitWatermarkText()
        } else {
            commitActiveField()
        }
    }

    /// NSTextField normally treats Return as its action key. Let the field
    /// editor insert a newline instead; clicking away or switching tools still
    /// commits the annotation through `commitActiveField()`.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) ||
              commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) else { return false }
        textView.insertNewlineIgnoringFieldEditor(nil)
        return true
    }

    private func commitActiveField(switchToSelection: Bool = true) {
        guard let field = activeField else { return }
        let text = field.stringValue
        let textColor = field.textColor ?? color
        let point = pendingTextPoint
        let textWidth = max(1, field.bounds.width / max(displayScale, 0.01))
        // Removing a focused field can synchronously send an end-editing callback.
        // Retire it first so that callback cannot commit the same text again.
        activeField = nil
        field.delegate = nil
        field.removeFromSuperview()
        if !text.isEmpty {
            commit(Annotation(tool: .text, points: [point], text: text, textWidth: textWidth,
                              fontSize: textFontSize, color: textColor))
            awaitingTextSelectionClick = switchToSelection
            if switchToSelection { tool = .select }
            window?.makeFirstResponder(self)
            onChange?()
        }
        needsDisplay = true
    }

    func finishTextEditing() {
        commitActiveField()
        commitWatermarkText()
    }

    // MARK: 导出（把标注烘焙进底图，供图片编辑器保存/复制）

    /// 新建一个 1:1 的同内容画布渲染成图，再按裁剪框裁切。
    func renderedImage() -> CGImage? {
        finishTextEditing()
        guard let baseImage else { return nil }
        let copy = AnnotationCanvas(frame: NSRect(origin: .zero, size: imageSize))
        copy.baseImage = baseImage
        copy.watermark = watermark
        copy.usesExportCrop = usesExportCrop
        copy.exportRegion = exportRegion
        copy.annotations = annotations
        // Create an explicitly sized bitmap. NSView's convenience bitmap rep
        // can use the Retina backing scale, which makes a small crop export at
        // a larger pixel size than the source screenshot.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: baseImage.width,
                                         pixelsHigh: baseImage.height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bitmapFormat: .alphaFirst,
                                         bytesPerRow: baseImage.width * 4,
                                         bitsPerPixel: 32) else { return nil }
        copy.cacheDisplay(in: copy.bounds, to: rep)
        guard let cg = rep.cgImage else { return nil }
        if let cropRect = usesExportCrop ? exportRegion : cropRect {
            // CGImage.cropping 为左上原点，与图片坐标一致，不要翻转
            return cg.cropping(to: cropRect.integral) ?? cg
        }
        return cg
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
