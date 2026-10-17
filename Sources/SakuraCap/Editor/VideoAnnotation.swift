import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum VideoMarkTool: String, CaseIterable, Identifiable {
    case select, pen, arrow, oval, rectangle, text, mosaic, number

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil"
        case .arrow: return "arrow.up.right"
        case .oval: return "circle"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3.fill"
        case .number: return "1.circle.fill"
        }
    }
    var label: String {
        switch self {
        case .select: return L("选择 / 移动")
        case .pen: return L("画笔")
        case .arrow: return L("箭头")
        case .oval: return L("圆圈")
        case .rectangle: return L("矩形")
        case .text: return L("文字")
        case .mosaic: return L("马赛克")
        case .number: return L("序号")
        }
    }
}

/// Coordinates are normalized to the visible video frame, not to the editor window.
struct VideoMark {
    var tool: VideoMarkTool
    var points: [CGPoint]
    var text: String = ""
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var mosaicStyle: MosaicStyle = .pixelate
}

final class VideoAnnotationCanvas: NSView, NSTextFieldDelegate {
    var tool: VideoMarkTool = .pen
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var mosaicStyle: MosaicStyle = .pixelate
    var marks: [VideoMark] = [] { didSet { needsDisplay = true } }
    var previewFrame: CGImage? { didSet { needsDisplay = true } }
    var onChange: (() -> Void)?
    private var current: VideoMark?
    private(set) var selectedIndex: Int?
    private var dragLast: CGPoint?
    private var movedSelection = false
    private var field: NSTextField?
    private var textPoint = CGPoint.zero
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private(set) var undoStack: [[VideoMark]] = []

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        marks = previous
        selectedIndex = nil
        onChange?()
    }

    func loadMarks(_ saved: [VideoMark]) {
        marks = saved
        undoStack = []
        selectedIndex = nil
        needsDisplay = true
    }

    func clear() {
        guard !marks.isEmpty else { return }
        undoStack.append(marks)
        marks = []
        selectedIndex = nil
        onChange?()
    }

    func deleteSelected() {
        guard let index = selectedIndex, marks.indices.contains(index) else { return }
        undoStack.append(marks)
        marks.remove(at: index)
        selectedIndex = nil
        onChange?()
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / max(bounds.width, 1))),
                y: min(1, max(0, point.y / max(bounds.height, 1))))
    }

    override func mouseDown(with event: NSEvent) {
        if field != nil { commitText() }
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        if tool == .select {
            let point = normalized(p)
            selectedIndex = marks.indices.reversed().first { index in
                let mark = marks[index]
                guard let first = mark.points.first else { return false }
                let box: CGRect
                if mark.points.count < 2 || mark.tool == .number || mark.tool == .text {
                    box = CGRect(x: first.x - 0.025, y: first.y - 0.04, width: 0.05, height: 0.08)
                } else {
                    box = Self.rect(for: mark, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                        .insetBy(dx: -0.015, dy: -0.025)
                }
                return box.contains(point)
            }
            dragLast = selectedIndex == nil ? nil : point
            movedSelection = false
            needsDisplay = true
            onChange?()
        } else if tool == .text {
            textPoint = normalized(p)
            let input = NSTextField(frame: CGRect(x: p.x, y: p.y - 12, width: 230, height: 32))
            input.placeholderString = L("输入标注文字")
            input.font = .boldSystemFont(ofSize: 20)
            input.delegate = self
            input.target = self
            input.action = #selector(commitText)
            addSubview(input)
            field = input
            window?.makeFirstResponder(input)
        } else if tool == .number {
            undoStack.append(marks)
            let next = marks.filter { $0.tool == .number }.count + 1
            marks.append(VideoMark(tool: .number, points: [normalized(p)], text: "\(next)", color: color))
            onChange?()
        } else {
            let point = normalized(p)
            current = VideoMark(tool: tool, points: [point, point], color: color,
                                lineWidth: lineWidth, mosaicStyle: mosaicStyle)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if tool == .select, let index = selectedIndex, marks.indices.contains(index), let last = dragLast {
            let point = normalized(convert(event.locationInWindow, from: nil))
            if !movedSelection { undoStack.append(marks); movedSelection = true }
            let dx = point.x - last.x, dy = point.y - last.y
            marks[index].points = marks[index].points.map {
                CGPoint(x: min(1, max(0, $0.x + dx)), y: min(1, max(0, $0.y + dy)))
            }
            dragLast = point
            return
        }
        guard var mark = current else { return }
        let point = normalized(convert(event.locationInWindow, from: nil))
        if mark.tool == .pen { mark.points.append(point) }
        else { mark.points[1] = point }
        current = mark
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if tool == .select {
            dragLast = nil
            if movedSelection { onChange?() }
            return
        }
        guard let mark = current else { return }
        current = nil
        guard mark.points.count >= 2,
              hypot(mark.points[1].x - mark.points[0].x,
                    mark.points[1].y - mark.points[0].y) > 0.005 else { return }
        undoStack.append(marks)
        marks.append(mark)
        onChange?()
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    @objc private func commitText() {
        guard let field else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        self.field = nil
        if !text.isEmpty {
            undoStack.append(marks)
            marks.append(VideoMark(tool: .text, points: [textPoint], text: text, color: color))
            onChange?()
        }
    }

    func finishEditing() { commitText() }

    override func draw(_ dirtyRect: NSRect) {
        let all = marks + (current.map { [$0] } ?? [])
        for mark in all where mark.tool == .mosaic { drawMosaic(mark) }
        Self.draw(marks: all, in: bounds)
        if let index = selectedIndex, marks.indices.contains(index) {
            let mark = marks[index]
            let box = Self.rect(for: mark, in: bounds).insetBy(dx: -8, dy: -8)
            let path = NSBezierPath(rect: box)
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
    }

    private func drawMosaic(_ mark: VideoMark) {
        guard mark.points.count >= 2 else { return }
        let rect = Self.rect(for: mark, in: bounds)
        guard rect.width >= 2, rect.height >= 2 else { return }
        guard let frame = previewFrame else {
            NSColor.systemRed.withAlphaComponent(0.25).setFill()
            NSBezierPath(rect: rect).fill()
            return
        }
        let sample = Self.rect(for: mark, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height)).integral
        guard let cropped = frame.cropping(to: sample) else { return }
        let ci = CIImage(cgImage: cropped)
        guard let output = Self.mosaic(image: ci, style: mark.mosaicStyle,
                                       region: ci.extent, scale: max(10, CGFloat(frame.width) / 110)),
              let image = ciContext.createCGImage(output, from: CIImage(cgImage: cropped).extent) else { return }
        NSImage(cgImage: image, size: rect.size).draw(in: rect)
    }

    static func mosaic(image: CIImage, style: MosaicStyle, region: CGRect, scale: CGFloat) -> CIImage? {
        switch style {
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = image
            filter.center = CGPoint(x: region.midX, y: region.midY)
            filter.scale = Float(scale)
            return filter.outputImage?.cropped(to: region)
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image.clampedToExtent()
            filter.radius = Float(scale * 0.8)
            return filter.outputImage?.cropped(to: region)
        case .hexagon:
            let filter = CIFilter.hexagonalPixellate()
            filter.inputImage = image
            filter.center = CGPoint(x: region.midX, y: region.midY)
            filter.scale = Float(scale)
            return filter.outputImage?.cropped(to: region)
        }
    }

    static func rect(for mark: VideoMark, in bounds: CGRect) -> CGRect {
        guard let first = mark.points.first, let last = mark.points.last else { return .zero }
        let x = min(first.x, last.x), y = min(first.y, last.y)
        return CGRect(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height,
                      width: abs(last.x - first.x) * bounds.width,
                      height: abs(last.y - first.y) * bounds.height)
    }

    static func draw(marks: [VideoMark], in rect: CGRect) {
        for mark in marks {
            guard let first = mark.points.first else { continue }
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
            }
            let a = point(first)
            let b = point(mark.points.last ?? first)
            let path = NSBezierPath()
            path.lineWidth = max(1, mark.lineWidth * rect.width / 800)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            mark.color.setStroke()
            switch mark.tool {
            case .select:
                break
            case .pen:
                path.move(to: a)
                for p in mark.points.dropFirst() { path.line(to: point(p)) }
            case .arrow:
                path.move(to: a); path.line(to: b)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let length = max(12, rect.width / 55)
                path.move(to: CGPoint(x: b.x - cos(angle - .pi / 6) * length,
                                      y: b.y - sin(angle - .pi / 6) * length))
                path.line(to: b)
                path.line(to: CGPoint(x: b.x - cos(angle + .pi / 6) * length,
                                      y: b.y - sin(angle + .pi / 6) * length))
            case .oval, .rectangle:
                let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                 width: abs(a.x - b.x), height: abs(a.y - b.y))
                if mark.tool == .oval { path.appendOval(in: box) }
                else { path.appendRect(box) }
            case .text:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: max(16, rect.width / 30)),
                    .foregroundColor: mark.color,
                ]
                NSAttributedString(string: mark.text, attributes: attrs).draw(at: a)
            case .number:
                let radius = max(13, rect.width / 80)
                let circle = NSBezierPath(ovalIn: CGRect(x: a.x - radius, y: a.y - radius,
                                                         width: radius * 2, height: radius * 2))
                mark.color.setFill()
                circle.fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: radius * 1.1), .foregroundColor: NSColor.white,
                ]
                let text = NSAttributedString(string: mark.text, attributes: attrs)
                let size = text.size()
                text.draw(at: CGPoint(x: a.x - size.width / 2, y: a.y - size.height / 2))
            case .mosaic:
                break
            }
            path.stroke()
        }
    }

    static func image(marks: [VideoMark], size: CGSize) -> CGImage? {
        guard marks.contains(where: { $0.tool != .mosaic }), size.width >= 1, size.height >= 1 else { return nil }
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let view = VideoAnnotationCanvas(frame: CGRect(x: 0, y: 0, width: width, height: height))
        view.marks = marks.filter { $0.tool != .mosaic }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bitmapFormat: .alphaFirst, bytesPerRow: width * 4,
                                            bitsPerPixel: 32) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage
    }
}

struct VideoAnnotationView: NSViewRepresentable {
    let canvas: VideoAnnotationCanvas
    func makeNSView(context: Context) -> VideoAnnotationCanvas { canvas }
    func updateNSView(_ view: VideoAnnotationCanvas, context: Context) {}
}
