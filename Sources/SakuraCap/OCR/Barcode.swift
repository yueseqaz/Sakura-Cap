import AppKit
import Vision

/// 用系统 Vision 识别图片中的二维码 / 条形码。
enum Barcode {
    /// 返回去重后的码内容（可能多个）。
    static func detect(_ image: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let observations = request.results as? [VNBarcodeObservation] ?? []
                var seen = Set<String>()
                var payloads: [String] = []
                for observation in observations {
                    guard let value = observation.payloadStringValue, !value.isEmpty else { continue }
                    if seen.insert(value).inserted { payloads.append(value) }
                }
                continuation.resume(returning: payloads)
            }
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Log.app.error("二维码识别失败: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: [])
            }
        }
    }
}
