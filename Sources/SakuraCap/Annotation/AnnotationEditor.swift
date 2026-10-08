import AppKit

/// 截屏后的标注编辑器：底图为刚截的图，可标注/裁剪/马赛克，然后「保存」或「拷贝」到剪贴板。
@MainActor
final class AnnotationEditorController: NSObject {
    static let shared = AnnotationEditorController()
    private var editors: [AnnotationEditorWindow] = []

    func open(image: CGImage, suggestedName: String) {
        NSApp.activate(ignoringOtherApps: true)
        let editor = AnnotationEditorWindow(image: image, suggestedName: suggestedName) { [weak self] window in
            self?.editors.removeAll { $0 === window }
        }
        editors.append(editor)
        editor.makeKeyAndOrderFront(nil)
    }
}

final class AnnotationEditorWindow: NSWindow {
    private let canvas = AnnotationCanvas(frame: .zero)
    private let image: CGImage
    private let suggestedName: String
    private let onClose: ((AnnotationEditorWindow) -> Void)?

    private let toolSegment = NSSegmentedControl()
    private let mosaicSegment = NSSegmentedControl()
    private let mosaicLabel = NSTextField(labelWithString: L("马赛克"))
    private let mosaicStrengthLabel = NSTextField(labelWithString: L("程度"))
    private let mosaicStrengthSlider = NSSlider()
    private let mosaicStrengthValue = NSTextField(labelWithString: "4")
    private let colorWell = NSColorWell()
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let widthLabel = NSTextField(labelWithString: L("粗细"))
    private let widthSlider = NSSlider()
    private let widthValue = NSTextField(labelWithString: "4")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let deleteButton = NSButton()
    private let ocrButton = NSButton()
    private let barcodeButton = NSButton()
    private let translateButton = NSButton()
    private var isOCRBusy = false
    private var isBarcodeBusy = false
    private var isTranslationBusy = false

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if modifiers.contains(.shift) { canvas.redo() } else { canvas.undo() }
            refresh()
            return
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "y" {
            canvas.redo()
            refresh()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            canvas.deleteSelected()
            refresh()
            return
        }
        super.keyDown(with: event)
    }

    private let allTools = AnnotationTool.allCases

    init(image: CGImage, suggestedName: String, onClose: @escaping (AnnotationEditorWindow) -> Void) {
        self.image = image
        self.suggestedName = suggestedName
        self.onClose = onClose

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let toolbarHeight: CGFloat = 52
        let maxW = visible.width * 0.9
        let maxH = visible.height * 0.82
        let scale = min(1, min(maxW / CGFloat(image.width), (maxH - toolbarHeight) / CGFloat(image.height)))
        // 和全屏截图一样给一个宽裕的窗口，长图也不会把工具栏挤重叠
        let width = min(max(CGFloat(image.width) * scale, 900), visible.width * 0.92)
        let contentSize = NSSize(width: width,
                                 height: max(420, min(maxH, CGFloat(image.height) * scale + toolbarHeight)))

        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = L("标注图片")
        isReleasedWhenClosed = false
        sharingType = .none
        canvas.baseImage = image
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onRecognitionSelection = { [weak self] action, rect in
            self?.recognize(action, in: rect)
        }
        canvas.onColorPicked = { [weak self] color in
            guard let self else { return }
            self.colorWell.color = color
            self.canvas.applyColor(color)
            let hex = color.hexString
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            Toast.show(title: L("已吸取颜色"), detail: hex)
        }

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        let bar = buildToolbar()
        let actions = buildQuickActions()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)
        container.addSubview(actions)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: actions.leadingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bar.topAnchor),
            actions.topAnchor.constraint(equalTo: container.topAnchor),
            actions.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: bar.topAnchor),
            actions.widthAnchor.constraint(equalToConstant: 56),
        ])
        contentView = container
        // 保证宽度至少能放下工具栏（按“马赛克”控件显示时的最宽状态量），避免按钮重叠
        mosaicLabel.isHidden = false
        mosaicSegment.isHidden = false
        mosaicStrengthLabel.isHidden = false
        mosaicStrengthSlider.isHidden = false
        mosaicStrengthValue.isHidden = false
        // 马赛克模式不会同时显示“粗细”，量宽度时按最宽的马赛克状态算
        widthLabel.isHidden = true
        widthSlider.isHidden = true
        widthValue.isHidden = true
        bar.layoutSubtreeIfNeeded()
        let neededWidth = bar.fittingSize.width
        if neededWidth > frame.width {
            setContentSize(NSSize(width: min(neededWidth, visible.width * 0.96), height: frame.height))
        }
        center()
        refresh()
    }

    private func buildToolbar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        toolSegment.segmentCount = allTools.count
        toolSegment.trackingMode = .selectOne
        for (index, tool) in allTools.enumerated() {
            let image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: nil)
            toolSegment.setImage(image, forSegment: index)
            toolSegment.setWidth(30, forSegment: index)
        }
        toolSegment.selectedSegment = 0
        toolSegment.target = self
        toolSegment.action = #selector(toolChanged)

        mosaicSegment.segmentCount = MosaicStyle.allCases.count
        mosaicSegment.trackingMode = .selectOne
        for (index, style) in MosaicStyle.allCases.enumerated() {
            mosaicSegment.setLabel(style.label, forSegment: index)
            mosaicSegment.setWidth(54, forSegment: index)
        }
        mosaicSegment.selectedSegment = 0
        mosaicSegment.target = self
        mosaicSegment.action = #selector(mosaicChanged)

        mosaicStrengthSlider.minValue = 1
        mosaicStrengthSlider.maxValue = 10
        mosaicStrengthSlider.doubleValue = 4
        mosaicStrengthSlider.target = self
        mosaicStrengthSlider.action = #selector(mosaicStrengthChanged)
        mosaicStrengthSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        mosaicStrengthValue.widthAnchor.constraint(equalToConstant: 22).isActive = true

        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged)

        configure(undoButton, symbol: "arrow.uturn.backward", action: #selector(undoTapped))
        configure(redoButton, symbol: "arrow.uturn.forward", action: #selector(redoTapped))
        configure(deleteButton, symbol: "trash", action: #selector(deleteTapped))

        widthSlider.minValue = 1
        widthSlider.maxValue = 20
        widthSlider.doubleValue = 4
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        widthValue.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let copyButton = NSButton(title: L("拷贝"), target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        let clearButton = NSButton(title: L("清空"), target: self, action: #selector(clearTapped))
        clearButton.bezelStyle = .rounded

        let zoomOutButton = NSButton(title: "−", target: self, action: #selector(zoomOutTapped))
        zoomOutButton.bezelStyle = .rounded
        let zoomInButton = NSButton(title: "+", target: self, action: #selector(zoomInTapped))
        zoomInButton.bezelStyle = .rounded
        let fitButton = NSButton(title: L("适应"), target: self, action: #selector(fitTapped))
        fitButton.bezelStyle = .rounded
        let pinButton = NSButton(title: L("定住"), target: self, action: #selector(pinTapped))
        pinButton.bezelStyle = .rounded
        let compareButton = NSButton()
        configure(compareButton, symbol: "rectangle.split.2x1", action: #selector(compareTapped))
        compareButton.toolTip = L("截图对比：再截一张并排对比")
        let eyedropperButton = NSButton()
        configure(eyedropperButton, symbol: "eyedropper", action: #selector(eyedropperTapped))
        eyedropperButton.toolTip = L("吸管：点击图片取色并复制 HEX")
        let measureButton = NSButton()
        configure(measureButton, symbol: "ruler", action: #selector(measureTapped))
        measureButton.toolTip = L("测量：点击两个点量距离（像素）")
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        zoomLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let saveButton = NSButton(title: L("保存"), target: self, action: #selector(saveTapped))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [toolSegment, mosaicLabel, mosaicSegment,
                                        mosaicStrengthLabel, mosaicStrengthSlider, mosaicStrengthValue,
                                        colorWell,
                                        widthLabel, widthSlider, widthValue, undoButton, redoButton,
                                        deleteButton, clearButton, spacer,
                                        zoomOutButton, zoomLabel, zoomInButton, fitButton, pinButton,
                                        compareButton, eyedropperButton, measureButton, copyButton, saveButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func buildQuickActions() -> NSView {
        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        for (button, symbol, label, action) in [
            (ocrButton, "text.viewfinder", L("取字"), #selector(ocrTapped)),
            (barcodeButton, "qrcode.viewfinder", L("二维码"), #selector(barcodeTapped)),
            (translateButton, "character.bubble", L("翻译"), #selector(translateTapped)),
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular))
            button.imagePosition = .imageOnly
            button.bezelStyle = .rounded
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
        ocrButton.toolTip = L("拖拽框选图片中的文字并复制到剪贴板")
        barcodeButton.toolTip = L("拖拽框选要识别的二维码")
        translateButton.toolTip = L("拖拽框选要翻译的文字")
        let stack = NSStackView(views: [ocrButton, barcodeButton, translateButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            stack.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
        ])
        return panel
    }

    private func configure(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func refresh() {
        let showMosaic = canvas.tool == .mosaic
        mosaicLabel.isHidden = !showMosaic
        mosaicSegment.isHidden = !showMosaic
        mosaicStrengthLabel.isHidden = !showMosaic
        mosaicStrengthSlider.isHidden = !showMosaic
        mosaicStrengthValue.isHidden = !showMosaic
        // 马赛克不需要线宽，用同一条位置换成“程度”滑块
        widthLabel.isHidden = showMosaic
        widthSlider.isHidden = showMosaic
        widthValue.isHidden = showMosaic
        let strength = canvas.currentMosaicStrength
        mosaicStrengthSlider.doubleValue = Double(strength)
        mosaicStrengthValue.stringValue = "\(Int(strength.rounded()))"
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
        zoomLabel.stringValue = "\(Int((canvas.zoom * 100).rounded()))%"
    }

    @objc private func toolChanged() {
        guard let tool = allTools[safe: toolSegment.selectedSegment] else { return }
        canvas.tool = tool
        refresh()
    }
    @objc private func mosaicChanged() {
        guard let style = MosaicStyle(rawValue: mosaicSegment.selectedSegment) else { return }
        canvas.applyMosaicStyle(style)
    }
    @objc private func mosaicStrengthChanged() {
        let value = CGFloat(mosaicStrengthSlider.doubleValue)
        mosaicStrengthValue.stringValue = "\(Int(value.rounded()))"
        canvas.applyMosaicStrength(value)
    }
    @objc private func colorChanged() { canvas.applyColor(colorWell.color) }
    @objc private func widthChanged() {
        let value = CGFloat(widthSlider.doubleValue)
        widthValue.stringValue = "\(Int(value))"
        canvas.applyLineWidth(value)
    }
    @objc private func deleteTapped() { canvas.deleteSelected(); refresh() }
    @objc private func clearTapped() { canvas.clearAll(); refresh() }
    @objc private func zoomInTapped() { canvas.zoomIn(); refresh() }
    @objc private func zoomOutTapped() { canvas.zoomOut(); refresh() }
    @objc private func fitTapped() { canvas.resetZoom(); refresh() }
    @objc private func pinTapped() {
        guard let cg = canvas.renderedImage() else { return }
        PinnedImageController.shared.pin(cg)
        close()
    }

    /// 吸管：一次性点击取色
    @objc private func eyedropperTapped() {
        canvas.beginColorPick()
        Toast.show(title: L("点击图片取色"), detail: L("按 Esc 可取消"))
    }

    /// 测量：点击两个点量距离
    @objc private func measureTapped() {
        canvas.beginMeasure()
        Toast.show(title: L("点击两个点测量距离（像素）"), detail: L("按 Esc 可取消"))
    }

    /// 截图对比：用当前底图打开对比窗口
    @objc private func compareTapped() {
        guard let image = canvas.baseImage else { return }
        CompareController.shared.open(original: image)
    }

    @objc private func ocrTapped() { beginRecognition(.ocr, prompt: L("拖拽框选要识别的文字")) }
    @objc private func barcodeTapped() { beginRecognition(.barcode, prompt: L("拖拽框选要识别的二维码")) }
    @objc private func translateTapped() { beginRecognition(.translate, prompt: L("拖拽框选要翻译的文字")) }

    private func beginRecognition(_ action: AnnotationCanvas.RecognitionAction, prompt: String) {
        if canvas.recognitionAction == action { canvas.endRecognitionSelection(); return }
        canvas.beginRecognitionSelection(action)
        Toast.show(title: prompt, detail: L("按 Esc 可取消"))
    }

    private func recognize(_ action: AnnotationCanvas.RecognitionAction, in rect: CGRect) {
        guard let base = canvas.baseImage else { return }
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
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
        ocrButton.isEnabled = false
        Task { @MainActor in
            defer {
                isOCRBusy = false
                ocrButton.isEnabled = true
            }
            guard let text = await OCR.recognize(image) else {
                let alert = NSAlert()
                alert.messageText = L("未识别到文字")
                alert.addButton(withTitle: L("好"))
                runModalAlert(alert)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let preview = text.count > 15 ? String(text.prefix(15)) + "…" : text
            Toast.show(title: L("识别成功，已复制到剪贴板"), detail: preview)
        }
    }

    private func recognizeBarcode(_ image: CGImage) {
        guard !isBarcodeBusy else { return }
        isBarcodeBusy = true
        barcodeButton.isEnabled = false
        Task { @MainActor in
            defer {
                isBarcodeBusy = false
                barcodeButton.isEnabled = true
            }
            let codes = await Barcode.detect(image)
            guard !codes.isEmpty else {
                let alert = NSAlert()
                alert.messageText = L("未识别到二维码 / 条形码")
                alert.addButton(withTitle: L("好"))
                runModalAlert(alert)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(codes.joined(separator: "\n"), forType: .string)
            Toast.show(title: L("识别成功，已复制到剪贴板"), detail: codes[0])
        }
    }

    private func translate(_ image: CGImage) {
        guard !isTranslationBusy else { return }
        isTranslationBusy = true
        translateButton.isEnabled = false
        Task { @MainActor in
            defer {
                isTranslationBusy = false
                translateButton.isEnabled = true
            }
            guard let original = await OCR.recognize(image) else {
                let alert = NSAlert()
                alert.messageText = L("未识别到文字")
                alert.addButton(withTitle: L("好"))
                runModalAlert(alert)
                return
            }
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

    @objc private func undoTapped() { canvas.undo(); refresh() }
    @objc private func redoTapped() { canvas.redo(); refresh() }

    @objc private func saveTapped() {
        guard let cg = canvas.renderedImage(),
              let dir = OutputDirectoryPicker.ensureDirectory(current: AppSettings.shared.outputDirectory),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        let url = dir.appendingPathComponent(suggestedName)
        try? data.write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        CompletionNotifier.shared.postSavedImage(url: url)
        close()
    }

    @objc private func copyTapped() {
        guard let cg = canvas.renderedImage() else { return }
        let nsImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        close()
    }

    override func close() {
        super.close()
        onClose?(self)
    }
}

private extension NSColor {
    /// sRGB 十六进制，如 #FF2D55
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
