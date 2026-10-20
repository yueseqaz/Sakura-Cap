import AppKit
import CoreText
import Vision

/// 用系统 Vision 做离线文字识别（截图 OCR）。
enum OCR {
    static func preparedImage(_ image: CGImage) -> CGImage {
        let shortest = min(image.width, image.height)
        guard shortest > 0 else { return image }
        let scale = min(6, max(1, Int(ceil(120.0 / Double(shortest)))))
        guard scale > 1, max(image.width, image.height) * scale <= 4096,
              let context = CGContext(data: nil, width: image.width * scale,
                                      height: image.height * scale, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * scale, height: image.height * scale))
        return context.makeImage() ?? image
    }

    static func recognize(_ image: CGImage) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let request = makeRequest()
            let handler = VNImageRequestHandler(cgImage: preparedImage(image), options: [:])
            do {
                try handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                return text.isEmpty ? nil : text
            } catch {
                Log.app.error("OCR 失败: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    static func prewarm() {
        guard let context = CGContext(data: nil, width: 256, height: 128, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 128))
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 24, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "识别 OCR", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                           .foregroundColor: CGColor(gray: 0, alpha: 1)]
        ))
        context.textPosition = CGPoint(x: 18, y: 53)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([makeRequest()])
        } catch {
            Log.app.debug("OCR 预热失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        return request
    }
}
