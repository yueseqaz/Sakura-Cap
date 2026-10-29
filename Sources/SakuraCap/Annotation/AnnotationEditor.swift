import AppKit

enum AnnotationImageSource {
    case newCapture
    case existingFile
}

/// 截屏后的标注编辑器：底图为刚截的图，可标注/裁剪/马赛克，然后「保存」或「拷贝」到剪贴板。
@MainActor
final class AnnotationEditorController: NSObject {
    static let shared = AnnotationEditorController()
    private var editors: [AnnotationEditorWindow] = []

    func open(image: CGImage, suggestedName: String, source: AnnotationImageSource) {
        NSApp.activate(ignoringOtherApps: true)
        let editor = AnnotationEditorWindow(image: image, suggestedName: suggestedName, source: source) { [weak self] window in
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
    private let source: AnnotationImageSource
    private let onClose: ((AnnotationEditorWindow) -> Void)?

    private let toolSegment = NSSegmentedControl()
    private let mosaicSegment = NSSegmentedControl()
    private let mosaicLabel = NSTextField(labelWithString: L("马赛克"))
    private let mosaicStrengthLabel = NSTextField(labelWithString: L("程度"))
    private let mosaicStrengthSlider = NSSlider()
    private let mosaicStrengthValue = NSTextField(labelWithString: "4")
    private let colorPicker = AnnotationColorPicker()
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let widthLabel = NSTextField(labelWithString: L("粗细"))
    private let widthSlider = NSSlider()
    private let widthValue = NSTextField(labelWithString: "4")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let deleteButton = NSButton()
    private let discardImageButton = NSButton()
    private let ocrButton = NSButton()
    private let barcodeButton = NSButton()
    private let translateButton = NSButton()
    private let askAIButton = NSButton()
    private let uploadButton = NSButton()
    private let eyedropperButton = NSButton()
    private let measureButton = NSButton()

    private lazy var actions = AnnotationEditorActions(canvas: canvas, suggestedName: suggestedName,
        renderImage: { [weak self] in
            self?.canvas.finishTextEditing()
            return self?.canvas.renderedImage()
        }, onClose: { [weak self] in self?.close() })

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
        if event.keyCode == 53,
           canvas.recognitionAction != nil || canvas.isPickingColor || canvas.isMeasuring || canvas.hasMeasurement {
            canvas.cancelOperation(nil)
            refresh()
            return
        }
        super.keyDown(with: event)
    }

    private let allTools = AnnotationTool.allCases.filter { $0 != .magnifier }
    private let magnifierButton = NSButton()

    init(image: CGImage, suggestedName: String, source: AnnotationImageSource,
         onClose: @escaping (AnnotationEditorWindow) -> Void) {
        self.image = image
        self.suggestedName = suggestedName
        self.source = source
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
        WindowPresentation.configure(self)
        title = L("标注图片")
        isReleasedWhenClosed = false
        sharingType = .readOnly
        canvas.baseImage = image
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onRecognitionSelection = { [weak self] action, rect in
            self?.actions.recognize(action, in: rect)
        }
        canvas.onColorPicked = { [weak self] color in
            guard let self else { return }
            self.colorPicker.selectedColor = color
            self.actions.pickColor(color)
            self.refresh()
        }

        actions.onChange = { [weak self] in self?.refresh() }
        actions.askAIButton = askAIButton
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
        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        SettingsAppearance.applySurface(to: bar, fill: SettingsAppearance.sidebar,
                                        border: SettingsAppearance.separator)

        toolSegment.segmentCount = allTools.count
        toolSegment.trackingMode = .selectOne
        toolSegment.segmentStyle = .rounded
        toolSegment.selectedSegmentBezelColor = .controlAccentColor
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

        colorPicker.onSelect = { [weak self] color in self?.canvas.applyColor(color) }

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
        SettingsAppearance.styleToolbarButton(copyButton)
        let clearButton = NSButton(title: L("清空"), target: self, action: #selector(clearTapped))
        clearButton.bezelStyle = .rounded
        SettingsAppearance.styleToolbarButton(clearButton)

        let zoomOutButton = NSButton(title: "−", target: self, action: #selector(zoomOutTapped))
        zoomOutButton.bezelStyle = .rounded
        SettingsAppearance.styleToolbarButton(zoomOutButton)
        let zoomInButton = NSButton(title: "+", target: self, action: #selector(zoomInTapped))
        zoomInButton.bezelStyle = .rounded
        SettingsAppearance.styleToolbarButton(zoomInButton)
        let fitButton = NSButton(title: L("适应"), target: self, action: #selector(fitTapped))
        fitButton.bezelStyle = .rounded
        SettingsAppearance.styleToolbarButton(fitButton)
        let pinButton = NSButton(title: L("定住"), target: self, action: #selector(pinTapped))
        pinButton.bezelStyle = .rounded
        SettingsAppearance.styleToolbarButton(pinButton)
        configure(eyedropperButton, symbol: "eyedropper", action: #selector(eyedropperTapped))
        eyedropperButton.toolTip = L("吸管：点击图片取色并复制 HEX")
        configure(measureButton, symbol: "ruler", action: #selector(measureTapped))
        measureButton.toolTip = L("测量：点击两个点量距离（像素）")
        configure(magnifierButton, symbol: "plus.magnifyingglass", action: #selector(magnifierTapped))
        magnifierButton.toolTip = L("放大镜：拖出圆形区域，将其中的图片放大 2 倍")
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        zoomLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let saveButton = NSButton(title: L("保存"), target: self, action: #selector(saveTapped))
        saveButton.bezelStyle = .rounded
        SettingsAppearance.styleToolbarButton(saveButton)
        saveButton.keyEquivalent = "\r"
        switch source {
        case .newCapture:
            discardImageButton.title = L("删除截图")
            discardImageButton.toolTip = L("丢弃当前截图，不保存")
        case .existingFile:
            discardImageButton.title = L("放弃编辑")
            discardImageButton.toolTip = L("关闭标注窗口，不保存本次修改；原文件不会被删除")
        }
        discardImageButton.bezelStyle = .rounded
        SettingsAppearance.styleToolbarButton(discardImageButton)
        discardImageButton.target = self
        discardImageButton.action = #selector(discardImageTapped)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [toolSegment, mosaicLabel, mosaicSegment,
                                        mosaicStrengthLabel, mosaicStrengthSlider, mosaicStrengthValue,
                                        colorPicker,
                                        widthLabel, widthSlider, widthValue, undoButton, redoButton,
                                        deleteButton, clearButton, spacer,
                                        zoomOutButton, zoomLabel, zoomInButton, fitButton, pinButton,
                                        eyedropperButton, measureButton, magnifierButton,
                                        copyButton, saveButton,
                                        discardImageButton])
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
        let panel = NSVisualEffectView()
        panel.material = .windowBackground
        panel.blendingMode = .withinWindow
        SettingsAppearance.applySurface(to: panel, fill: SettingsAppearance.sidebar,
                                        border: SettingsAppearance.separator)

        for (button, symbol, label, action) in [
            (ocrButton, "text.viewfinder", L("取字"), #selector(ocrTapped)),
            (barcodeButton, "qrcode.viewfinder", L("二维码"), #selector(barcodeTapped)),
            (translateButton, "character.bubble", L("翻译"), #selector(translateTapped)),
            (askAIButton, "sparkles", L("问 AI"), #selector(askAITapped)),
            (uploadButton, "icloud.and.arrow.up", L("上传图床"), #selector(uploadTapped)),
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular))
            // Keep the narrow action rail icon-only.  The tooltip and accessibility
            // label still provide the action name without letting text collide with
            // neighboring controls on compact or resized editor windows.
            button.title = ""
            button.imagePosition = .imageOnly
            button.bezelStyle = .rounded
            SettingsAppearance.styleToolbarButton(button)
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        ocrButton.toolTip = L("点击选择识别当前区域或重新框选")
        barcodeButton.toolTip = L("拖拽框选要识别的二维码")
        translateButton.toolTip = L("点击选择识别当前区域或重新框选")
        askAIButton.toolTip = L("把这张图片发给 AI（或先 OCR）")
        uploadButton.toolTip = L("上传整图（含标注）到图床，链接按设置格式复制到剪贴板")
        let stack = NSStackView(views: [ocrButton, barcodeButton, translateButton, askAIButton, uploadButton])
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
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        SettingsAppearance.styleToolbarButton(button)
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func refresh() {
        ocrButton.isEnabled = !actions.isOCRBusy
        barcodeButton.isEnabled = !actions.isBarcodeBusy
        translateButton.isEnabled = !actions.isTranslationBusy
        uploadButton.isEnabled = !actions.isUploadBusy
        let activeRecognition = canvas.recognitionAction
        // Busy work is represented by the disabled state; only an actual
        // transient selection is shown as the selected tool.
        SettingsAppearance.setToolActive(ocrButton, activeRecognition == .ocr, inactiveColor: .labelColor)
        SettingsAppearance.setToolActive(barcodeButton, activeRecognition == .barcode, inactiveColor: .labelColor)
        SettingsAppearance.setToolActive(translateButton, activeRecognition == .translate, inactiveColor: .labelColor)
        SettingsAppearance.setToolActive(uploadButton, false, inactiveColor: .labelColor)
        SettingsAppearance.setToolActive(eyedropperButton, canvas.isPickingColor, inactiveColor: .labelColor)
        SettingsAppearance.setToolActive(measureButton, canvas.isMeasuring, inactiveColor: .labelColor)
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
        magnifierButton.state = canvas.tool == .magnifier ? .on : .off
        SettingsAppearance.setToolActive(magnifierButton, canvas.tool == .magnifier, inactiveColor: .labelColor)
        toolSegment.selectedSegment = canvas.tool == .magnifier ? -1 : (allTools.firstIndex(of: canvas.tool) ?? -1)
    }

    @objc private func toolChanged() {
        guard let tool = allTools[safe: toolSegment.selectedSegment] else { return }
        canvas.tool = tool
        refresh()
    }
    @objc private func magnifierTapped() {
        canvas.tool = .magnifier
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
    @objc private func widthChanged() {
        let value = CGFloat(widthSlider.doubleValue)
        widthValue.stringValue = "\(Int(value))"
        canvas.applyLineWidth(value)
    }
    @objc private func deleteTapped() { canvas.deleteSelected(); refresh() }
    @objc private func clearTapped() { canvas.clearAll(); refresh() }
    @objc private func discardImageTapped() {
        close()
    }
    @objc private func zoomInTapped() { canvas.zoomIn(); refresh() }
    @objc private func zoomOutTapped() { canvas.zoomOut(); refresh() }
    @objc private func fitTapped() { canvas.resetZoom(); refresh() }
    @objc private func pinTapped() { actions.pinTapped() }
    @objc private func eyedropperTapped() { actions.eyedropperTapped(); refresh() }
    @objc private func measureTapped() { actions.measureTapped(); refresh() }
    @objc private func askAITapped() { actions.askAITapped() }
    @objc private func ocrTapped() {
        guard !showRecognitionMenu(for: .ocr, from: ocrButton) else { return }
        actions.ocrTapped()
        refresh()
    }
    @objc private func barcodeTapped() { actions.barcodeTapped(); refresh() }
    @objc private func translateTapped() {
        guard !showRecognitionMenu(for: .translate, from: translateButton) else { return }
        actions.translateTapped()
        refresh()
    }
    @objc private func uploadTapped() { actions.uploadTapped() }
    @objc private func undoTapped() { actions.undoTapped() }
    @objc private func redoTapped() { actions.redoTapped() }
    @objc private func saveTapped() { actions.saveTapped() }
    @objc private func copyTapped() { actions.copyTapped() }

    private func showRecognitionMenu(for action: AnnotationCanvas.RecognitionAction, from button: NSButton) -> Bool {
        guard let event = NSApp.currentEvent, event.window === button.window else { return false }
        let menu = NSMenu()
        let current = NSMenuItem(title: L("识别当前区域"), action: #selector(recognitionMenuItem(_:)), keyEquivalent: "")
        current.target = self
        current.tag = action.rawValue * 2
        let reselect = NSMenuItem(title: L("重新框选识别"), action: #selector(recognitionMenuItem(_:)), keyEquivalent: "")
        reselect.target = self
        reselect.tag = action.rawValue * 2 + 1
        menu.addItem(current)
        menu.addItem(reselect)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
        return true
    }

    @objc private func recognitionMenuItem(_ sender: NSMenuItem) {
        guard let action = AnnotationCanvas.RecognitionAction(rawValue: sender.tag / 2) else { return }
        if sender.tag.isMultiple(of: 2) {
            actions.recognizeCurrentSelection(action)
        } else {
            switch action {
            case .ocr: actions.ocrTapped()
            case .barcode: actions.barcodeTapped()
            case .translate: actions.translateTapped()
            }
        }
        refresh()
    }

    override func close() {
        super.close()
        onClose?(self)
    }
}
