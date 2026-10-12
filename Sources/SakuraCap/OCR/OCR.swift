import AppKit
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
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            let handler = VNImageRequestHandler(cgImage: preparedImage(image), options: [:])
            do {
                try handler.perform([request])
            } catch {
                Log.app.error("OCR 失败: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: nil)
            }
        }
    }
}
