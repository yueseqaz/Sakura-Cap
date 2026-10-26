import AppKit

/// Commands and service integrations shared by the window and in-place presentations.
@MainActor
final class AnnotationEditorActions: NSObject {
    let canvas: AnnotationCanvas
    var renderImage: () -> CGImage?
    var recognitionBounds: () -> CGRect? = { nil }
    var onClose: () -> Void
    var onChange: (() -> Void)?
    var suspend: () -> Void = {}
    var resume: () -> Void = {}
    var preparePresentation: () -> Void = {}
    var isValid: () -> Bool = { true }
    var notify: (String, String?) -> Void = { Toast.show(title: $0, detail: $1) }
    weak var askAIButton: NSButton?
    let suggestedName: String
    private(set) var isOCRBusy = false
    private(set) var isBarcodeBusy = false
    private(set) var isTranslationBusy = false
    private(set) var isUploadBusy = false

    init(canvas: AnnotationCanvas, suggestedName: String,
         renderImage: @escaping () -> CGImage?, onClose: @escaping () -> Void) {
        self.canvas = canvas
        self.suggestedName = suggestedName
        self.renderImage = renderImage
        self.onClose = onClose
    }

    func pickColor(_ color: NSColor) {
        canvas.applyColor(color)
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                         Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        notify(L("已吸取颜色"), hex)
    }

    private func showAlert(_ alert: NSAlert) {
        suspend()
        defer { resume() }
        runModalAlert(alert)
    }

    private func showFailure(_ error: Error) {
        suspend()
        defer { resume() }
        showOCRFailureAlert(error)
    }

    @objc func pinTapped() {
        guard let cg = renderImage() else { return }
        onClose()
        PinnedImageController.shared.pin(cg)
    }

    /// 吸管：一次性点击取色
    @objc func eyedropperTapped() {
        canvas.finishTextEditing()
        canvas.beginColorPick()
        notify(L("点击图片取色"), L("按 Esc 可取消"))
    }

    /// 测量：点击两个点量距离
    @objc func measureTapped() {
        canvas.finishTextEditing()
        canvas.beginMeasure()
        notify(L("点击两个点测量距离（像素）"), L("按 Esc 可取消"))
    }

    @objc func askAITapped() {
        let menu = NSMenu()
        let imageItem = NSMenuItem(title: L("图片提问"), action: #selector(askAIWithImage), keyEquivalent: "")
        imageItem.target = self
        let ocrItem = NSMenuItem(title: L("OCR 文字提问"), action: #selector(askAIWithOCR), keyEquivalent: "")
        ocrItem.target = self
        menu.addItem(imageItem)
        menu.addItem(ocrItem)
        if let event = NSApp.currentEvent, let askAIButton {
            NSMenu.popUpContextMenu(menu, with: event, for: askAIButton)
        }
    }

    /// 整图（含标注）发给 AI 聊天窗口
    @objc func askAIWithImage() {
        guard let cg = renderImage() else { return }
        preparePresentation()
        AIChatPresenter.shared.openWithImage(cg)
    }

    /// 先 OCR 整图，识别出的文字带进 AI 聊天窗口（适配不支持图片的模型）
    @objc func askAIWithOCR() {
        guard let cg = renderImage() else { return }
        Task { @MainActor in
            let result = await OCR.recognize(cg)
            guard isValid() else { return }
            switch result {
            case .text(let text):
                preparePresentation()
                AIChatPresenter.shared.openWithText(text)
            case .empty: notify(L("未识别到文字"), nil)
            case .failed(let error): notify(L("识别失败"), error.localizedDescription)
            }
        }
    }

    @objc func ocrTapped() { beginRecognition(.ocr, prompt: L("拖拽框选要识别的文字")) }
    @objc func barcodeTapped() { beginRecognition(.barcode, prompt: L("拖拽框选要识别的二维码")) }
    @objc func translateTapped() { beginRecognition(.translate, prompt: L("拖拽框选要翻译的文字")) }

    private func beginRecognition(_ action: AnnotationCanvas.RecognitionAction, prompt: String) {
        if canvas.recognitionAction == action { canvas.endRecognitionSelection(); return }
        canvas.finishTextEditing()
        canvas.beginRecognitionSelection(action)
        notify(prompt, L("按 Esc 可取消"))
    }

    func recognize(_ action: AnnotationCanvas.RecognitionAction, in rect: CGRect) {
        guard let base = canvas.baseImage else { return }
        let bounds = recognitionBounds() ?? CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let clipped = rect.integral.intersection(bounds)
        guard clipped.width >= 2, clipped.height >= 2,
              let image = base.cropping(to: clipped) else { return }
        switch action {
        case .ocr: recognizeOCR(image)
        case .barcode: recognizeBarcode(image)
        case .translate: translate(image)
        }
    }

    /// 对框选区域识别文字并复制到剪贴板
    private func recognizeOCR(_ image: CGImage) {
        guard !isOCRBusy else { return }
        isOCRBusy = true
        onChange?()
        Task { @MainActor in
            defer {
                isOCRBusy = false
                onChange?()
            }
            let result = await OCR.recognize(image)
            guard isValid() else { return }
            switch result {
            case .empty:
                let alert = NSAlert()
                alert.messageText = L("未识别到文字")
                alert.addButton(withTitle: L("好"))
                showAlert(alert)
            case .failed(let error):
                showFailure(error)
            case .text(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                let preview = text.count > 15 ? String(text.prefix(15)) + "…" : text
                notify(L("识别成功，已复制到剪贴板"), preview)
            }
        }
    }

    private func recognizeBarcode(_ image: CGImage) {
        guard !isBarcodeBusy else { return }
        isBarcodeBusy = true
        onChange?()
        Task { @MainActor in
            defer {
                isBarcodeBusy = false
                onChange?()
            }
            let codes = await Barcode.detect(image)
            guard isValid() else { return }
            guard !codes.isEmpty else {
                let alert = NSAlert()
                alert.messageText = L("未识别到二维码或条形码")
                alert.addButton(withTitle: L("好"))
                showAlert(alert)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(codes.joined(separator: "\n"), forType: .string)
            notify(L("识别成功，已复制到剪贴板"), codes[0])
        }
    }

    private func translate(_ image: CGImage) {
        guard !isTranslationBusy else { return }
        isTranslationBusy = true
        onChange?()
        Task { @MainActor in
            defer {
                isTranslationBusy = false
                onChange?()
            }
            let result = await OCR.recognize(image)
            guard isValid() else { return }
            switch result {
            case .empty:
                let alert = NSAlert()
                alert.messageText = L("未识别到文字")
                alert.addButton(withTitle: L("好"))
                showAlert(alert)
                return
            case .failed(let error):
                showFailure(error)
                return
            case .text(let original):
                preparePresentation()
                let model = TranslationPresenter.shared.present(original: original)
                model.isLoading = true
                do {
                    model.translation = try await TranslationService.translate(original, config: AppSettings.shared.translationConfig)
                } catch {
                    model.error = error.localizedDescription
                }
                model.isLoading = false
            }
        }
    }

    /// 上传整图（含标注）到图床，成功后按设置格式复制链接
    @objc func uploadTapped() {
        guard !isUploadBusy else { return }
        guard ImageHost.isConfigured else {
            notify(L("图床未配置"), L("请到 设置 → 图床 配置后再上传"))
            return
        }
        guard let cg = renderImage(),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        isUploadBusy = true
        onChange?()
        notify(L("正在上传图床…"), nil)
        Task { @MainActor in
            defer {
                isUploadBusy = false
                onChange?()
            }
            do {
                let link = try await ImageHost.upload(png: data)
                guard isValid() else { return }
                let text = AppSettings.shared.imageHostLinkFormat.text(url: link)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                notify(L("已上传，链接已复制"), link)
            } catch {
                guard isValid() else { return }
                let detail = (error as? ImageHostError)?.errorDescription ?? error.localizedDescription
                Log.app.error("图床上传失败: \(detail, privacy: .public)")
                notify(L("上传失败"), detail)
            }
        }
    }

    @objc func undoTapped() { canvas.undo(); onChange?() }
    @objc func redoTapped() { canvas.redo(); onChange?() }

    @objc func saveTapped() {
        guard let cg = renderImage(),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        suspend()
        defer { resume() }
        guard let dir = OutputDirectoryPicker.ensureDirectory(current: AppSettings.shared.outputDirectory) else { return }
        let url = dir.appendingPathComponent(suggestedName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // 保存失败绝不能假装成功：不弹 Finder、不发已保存通知、不关窗，留着让用户重试
            Log.app.error("截图保存失败: \(url.path, privacy: .public) \(error.localizedDescription, privacy: .public)")
            notify(L("保存失败"), error.localizedDescription)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        CompletionNotifier.shared.postSavedImage(url: url)
        onClose()
    }

    @objc func copyTapped() {
        guard let cg = renderImage() else { return }
        let nsImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([nsImage]) else { return }
        onClose()
    }

}
