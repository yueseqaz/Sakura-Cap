import AppKit
import CoreImage

/// 水印的铺陈方式。单个水印适合署名，全屏平铺适合版权保护。
enum WatermarkMode: String, CaseIterable, Identifiable {
    case single
    case tiled

    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return L("单个水印")
        case .tiled: return L("全屏水印")
        }
    }
}

enum WatermarkPosition: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight, centerLeft, center, centerRight, bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }
    var label: String {
        switch self {
        case .topLeft: return L("左上")
        case .topCenter: return L("顶部居中")
        case .topRight: return L("右上")
        case .centerLeft: return L("左侧居中")
        case .center: return L("正中")
        case .centerRight: return L("右侧居中")
        case .bottomLeft: return L("左下")
        case .bottomCenter: return L("底部居中")
        case .bottomRight: return L("右下")
        }
    }

    var normalizedPoint: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topCenter: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .centerLeft: return CGPoint(x: 0, y: 0.5)
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .centerRight: return CGPoint(x: 1, y: 0.5)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .bottomCenter: return CGPoint(x: 0.5, y: 1)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        }
    }
}

/// 渲染层只保存可持久化的值，避免把 NSColor/NSImage 放进剪辑文档。
struct WatermarkConfiguration: Equatable {
    var text: String = "Sakura-Cap"
    var imagePath: String?
    var mode: WatermarkMode = .single
    var position: WatermarkPosition = .bottomRight
    /// Set when the watermark is dragged directly on the annotation canvas.
    var customPosition: CGPoint?
    var opacity: CGFloat = 0.72
    var fontSize: CGFloat = 32
    /// AppKit font weight (-1 ultra-light ... 1 black), controlled by the
    /// annotation toolbar's existing 粗细 slider.
    var fontWeight: CGFloat = 0.2
    var scale: CGFloat = 1
    var rotation: CGFloat = 0
    /// A shallow shear used for the sphere's vertical tilt gesture.
    var tilt: CGFloat = 0
    var spacing: CGFloat = 1.8
    var padding: CGFloat = 28
    var colorHex: String = "#FFFFFF"
    var enabled: Bool = true

    var color: NSColor { NSColor(hex: colorHex) ?? .white }
}

enum WatermarkRenderer {
    /// Produces a transparent image at the exact output size. The generated image is
    /// shared by the editor preview and AVVideoComposition so exports match previews.
    static func image(for config: WatermarkConfiguration, size: CGSize) -> CGImage? {
        guard config.enabled, size.width >= 1, size.height >= 1,
              !config.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || config.imagePath != nil else {
            return nil
        }
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bitmapFormat: .alphaFirst, bytesPerRow: width * 4,
                                         bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let mark = markSize(config)
        if config.mode == .single {
            let anchor = config.customPosition ?? config.position.normalizedPoint
            let x = anchor.x * size.width - mark.width * anchor.x
            let yFromTop = anchor.y * size.height - mark.height * anchor.y
            drawMark(config, in: CGRect(x: x, y: size.height - yFromTop - mark.height,
                                        width: mark.width, height: mark.height), context: context)
        } else {
            let stepX = max(mark.width * config.spacing, mark.width + 1)
            let stepY = max(mark.height * config.spacing, mark.height + 1)
            var row = -2
            while CGFloat(row) * stepY < size.height + stepY {
                var column = -2
                while CGFloat(column) * stepX < size.width + stepX {
                    let x = CGFloat(column) * stepX + (row.isMultiple(of: 2) ? 0 : stepX / 2)
                    let yFromTop = CGFloat(row) * stepY
                    drawMark(config, in: CGRect(x: x, y: size.height - yFromTop - mark.height,
                                                width: mark.width, height: mark.height), context: context)
                    column += 1
                }
                row += 1
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    static func composited(_ base: CIImage, config: WatermarkConfiguration, size: CGSize) -> CIImage {
        guard let overlay = Self.image(for: config, size: size) else { return base }
        return CIImage(cgImage: overlay).composited(over: base).cropped(to: base.extent)
    }

    /// AppKit flips bitmap images once more when drawing them inside an
    /// `isFlipped` view. Keep the export/CI image in its native orientation,
    /// and use this counterpart only for the annotation canvas preview.
    static func verticallyFlipped(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func markSize(_ config: WatermarkConfiguration) -> CGSize {
        let font = NSFont.systemFont(ofSize: max(8, config.fontSize * config.scale),
                                     weight: NSFont.Weight(rawValue: max(-1, min(1, config.fontWeight))))
        let text = config.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let textSize = text.isEmpty ? .zero : (text as NSString).size(withAttributes: [.font: font])
        var width = textSize.width
        var height = textSize.height
        if let path = config.imagePath, NSImage(contentsOfFile: path) != nil {
            let imageHeight = max(12, config.fontSize * config.scale * 1.2)
            width += imageHeight + (text.isEmpty ? 0 : 8)
            height = max(height, imageHeight)
        }
        return CGSize(width: max(1, width + config.padding * 2), height: max(1, height + config.padding * 2))
    }

    private static func drawMark(_ config: WatermarkConfiguration, in rect: CGRect, context: NSGraphicsContext) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.translateBy(x: center.x, y: center.y)
        context.cgContext.rotate(by: config.rotation * .pi / 180)
        let shear = tan(max(-45, min(45, config.tilt)) * .pi / 180)
        context.cgContext.concatenate(CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: 0, ty: 0))
        context.cgContext.translateBy(x: -center.x, y: -center.y)
        let alpha = min(1, max(0, config.opacity))
        var x = rect.minX + config.padding
        let font = NSFont.systemFont(ofSize: max(8, config.fontSize * config.scale),
                                     weight: NSFont.Weight(rawValue: max(-1, min(1, config.fontWeight))))
        if let path = config.imagePath, let image = NSImage(contentsOfFile: path) {
            let h = max(12, config.fontSize * config.scale * 1.2)
            image.draw(in: CGRect(x: x, y: rect.midY - h / 2, width: h, height: h),
                       from: .zero, operation: .sourceOver, fraction: alpha)
            x += h + 8
        }
        let text = config.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: config.color.withAlphaComponent(alpha),
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: x, y: rect.midY - textSize.height / 2), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension NSColor {
    var hexString: String {
        guard let color = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X",
                      Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()))
    }

    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let divisor: CGFloat = 255
        let r = CGFloat((number >> (value.count == 8 ? 24 : 16)) & 0xFF) / divisor
        let g = CGFloat((number >> (value.count == 8 ? 16 : 8)) & 0xFF) / divisor
        let b = CGFloat((number >> (value.count == 8 ? 8 : 0)) & 0xFF) / divisor
        let a = value.count == 8 ? CGFloat(number & 0xFF) / divisor : 1
        self.init(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}
