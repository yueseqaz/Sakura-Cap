import AppKit

/// 选区结果的统一消化点：把各 SelectionPurpose 映射到对应动作——
/// 截图 / OCR / 二维码 / 对比 / 翻译 / 滚动截屏 / 问 AI（图 | 文）/ 录制选区。
/// StatusItemController 与热键只负责发起选择（beginSelection），结果统一路由到这里，
/// 避免入口与结果处理两头都要懂全部 purpose。
@MainActor
final class CaptureIntentCoordinator {
    static let shared = CaptureIntentCoordinator()

    private weak var controller: RecordingController?

    func attach(controller: RecordingController) {
        self.controller = controller
    }

    /// 接管选区回调（应用启动时调用一次）
    func beginObservingSelection() {
        SelectionController.shared.onPicked = { [weak self] result in
            self?.handlePicked(result)
        }
        // 取消选择不应自行弹出设置窗口；只有对比功能的待截回调需要清理。
        SelectionController.shared.onCancelled = { _ in
            if SelectionController.shared.currentPurpose == .compare {
                CompareController.shared.cancelPendingCapture()
            }
        }
    }

    private func handlePicked(_ result: SelectionResult) {
        // 截图用途：不进入录制流程
        if SelectionController.shared.currentPurpose == .screenshot {
            switch result {
            case .display(let id): ScreenshotController.shared.captureDisplay(id)
            case .region(let region): ScreenshotController.shared.captureRegion(region)
            }
            return
        }
        // OCR 用途：识别文字并复制到剪贴板
        if SelectionController.shared.currentPurpose == .ocr {
            switch result {
            case .display(let id): ScreenshotController.shared.ocrDisplay(id)
            case .region(let region): ScreenshotController.shared.ocrRegion(region)
            }
            return
        }
        // 二维码：框选后识别内容并复制
        if SelectionController.shared.currentPurpose == .qr {
            if case .region(let region) = result { ScreenshotController.shared.qrRegion(region) }
            return
        }
        // 截图对比：框选第二张图
        if SelectionController.shared.currentPurpose == .compare {
            if case .region(let region) = result { ScreenshotController.shared.compareRegion(region) }
            return
        }
        // 翻译：框选区域后 OCR + AI 翻译
        if SelectionController.shared.currentPurpose == .translate {
            if case .region(let region) = result { ScreenshotController.shared.translateRegion(region) }
            return
        }
        // 滚动截屏：框选后进入长截图
        if SelectionController.shared.currentPurpose == .scrolling {
            if case .region(let region) = result { ScrollingCapture.shared.start(region: region) }
            return
        }
        // 截屏问 AI：直接给图（视觉模型）
        if SelectionController.shared.currentPurpose == .aiImage {
            Task { @MainActor in
                guard #available(macOS 14.0, *) else { return }
                let image: CGImage?
                switch result {
                case .display(let id): image = try? await ScreenshotController.shared.captureImage(displayID: id, region: nil)
                case .region(let region): image = try? await ScreenshotController.shared.captureImage(displayID: region.displayID, region: region)
                }
                if let image {
                    AIChatPresenter.shared.openWithImage(image)
                } else {
                    Toast.show(title: L("截屏失败"), detail: nil)
                }
            }
            return
        }
        // 截屏问 AI：先 OCR 再带文字（不支持图片的模型）
        if SelectionController.shared.currentPurpose == .aiOCR {
            Task { @MainActor in
                guard #available(macOS 14.0, *) else { return }
                var image: CGImage?
                switch result {
                case .display(let id): image = try? await ScreenshotController.shared.captureImage(displayID: id, region: nil)
                case .region(let region): image = try? await ScreenshotController.shared.captureImage(displayID: region.displayID, region: region)
                }
                guard let image else {
                    Toast.show(title: L("截屏失败"), detail: nil)
                    return
                }
                switch await OCR.recognize(image) {
                case .text(let text): AIChatPresenter.shared.openWithText(text)
                case .empty: Toast.show(title: L("未识别到文字"), detail: nil)
                case .failed(let error): Toast.show(title: L("识别失败"), detail: error.localizedDescription)
                }
            }
            return
        }
        // 默认（录制选区）：把选择结果写进设置并进入待开始状态
        guard let controller else { return }
        let settings = AppSettings.shared
        switch result {
        case .display(let id):
            settings.captureMode = .display
            settings.allDisplaysParallel = false
            settings.selectedDisplayID = id
        case .region(let region):
            settings.captureMode = .region
            settings.updateRegion(region)
            RegionFrameOverlay.shared.show(region: region)
        }
        // 选择完成后不立即开录：进入待开始状态，由 HUD 上的「开始录制」确认
        controller.arm()
    }
}
