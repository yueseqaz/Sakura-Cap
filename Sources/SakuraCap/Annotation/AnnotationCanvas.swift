import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 模型

enum AnnotationTool: Int, CaseIterable {
    case select, pen, arrow, rectangle, text, number, mosaic, crop

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .number: return "1.circle"
        case .mosaic: return "square.grid.3x3.fill"
        case .crop: return "crop"
        }
    }

    /// 直播覆盖层可用（裁剪只用于图片编辑）
    var availableLive: Bool { self != .crop }
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
struct Annotation {
    var tool: AnnotationTool
    var points: [CGPoint]
    var text: String = ""
    var color: NSColor
    var mosaicStyle: MosaicStyle = .pixelate
    var mosaicStrength: CGFloat = 4
    var lineWidth: CGFloat = 4
}

// MARK: - 画布

/// 通用标注画布：可带底图（图片编辑）或不带（直播覆盖层）。
/// 支持 画笔/箭头/矩形/文字/序号/马赛克/裁剪，以及撤销、重做。
final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    var tool: AnnotationTool = .select {
        didSet {
            // 切换到绘制工具时清掉选中，避免下一个图形先被当成“编辑旧标注”
            if tool != .select { selectedIndex = nil }
            cancelTransient()
            needsDisplay = true
        }
    }
    var color: NSColor = .systemRed
    var mosaicStyle: MosaicStyle = .pixelate
    var mosaicStrength: CGFloat = 4
    var lineWidth: CGFloat = 4
    var allowCrop = true

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

    /// 变更回调（用于刷新撤销/重做按钮状态、编辑器脏标记）
    var onChange: (() -> Void)?

    private(set) var annotations: [Annotation] = []
    private var current: Annotation?
    private struct Snapshot { let baseImage: CGImage?; let annotations: [Annotation] }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var activeField: NSTextField?
    private var pendingTextPoint: CGPoint = .zero
    private(set) var cropRect: CGRect? // 图片坐标
    private var cropAnchor: CGPoint?

    // 一次性识别框选（图片坐标）
    enum RecognitionAction { case ocr, barcode, translate }
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
    private var hoverColor: NSColor?
    private var hoverPoint: CGPoint?

    // 选中/编辑
    private var selectedIndex: Int?
    private var dragState: DragState = .none
    private var dragLast: CGPoint = .zero
    private enum DragState: Equatable { case none, move, handle(Int) }

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

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
        cancelTransient()
        isMeasuring = true
        measureStart = nil
        measureEnd = nil
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
        needsDisplay = true
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
        // Keep zoom centered on the image rather than following the cursor.
        // This makes toolbar, trackpad and wheel zoom behave consistently.
        zoom = min(20, max(0.2, zoom * factor))
        panOffset = .zero
        needsDisplay = true
        onChange?()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // ⌘ + 滚轮：平移画面
            panOffset.x += event.scrollingDeltaX
            panOffset.y += event.scrollingDeltaY
            needsDisplay = true
        } else {
            // 单独滚轮：缩放
            let factor = min(1.18, max(0.85, pow(1.02, event.scrollingDeltaY)))
            zoom(at: CGPoint(x: bounds.midX, y: bounds.midY), factor: factor)
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(at: CGPoint(x: bounds.midX, y: bounds.midY), factor: 1 + event.magnification)
    }

    private func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
        let scale = displayScale
        let origin = displayOrigin
        return CGPoint(x: (viewPoint.x - origin.x) / scale, y: (viewPoint.y - origin.y) / scale)
    }

    private func isInsideImage(_ point: CGPoint) -> Bool {
        let size = imageSize
        return point.x >= 0 && point.y >= 0 && point.x <= size.width && point.y <= size.height
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        let scale = displayScale
        let origin = displayOrigin
        return CGPoint(x: imagePoint.x * scale + origin.x, y: imagePoint.y * scale + origin.y)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        if let baseImage {
            NSImage(cgImage: baseImage, size: imageSize)
                .draw(in: NSRect(origin: displayOrigin, size: CGSize(width: imageSize.width * displayScale,
                                                                     height: imageSize.height * displayScale)))
        }
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
        case .rectangle:
            guard annotation.points.count >= 2 else { return }
            let a = viewPoint(annotation.points[0]), b = viewPoint(annotation.points[1])
            let rect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.lineWidth
            annotation.color.setStroke()
            path.stroke()
        case .text:
            guard let point = annotation.points.first else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(12, annotation.lineWidth * 7) * displayScale, weight: .bold),
                .foregroundColor: annotation.color,
            ]
            NSAttributedString(string: annotation.text, attributes: attributes).draw(at: viewPoint(point))
        case .number:
            guard let point = annotation.points.first else { return }
            drawNumber(annotation.text, at: viewPoint(point), color: annotation.color)
        case .mosaic:
            drawMosaic(annotation)
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

        let dx = Int(abs(b.x - a.x).rounded())
        let dy = Int(abs(b.y - a.y).rounded())
        let distance = Int(hypot(b.x - a.x, b.y - a.y).rounded())
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
        case .text, .number: return a.points.first.map { [$0] } ?? []
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
            let font = NSFont.systemFont(ofSize: max(12, a.lineWidth * 7), weight: .bold)
            let textSize = NSAttributedString(string: a.text, attributes: [.font: font]).size()
            return CGRect(x: p.x, y: p.y, width: textSize.width, height: textSize.height).insetBy(dx: -4, dy: -4)
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
        case .rectangle:
            guard a.points.count >= 2 else { return false }
            let rect = imageRect(a.points[0], a.points[1])
            let outer = rect.insetBy(dx: -slack, dy: -slack)
            let inner = rect.insetBy(dx: slack, dy: slack)
            if !outer.contains(point) { return false }
            return !(inner.width > 0 && inner.height > 0 && inner.contains(point))
        case .mosaic:
            guard a.points.count >= 2 else { return false }
            return imageRect(a.points[0], a.points[1]).contains(point)
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
        // of it hides the digit until the next repaint.
        let handles = a.tool == .number || a.tool == .text ? [] : handlePoints(a)
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

    func applyColor(_ c: NSColor) {
        color = c
        if let index = selectedIndex, annotations.indices.contains(index) {
            annotations[index].color = c
            needsDisplay = true
            onChange?()
        }
    }

    func applyLineWidth(_ w: CGFloat) {
        lineWidth = w
        if let index = selectedIndex, annotations.indices.contains(index) {
            annotations[index].lineWidth = w
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
        let ci = CIImage(cgImage: source)
        let extent = ci.extent
        let factor = min(10, max(1, strength))
        var output: CIImage?
        switch style {
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = ci
            filter.scale = Float(max(4, extent.width * factor / 96))
            filter.center = CGPoint(x: extent.midX, y: extent.midY)
            output = filter.outputImage
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ci.clampedToExtent()
            filter.radius = Float(max(2, extent.width * factor / 120))
            output = filter.outputImage?.cropped(to: extent)
        case .hexagon:
            let filter = CIFilter.hexagonalPixellate()
            filter.inputImage = ci
            filter.scale = Float(max(4, extent.width * factor / 96))
            filter.center = CGPoint(x: extent.midX, y: extent.midY)
            output = filter.outputImage
        }
        guard let output, let cg = ciContext.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: cg, size: region.size)
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
        if activeField != nil { commitActiveField() }
        let point = imagePoint(convert(event.locationInWindow, from: nil))
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
            } else {
                measureEnd = point
                isMeasuring = false
                window?.acceptsMouseMovedEvents = false
                window?.invalidateCursorRects(for: self)
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
                dragState = hit.handle >= 0 ? .handle(hit.handle) : .move
                dragLast = point
                onChange?()
            } else {
                selectedIndex = nil
                dragState = .none
            }
        case .pen:
            current = Annotation(tool: .pen, points: [point], color: color, lineWidth: lineWidth)
        case .arrow, .rectangle, .mosaic:
            current = Annotation(tool: tool, points: [point, point], color: color,
                                 mosaicStyle: mosaicStyle, mosaicStrength: mosaicStrength,
                                 lineWidth: lineWidth)
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
        let point = imagePoint(convert(event.locationInWindow, from: nil))
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
                if annotations[index].points.indices.contains(h) { annotations[index].points[h] = point }
            case .none:
                break
            }
        } else if var active = current {
            if active.tool == .pen { active.points.append(point) }
            else if active.points.count >= 2 { active.points[1] = point }
            current = active
        }
        needsDisplay = true
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
        measureDrag = nil
        if let action = recognitionAction {
            let rect = ocrRect
            endRecognitionSelection()
            if let rect, rect.width >= 4, rect.height >= 4 { onRecognitionSelection?(action, rect) }
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
            if active.tool != .pen || active.points.count > 1 { commit(active) }
            current = nil
        }
        needsDisplay = true
    }

    private func commit(_ annotation: Annotation) {
        pushUndo()
        annotations.append(annotation)
        // 自动选中新标注，画完即可直接调整（拖控制点/本体），无需切回选择工具
        selectedIndex = annotations.count - 1
        onChange?()
    }

    private func nextNumber() -> Int {
        let used = annotations.filter { $0.tool == .number }.count
        return used + 1
    }

    // MARK: 撤销 / 重做

    private var snapshot: Snapshot { Snapshot(baseImage: baseImage, annotations: annotations) }

    private func pushUndo() {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    private func restore(_ state: Snapshot) {
        baseImage = state.baseImage
        annotations = state.annotations
        selectedIndex = nil
        needsDisplay = true
        onChange?()
    }

    /// 裁剪：立即把底图换成裁剪区域；标注随之平移，完全落在外面的丢掉，剩下的夹到边界内
    private func applyCrop(_ rect: CGRect) {
        guard let baseImage else { return }
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
        redoStack.append(snapshot)
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
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

    private func beginTextInput(at point: CGPoint) {
        window?.makeKey()
        pendingTextPoint = point
        let view = viewPoint(point)
        let field = NSTextField(frame: NSRect(x: view.x, y: view.y - 8, width: 260, height: 38))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        field.textColor = color
        field.placeholderString = L("输入文字")
        field.delegate = self
        field.target = self
        field.action = #selector(textCommitted)
        addSubview(field)
        activeField = field
        window?.makeFirstResponder(field)
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitActiveField() }
    @objc private func textCommitted() { commitActiveField() }

    private func commitActiveField() {
        guard let field = activeField else { return }
        let text = field.stringValue
        let textColor = field.textColor ?? color
        let point = pendingTextPoint
        field.removeFromSuperview()
        activeField = nil
        if !text.isEmpty {
            commit(Annotation(tool: .text, points: [point], text: text, color: textColor))
        }
        needsDisplay = true
    }

    // MARK: 导出（把标注烘焙进底图，供图片编辑器保存/复制）

    /// 新建一个 1:1 的同内容画布渲染成图，再按裁剪框裁切。
    func renderedImage() -> CGImage? {
        guard let baseImage else { return nil }
        let copy = AnnotationCanvas(frame: NSRect(origin: .zero, size: imageSize))
        copy.baseImage = baseImage
        copy.annotations = annotations
        copy.cropRect = cropRect
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
        if let cropRect {
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
