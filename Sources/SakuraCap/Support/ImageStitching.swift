import AppKit
import ImageIO
import UniformTypeIdentifiers

struct StitchImage: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let pixelSize: CGSize
    let preview: CGImage
    var frame: CGRect
}

enum StitchBackground: Int, CaseIterable, Sendable {
    case transparent, white, black

    var title: String {
        switch self {
        case .transparent: return L("透明背景")
        case .white: return L("白色背景")
        case .black: return L("黑色背景")
        }
    }
}

struct StitchDocument: Sendable {
    static let imageLimit = 32
    static let pixelLimit: CGFloat = 24_000_000
    static let edgeLimit: CGFloat = 32_768
    var images: [StitchImage] = []
    var background: StitchBackground = .transparent

    var bounds: CGRect {
        images.reduce(CGRect.null) { $0.union($1.frame) }
    }

    // Outward rounding keeps subpixel placements from cropping an image edge.
    var outputBounds: CGRect { images.isEmpty ? .zero : bounds.integral }

    var canExport: Bool {
        let size = outputBounds.size
        return size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
            && size.width <= Self.edgeLimit && size.height <= Self.edgeLimit
            && size.width * size.height <= Self.pixelLimit
    }

    mutating func append(_ imported: [StitchImage], gap: CGFloat) {
        var x = images.isEmpty ? 0 : bounds.maxX + gap
        let y = images.isEmpty ? 0 : bounds.minY
        for var image in imported.prefix(max(0, Self.imageLimit - images.count)) {
            image.frame.origin = CGPoint(x: x, y: y)
            images.append(image)
            x = image.frame.maxX + gap
        }
    }

    mutating func arrange(vertical: Bool, gap: CGFloat) {
        var offset: CGFloat = 0
        for index in images.indices {
            images[index].frame.origin = vertical ? CGPoint(x: 0, y: offset) : CGPoint(x: offset, y: 0)
            offset += (vertical ? images[index].frame.height : images[index].frame.width) + gap
        }
    }

    static func resizedFrame(_ image: StitchImage, scale: CGFloat) -> CGRect {
        let scale = min(8, max(0.01, scale))
        return CGRect(origin: image.frame.origin,
                      size: CGSize(width: image.pixelSize.width * scale, height: image.pixelSize.height * scale))
    }
}

enum StitchFailure: LocalizedError {
    case unreadable(String), sourceTooLarge, tooLarge, encoding

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return String(format: L("无法读取图片：%@"), name)
        case .sourceTooLarge: return L("源图片过大，请先缩小到 6400 万像素以内。")
        case .tooLarge: return L("拼接结果过大。请缩小图片或减少间距；最多支持 2400 万像素，单边不超过 32768 像素。")
        case .encoding: return L("无法生成图片，请检查保存位置和可用空间。")
        }
    }
}

enum StitchRenderer {
    static func load(_ url: URL) throws -> StitchImage {
        try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                  width.isFinite, height.isFinite, width > 0, height > 0 else {
                throw StitchFailure.unreadable(url.lastPathComponent)
            }
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            guard width * height <= 64_000_000 else { throw StitchFailure.sourceTooLarge }
            let size = (5...8).contains(orientation)
                ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
            guard let preview = thumbnail(source, maxEdge: 640) else {
                throw StitchFailure.unreadable(url.lastPathComponent)
            }
            return StitchImage(id: UUID(), url: url, pixelSize: size, preview: preview,
                               frame: CGRect(origin: .zero, size: size))
        }
    }

    private static func thumbnail(_ source: CGImageSource, maxEdge: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    static func render(_ document: StitchDocument) throws -> CGImage {
        try Task.checkCancellation()
        guard document.canExport else { throw StitchFailure.tooLarge }
        let bounds = document.outputBounds
        guard let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw StitchFailure.tooLarge
        }
        context.clear(CGRect(origin: .zero, size: bounds.size))
        if document.background != .transparent {
            let white: CGFloat = document.background == .white ? 1 : 0
            context.setFillColor(CGColor(gray: white, alpha: 1))
            context.fill(CGRect(origin: .zero, size: bounds.size))
        }
        context.interpolationQuality = .high
        for image in document.images {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(image.url as CFURL,
                                                              [kCGImageSourceShouldCache: false] as CFDictionary) else {
                    throw StitchFailure.unreadable(image.url.lastPathComponent)
                }
                // Decode only as much as the placed image needs, one original at a time.
                let longest = max(image.pixelSize.width, image.pixelSize.height)
                let budgetEdge = sqrt(StitchDocument.pixelLimit /
                    (image.pixelSize.width * image.pixelSize.height)) * longest
                let edge = max(1, min(longest, max(image.frame.width, image.frame.height), budgetEdge).rounded(.up))
                guard let decoded = thumbnail(source, maxEdge: Int(min(edge, StitchDocument.edgeLimit))) else {
                    throw StitchFailure.unreadable(image.url.lastPathComponent)
                }
                let rect = CGRect(x: image.frame.minX - bounds.minX, y: bounds.maxY - image.frame.maxY,
                                  width: image.frame.width, height: image.frame.height)
                context.draw(decoded, in: rect)
            }
        }
        guard let result = context.makeImage() else { throw StitchFailure.encoding }
        return result
    }

    static func pngData(_ document: StitchDocument) throws -> Data {
        let image = try render(document)
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StitchFailure.encoding
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StitchFailure.encoding }
        return data as Data
    }
}
