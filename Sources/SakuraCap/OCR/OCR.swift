import AppKit
import CoreText
import Vision

/// 用系统 Vision 做离线文字识别（截图 OCR）。
enum OCR {
    /// 识别结果：区分「没识别到字」和「识别引擎出错」，
    /// 否则 macOS 的 TextRecognition/ANE 异常会伪装成「未识别到文字」，很难排查。
    enum Outcome {
        case text(String)
        case empty
        case failed(Error)
    }

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

    static func recognize(_ image: CGImage) async -> Outcome {
        let prepared = preparedImage(image)
        switch await attempt(prepared) {
        case .success(let text):
            return text.isEmpty ? .empty : .text(text)
        case .failure(let error):
            Log.app.error("OCR 失败(第 1 次): \(describe(error), privacy: .public) image=\(image.width)x\(image.height, privacy: .public)")
        }
        // macOS 26/27 的 TextRecognition 走 ANE（E5RT），偶发 E5RT Code 13 等错误；
        // 稍等重试一次通常能恢复，失败时再如实报错。
        try? await Task.sleep(nanoseconds: 200_000_000)
        switch await attempt(prepared) {
        case .success(let text):
            Log.app.notice("OCR 重试成功")
            return text.isEmpty ? .empty : .text(text)
        case .failure(let error):
            Log.app.error("OCR 失败(第 2 次): \(describe(error), privacy: .public)")
            return .failed(error)
        }
    }

    private static func attempt(_ image: CGImage) async -> Result<String, Error> {
        await Task.detached(priority: .userInitiated) {
            let request = makeRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                return .success(lines.joined(separator: "\n"))
            } catch {
                return .failure(error)
            }
        }.value
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) code=\(ns.code): \(ns.localizedDescription)"
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
            Log.app.debug("OCR 预热完成")
        } catch {
            // 预热失败意味着后续 OCR 大概率也会失败，用 error 级别便于排查（ANE/E5RT 故障）。
            Log.app.error("OCR 预热失败: \(describe(error), privacy: .public)")
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
