import Foundation
import CoreGraphics
import ImageIO
import CWebP

enum ImageOutputFormat: String, CaseIterable, Sendable {
    case png = "public.png"
    case jpeg = "public.jpeg"
    case heic = "public.heic"
    case tiff = "public.tiff"
    case bmp = "com.microsoft.bmp"
    case gif = "com.compuserve.gif"
    case jpeg2000 = "public.jpeg-2000"
    case avif = "public.avif"
    case webp = "org.webmproject.webp"

    static var available: [Self] {
        let supported = Set(CGImageDestinationCopyTypeIdentifiers() as! [String])
        return allCases.filter { $0 == .webp || supported.contains($0.rawValue) }
    }

    var title: String {
        switch self {
        case .jpeg2000: return "JPEG 2000"
        case .webp: return "WebP"
        default: return String(describing: self).uppercased()
        }
    }

    var pathExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .jpeg2000: return "jp2"
        default: return String(describing: self)
        }
    }

    var supportsQuality: Bool {
        switch self {
        case .jpeg, .heic, .jpeg2000, .avif, .webp: return true
        default: return false
        }
    }

    var requiresOpaqueImage: Bool { self == .jpeg || self == .bmp }

    var supportsCompressionQuality: Bool { supportsQuality || self == .png || self == .tiff }
}

struct ImageConversionOptions: Sendable, Equatable {
    // nil keeps the source format; nil quality skips intentional quality reduction.
    var format: ImageOutputFormat?
    var quality: Double?
}

struct ImageConversionPreview: Sendable {
    let byteCount: Int
    let thumbnail: Data?
}

/// 预览和导出共用同一编码路径；串行后台执行，不在拖动滑块时阻塞主线程。
actor ImageConversionWorker {
    func estimatedSize(source: URL, options: ImageConversionOptions) throws -> Int {
        try autoreleasepool { try Self.encodedData(source: source, options: options).count }
    }

    func preview(source: URL, options: ImageConversionOptions) throws -> ImageConversionPreview {
        try autoreleasepool {
            let data = try Self.encodedData(source: source, options: options)
            try Task.checkCancellation()
            var thumbnail: Data?
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: 120,
               ] as CFDictionary) {
                let bytes = NSMutableData()
                if let destination = CGImageDestinationCreateWithData(bytes, ImageOutputFormat.png.rawValue as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    if CGImageDestinationFinalize(destination) { thumbnail = bytes as Data }
                }
            }
            return ImageConversionPreview(byteCount: data.count, thumbnail: thumbnail)
        }
    }

    func convert(source: URL, options: ImageConversionOptions) throws -> URL {
        try autoreleasepool {
            let data = try Self.encodedData(source: source, options: options)
            let folder = source.deletingLastPathComponent()
            let base = source.deletingPathExtension().lastPathComponent
            var suffix = 1
            while true {
                let name = suffix == 1 ? base : "\(base) \(suffix)"
                let ext = options.format?.pathExtension ?? source.pathExtension
                let output = folder.appendingPathComponent(name).appendingPathExtension(ext)
                do {
                    // 文件检查与写入之间也可能有同名文件产生，写入本身必须禁止覆盖。
                    try data.write(to: output, options: .withoutOverwriting)
                    return output
                } catch CocoaError.fileWriteFileExists {
                    suffix += 1
                }
            }
        }
    }

    static func encodedData(source url: URL, options: ImageConversionOptions) throws -> Data {
        try Task.checkCancellation()
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ConversionError.read }
        let sourceType = CGImageSourceGetType(source) as String?
        let keepsFormat = options.format == nil || options.format?.rawValue == sourceType
        // A no-op must be byte-for-byte, including metadata, animation and additional pages.
        if keepsFormat && (options.quality == nil || CGImageSourceGetCount(source) > 1) { return original }
        // Read-only formats (for example camera RAW) can still be kept unchanged.
        guard let format = options.format ?? ImageOutputFormat.allCases.first(where: { $0.rawValue == sourceType }) else { return original }
        // Apply EXIF orientation while retaining the original pixel dimensions.
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, max(width, height)),
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) else {
            throw ConversionError.read
        }
        try Task.checkCancellation()
        if let quality = options.quality, !format.supportsQuality,
           format.supportsCompressionQuality, quality < 1 {
            image = try quantizedImage(image, quality: quality)
        }
        if format == .webp {
            let data = try encodeWebP(image, quality: options.quality)
            return keepsFormat && data.count >= original.count ? original : data
        }
        if format.requiresOpaqueImage {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw ConversionError.write
            }
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.draw(image, in: bounds)
            guard let opaque = context.makeImage() else { throw ConversionError.write }
            image = opaque
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.rawValue as CFString, 1, nil) else {
            throw ConversionError.unsupported
        }
        var propertiesToWrite: [CFString: Any] = [:]
        if format.supportsQuality {
            propertiesToWrite[kCGImageDestinationLossyCompressionQuality] = min(max(options.quality ?? 1, 0), 1)
        }
        if format == .tiff {
            propertiesToWrite[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] // LZW
        }
        CGImageDestinationAddImage(destination, image, propertiesToWrite as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.write }
        try Task.checkCancellation()
        // Re-encoding an already optimized image can grow it dramatically. Compression
        // without a format change must never cost more bytes than the original.
        return keepsFormat && data.length >= original.count ? original : data as Data
    }

    private static func quantizedImage(_ image: CGImage, quality: Double) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data else { throw ConversionError.write }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // PNG/TIFF have no native lossy quality parameter. Reduce RGB precision,
        // never alpha or dimensions, so their lossless encoders can compress better.
        let step = max(1, Int((1 - min(max(quality, 0), 1)) * 127) + 1)
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        for y in 0..<image.height {
            try Task.checkCancellation()
            for x in 0..<image.width {
                let offset = y * context.bytesPerRow + x * 4
                let alpha = Int(pixels[offset + 3])
                guard alpha > 0 else { continue }
                for channel in 0..<3 {
                    let straight = min(255, (Int(pixels[offset + channel]) * 255 + alpha / 2) / alpha)
                    let value = min(255, ((straight + step / 2) / step) * step)
                    pixels[offset + channel] = UInt8((value * alpha + 127) / 255)
                }
            }
        }
        guard let result = context.makeImage() else { throw ConversionError.write }
        return result
    }

    private static func encodeWebP(_ image: CGImage, quality: Double?) throws -> Data {
        guard image.width <= WEBP_MAX_DIMENSION, image.height <= WEBP_MAX_DIMENSION else {
            throw ConversionError.webpDimensions
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw ConversionError.write }
        let stride = image.width * 4
        var rgba = [UInt8](repeating: 0, count: stride * image.height)
        return try rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: stride, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { throw ConversionError.write }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = bytes.bindMemory(to: UInt8.self)
            // Core Graphics 使用预乘 alpha，libwebp 的 RGBA API 需要非预乘的 sRGB 字节。
            for offset in Swift.stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Int(pixels[offset + 3])
                guard alpha > 0, alpha < 255 else { continue }
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(min(255, (Int(pixels[offset + channel]) * 255 + alpha / 2) / alpha))
                }
            }
            try Task.checkCancellation()
            var output: UnsafeMutablePointer<UInt8>?
            let count: Int
            if let quality {
                count = WebPEncodeRGBA(pixels.baseAddress, Int32(image.width), Int32(image.height), Int32(stride),
                                       Float(min(max(quality, 0), 1) * 100), &output)
            } else {
                count = WebPEncodeLosslessRGBA(pixels.baseAddress, Int32(image.width), Int32(image.height), Int32(stride), &output)
            }
            defer { WebPFree(output) }
            guard count > 0, let output else { throw ConversionError.write }
            try Task.checkCancellation()
            return Data(bytes: output, count: count)
        }
    }

    enum ConversionError: LocalizedError {
        case read, write, unsupported, webpDimensions

        var errorDescription: String? {
            switch self {
            case .read: return L("无法读取图片")
            case .write: return L("写入文件失败")
            case .unsupported: return L("此设备不支持该输出格式")
            case .webpDimensions: return L("WebP 的宽高不能超过 16383 像素，请先缩小图片或选择其他格式")
            }
        }
    }
}
