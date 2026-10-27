import AppKit

/// Frozen desktop and the regular editor share a canvas and command implementation.
@MainActor
final class InlineScreenshotController: NSObject {
    static let shared = InlineScreenshotController()

    private var windows: [InlineScreenshotWindow] = []
    private var toolbar: NSPanel?
    private var quickRail: NSPanel?
    private var properties: NSPanel?
    private weak var activeView: InlineScreenshotView?
    private var actions: AnnotationEditorActions?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var preparing = false
    private var sessionID = UUID()
    private var hiddenControls = false
    private var suspensionCount = 0
    private var toolPicker: NSSegmentedControl?
    private var adjustButton: NSButton?
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private var copyButton: NSButton?
    private var saveButton: NSButton?
    private var magnifierButton: NSButton?
    private var eyedropperButton: NSButton?
    private var measureButton: NSButton?
    private var zoomLabel: NSTextField?
    private var colorPicker: AnnotationColorPicker?
    private var widthSlider: NSSlider?
    private var mosaicSlider: NSSlider?
    private var mosaicPicker: NSSegmentedControl?
    private var colorProperties: NSStackView?
    private var mosaicProperties: NSStackView?
    private var quickButtons: [NSButton] = []
    private let tools = AnnotationTool.allCases.filter { $0 != .magnifier }

    var isActive: Bool { preparing || !windows.isEmpty }
    private var panels: [NSPanel] { [toolbar, quickRail, properties].compactMap { $0 } }

    func begin(_ intent: SelectionIntent) async {
        guard !isActive, !SelectionController.shared.isActive else { return }
        guard #available(macOS 14.0, *) else {
            let alert = NSAlert()
            alert.messageText = L("截图需要 macOS 14 或更高版本")
            alert.addButton(withTitle: L("好"))
            runModalAlert(alert)
            return
        }
        // Close the live drawing surface before freezing, not while taking each display.
        ScreenAnnotationController.shared.close()
        preparing = true
        let session = UUID()
        sessionID = session
        previousApp = NSWorkspace.shared.frontmostApplication
        let screens = NSScreen.screens
        let pointer = NSEvent.mouseLocation
        do {
            var snapshots: [(NSScreen, CGImage)] = []
            // Do not show any overlay until every display has been captured.
            for screen in screens {
                let image = try await ScreenshotController.shared.captureImage(displayID: screen.displayID, region: nil)
                guard sessionID == session else { return }
                snapshots.append((screen, image))
            }
            guard sessionID == session else { return }
            guard screens.map(\.frame) == NSScreen.screens.map(\.frame),
                  screens.map(\.displayID) == NSScreen.screens.map(\.displayID) else {
                throw URLError(.cancelled)
            }
            preparing = false
            present(snapshots: snapshots, intent: intent, pointer: pointer)
        } catch {
            guard sessionID == session else { return }
            preparing = false
            previousApp = nil
            let alert = NSAlert()
            alert.messageText = L("截图失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L("好"))
            runModalAlert(alert)
        }
    }

    func present(snapshots: [(NSScreen, CGImage)], intent: SelectionIntent, pointer: CGPoint) {
        guard !snapshots.isEmpty, windows.isEmpty else { return }
        hiddenControls = false
        sessionID = UUID()
        NSApp.activate(ignoringOtherApps: true)
        for (screen, image) in snapshots {
            let view = InlineScreenshotView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
            let window = InlineScreenshotWindow(contentRect: screen.frame, styleMask: .borderless,
                                                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.level = .screenSaver + 1
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = view
            view.onSelectionChanged = { [weak self, weak view] in
                guard let self, let view else { return }
                self.activate(view)
            }
            view.canvas.onChange = { [weak self, weak view] in
                view?.refreshSelection()
                self?.refreshControls()
            }
            windows.append(window)
        }
        let target = windows.first { $0.frame.contains(pointer) } ?? windows[0]
        makeToolbar(availableWidth: snapshots.map { $0.0.visibleFrame.width }.min() ?? target.frame.width)
        windows.forEach { $0.orderFrontRegardless() }
        target.makeKey()
        target.makeFirstResponder(target.contentView)
        if intent == .displayOnly, let view = target.contentView as? InlineScreenshotView {
            view.setSelection(view.bounds)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
    }

    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window,
              self.windows.contains(where: { $0 === window }) || self.panels.contains(where: { $0 === window }) else { return event }
        let canvas = self.activeView?.canvas
        if event.keyCode == 53 {
            if canvas?.recognitionAction != nil || canvas?.isPickingColor == true || canvas?.isMeasuring == true || canvas?.hasMeasurement == true {
                canvas?.cancelOperation(nil)
                activeView?.setRecognitionSelectionActive(false)
                self.refreshControls()
            } else if event.window?.firstResponder is NSTextView {
                canvas?.finishTextEditing()
            } else { self.close() }
            return nil
        }
        guard !(event.window?.firstResponder is NSTextView) else { return event }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": self.actions?.copyTapped(); return nil
            case "s": self.actions?.saveTapped(); return nil
            case "z":
                if event.modifierFlags.contains(.shift) { canvas?.redo() } else { canvas?.undo() }
                return nil
            case "y": canvas?.redo(); return nil
            default: break
            }
        }
        if event.keyCode == 48 {
            self.hiddenControls.toggle()
            self.refreshControls()
            return nil
        }
        if event.keyCode == 36 || event.keyCode == 76 { self.actions?.saveTapped(); return nil }
        if event.keyCode == 51 || event.keyCode == 117 { canvas?.deleteSelected(); return nil }
        return event
    }

    private func activate(_ view: InlineScreenshotView) {
        if activeView !== view {
            activeView?.canvas.finishTextEditing()
            activeView?.setSelection(nil, notify: false)
            activeView = view
            view.adjustingSelection = true
            let commands = AnnotationEditorActions(canvas: view.canvas, suggestedName: FileName.make(ext: "png"),
                renderImage: { [weak view] in view?.renderedSelection() }, onClose: { [weak self] in self?.close() })
            let session = sessionID
            commands.isValid = { [weak self, weak view] in self?.sessionID == session && self?.activeView === view }
            commands.notify = { [weak view] title, detail in
                Toast.show(title: title, detail: detail,
                           level: NSWindow.Level(rawValue: (view?.window?.level.rawValue ?? NSWindow.Level.floating.rawValue) + 3))
            }
            commands.recognitionBounds = { [weak view] in view?.pixelSelection }
            commands.onChange = { [weak self] in self?.refreshControls() }
            commands.suspend = { [weak self] in
                guard let self, self.sessionID == session else { return }
                self.suspensionCount += 1
                self.windows.forEach { $0.orderOut(nil) }
                self.panels.forEach { $0.orderOut(nil) }
            }
            commands.resume = { [weak self] in
                guard let self, self.sessionID == session else { return }
                self.suspensionCount = max(0, self.suspensionCount - 1)
                if self.suspensionCount == 0 { self.restoreWindows() }
            }
            // Result windows use the regular floating level. Lower the frozen desktop
            // while keeping this session editable, rather than hiding its results.
            commands.preparePresentation = { [weak self] in
                guard let self, self.sessionID == session else { return }
                self.windows.forEach { $0.level = .normal }
                self.panels.forEach { $0.level = .floating }
            }
            commands.askAIButton = quickButtons[safe: 3]
            actions = commands
            colorPicker?.selectedColor = view.canvas.color
            colorPicker?.willPresentDialog = commands.suspend
            colorPicker?.didDismissDialog = commands.resume
            view.canvas.onRecognitionSelection = { [weak commands, weak view] action, rect in
                view?.setRecognitionSelectionActive(false)
                commands?.recognize(action, in: rect)
            }
            view.canvas.onColorPicked = { [weak self, weak commands] color in
                self?.colorPicker?.selectedColor = color
                commands?.pickColor(color)
                self?.refreshControls()
            }
            positionToolbar()
        }
        view.window?.makeKey()
        refreshControls()
    }

    private func makeToolbar(availableWidth: CGFloat) {
        let adjust = button("selection.pin.in.out", "调整选区", #selector(adjustSelection))
        adjustButton = adjust
        let picker = NSSegmentedControl()
        picker.segmentCount = tools.count
        picker.trackingMode = .selectOne
        picker.selectedSegment = -1
        picker.segmentStyle = .rounded
        picker.selectedSegmentBezelColor = .controlAccentColor
        picker.target = self
        picker.action = #selector(toolChanged)
        for (index, tool) in tools.enumerated() {
            picker.setImage(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.label), forSegment: index)
            picker.setWidth(28, forSegment: index)
            picker.setToolTip(tool.label, forSegment: index)
        }
        picker.setAccessibilityLabel(L("标注工具"))
        toolPicker = picker
        let undo = button("arrow.uturn.backward", "撤销", #selector(undo))
        let redo = button("arrow.uturn.forward", "下一步", #selector(redo))
        undoButton = undo
        redoButton = redo
        let edit = row([adjust, separator(), picker, separator(), undo, redo,
                        button("trash", "删除选中标注", #selector(deleteAnnotation)),
                        button("eraser", "清空", #selector(clear))])
        let zoom = NSTextField(labelWithString: "100%")
        zoom.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoom.alignment = .center
        zoom.widthAnchor.constraint(equalToConstant: 40).isActive = true
        zoomLabel = zoom
        let magnifier = button("plus.magnifyingglass", "放大镜：拖出圆形区域，将其中的图片放大 2 倍", #selector(magnifier))
        magnifierButton = magnifier
        let eyedropper = button("eyedropper", "吸管：点击图片取色并复制 HEX", #selector(eyedropper))
        eyedropperButton = eyedropper
        let measure = button("ruler", "测量：点击两个点量距离（像素）", #selector(measure))
        measureButton = measure
        let copy = NSButton(title: L("拷贝"), target: self, action: #selector(copyTapped))
        let save = NSButton(title: L("保存"), target: self, action: #selector(save))
        for button in [copy, save] {
            button.bezelStyle = .rounded
            SettingsAppearance.styleToolbarButton(button)
        }
        save.contentTintColor = .controlAccentColor
        copy.toolTip = L("拷贝") + " (⌘C)"
        save.toolTip = L("保存") + " (↩ / ⌘S)"
        copyButton = copy
        saveButton = save
        let utility = row([button("minus.magnifyingglass", "缩小", #selector(zoomOut)), zoom,
                           button("plus.magnifyingglass", "放大", #selector(zoomIn)),
                           button("arrow.up.left.and.arrow.down.right", "适应", #selector(fit)), separator(),
                           button("pin", "定住", #selector(pin)), eyedropper, measure, magnifier,
                           separator(), copy, save, button("xmark", "删除截图", #selector(cancel))])
        let content = row([edit, separator(), utility])
        if content.fittingSize.width + 24 > availableWidth - 32 {
            content.orientation = .vertical
            content.alignment = .centerX
            content.arrangedSubviews[1].isHidden = true
        }
        toolbar = panel(content, identifier: "inline.tools")

        let rail = NSStackView()
        rail.orientation = .vertical
        rail.spacing = 8
        for (index, entry) in [("text.viewfinder", "取字"), ("qrcode.viewfinder", "二维码"),
                               ("character.bubble", "翻译"), ("sparkles", "问 AI"), ("icloud.and.arrow.up", "上传图床")].enumerated() {
            let control = button(entry.0, entry.1, #selector(quickAction(_:)), size: 34)
            control.tag = index
            if index == 0 || index == 2 {
                control.toolTip = L("点击选择识别当前区域或重新框选")
            }
            quickButtons.append(control)
            rail.addArrangedSubview(control)
        }
        quickRail = panel(rail, identifier: "inline.quick")

        let color = AnnotationColorPicker()
        color.onSelect = { [weak self] value in self?.activeView?.canvas.applyColor(value) }
        colorPicker = color
        let width = NSSlider(value: 4, minValue: 1, maxValue: 20, target: self, action: #selector(widthChanged(_:)))
        width.widthAnchor.constraint(equalToConstant: 100).isActive = true
        width.setAccessibilityLabel(L("粗细"))
        widthSlider = width
        colorProperties = row([color, separator(), NSTextField(labelWithString: L("粗细")), width])
        let styles = NSSegmentedControl(labels: MosaicStyle.allCases.map(\.label), trackingMode: .selectOne,
                                        target: self, action: #selector(mosaicStyleChanged(_:)))
        styles.selectedSegment = 0
        mosaicPicker = styles
        let strength = NSSlider(value: 4, minValue: 1, maxValue: 10, target: self, action: #selector(mosaicChanged(_:)))
        strength.widthAnchor.constraint(equalToConstant: 90).isActive = true
        strength.setAccessibilityLabel(L("马赛克程度"))
        mosaicSlider = strength
        mosaicProperties = row([styles, separator(), NSTextField(labelWithString: L("程度")), strength])
        let propertyStack = row([colorProperties!, mosaicProperties!])
        properties = panel(propertyStack, identifier: "inline.properties")
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return line
    }

    private func button(_ symbol: String, _ title: String, _ action: Selector, size: CGFloat = 28) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: L(title)) ?? NSImage(),
                              target: self, action: action)
        button.bezelStyle = .rounded
        button.isBordered = false
        button.contentTintColor = SettingsAppearance.text
        button.image = button.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size > 28 ? 17 : 14, weight: .regular))
        button.toolTip = L(title)
        button.setAccessibilityLabel(L(title))
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        return button
    }

    private func panel(_ stack: NSStackView, identifier: String) -> NSPanel {
        let size = CGSize(width: stack.fittingSize.width + 24, height: stack.fittingSize.height + 20)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.layer?.masksToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10)
        ])
        panel.contentView = background
        return panel
    }

    private func positionToolbar() {
        guard let toolbar, let view = activeView, let window = view.window else { return }
        let frame = window.screen?.visibleFrame ?? window.frame
        toolbar.setFrameOrigin(CGPoint(x: frame.midX - toolbar.frame.width / 2, y: frame.minY + 18))
        if let rail = quickRail {
            rail.setFrameOrigin(CGPoint(x: frame.maxX - rail.frame.width - 18, y: frame.midY - rail.frame.height / 2))
        }
    }

    private func refreshControls() {
        let canvas = activeView?.canvas
        let selected = activeView?.selection != nil
        toolPicker?.isEnabled = selected
        copyButton?.isEnabled = selected
        saveButton?.isEnabled = selected
        undoButton?.isEnabled = canvas?.canUndo ?? false
        redoButton?.isEnabled = canvas?.canRedo ?? false
        adjustButton?.state = activeView?.adjustingSelection == true ? .on : .off
        if let adjustButton {
            SettingsAppearance.setToolActive(adjustButton, activeView?.adjustingSelection == true)
        }
        toolPicker?.selectedSegment = activeView?.adjustingSelection == true ? -1 : tools.firstIndex(of: canvas?.tool ?? .select) ?? -1
        let magnifierActive = canvas?.tool == .magnifier && activeView?.adjustingSelection == false
        magnifierButton?.state = magnifierActive ? .on : .off
        if let magnifierButton { SettingsAppearance.setToolActive(magnifierButton, magnifierActive) }
        if let eyedropperButton { SettingsAppearance.setToolActive(eyedropperButton, canvas?.isPickingColor == true) }
        if let measureButton { SettingsAppearance.setToolActive(measureButton, canvas?.isMeasuring == true) }
        zoomLabel?.stringValue = "\(Int(((canvas?.zoom ?? 1) * 100).rounded()))%"
        let propertyTool = canvas?.selectedAnnotation?.tool ?? canvas?.tool ?? .select
        let mosaic = propertyTool == .mosaic
        colorProperties?.isHidden = mosaic
        mosaicProperties?.isHidden = !mosaic
        widthSlider?.doubleValue = Double(canvas?.selectedAnnotation?.lineWidth ?? canvas?.lineWidth ?? 4)
        colorPicker?.selectedColor = canvas?.selectedAnnotation?.color ?? canvas?.color ?? .systemRed
        mosaicSlider?.doubleValue = Double(canvas?.currentMosaicStrength ?? 4)
        mosaicPicker?.selectedSegment = canvas?.selectedAnnotation?.mosaicStyle.rawValue ?? canvas?.mosaicStyle.rawValue ?? 0
        let busy = [actions?.isOCRBusy, actions?.isBarcodeBusy, actions?.isTranslationBusy, false, actions?.isUploadBusy]
        let activeRecognition = canvas?.recognitionAction
        for (index, button) in quickButtons.enumerated() {
            button.isEnabled = selected && busy[index] != true
            let active = switch index {
            case 0: activeRecognition == .ocr
            case 1: activeRecognition == .barcode
            case 2: activeRecognition == .translate
            default: false
            }
            // Busy work is shown by the disabled control. Keep the selected
            // treatment for the temporary drag-selection state only, so a
            // completed request cannot leave a button looking latched.
            SettingsAppearance.setToolActive(button, active)
        }
        for panel in [toolbar, quickRail].compactMap({ $0 }) {
            if selected && !hiddenControls && suspensionCount == 0 { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        }
        let needsProperties = selected && !hiddenControls && suspensionCount == 0 && activeView?.adjustingSelection == false &&
            [.pen, .arrow, .rectangle, .text, .number, .mosaic].contains(propertyTool)
        if let properties, let content = properties.contentView, let toolbar, needsProperties {
            content.layoutSubtreeIfNeeded()
            let stack = content.subviews[0]
            properties.setContentSize(CGSize(width: stack.fittingSize.width + 24, height: stack.fittingSize.height + 20))
            properties.setFrameOrigin(CGPoint(x: toolbar.frame.minX + 12, y: toolbar.frame.maxY + 10))
            properties.orderFrontRegardless()
        } else { properties?.orderOut(nil) }
    }

    @objc private func adjustSelection() {
        activeView?.canvas.finishTextEditing()
        activeView?.canvas.cancelOperation(nil)
        activeView?.adjustingSelection = true
        refreshControls()
    }

    private func useCanvas() {
        activeView?.canvas.finishTextEditing()
        activeView?.adjustingSelection = false
        activeView?.window?.makeKey()
        activeView?.window?.makeFirstResponder(activeView?.canvas)
    }

    @objc private func toolChanged() {
        guard let picker = toolPicker, tools.indices.contains(picker.selectedSegment), let view = activeView else { return }
        let tool = tools[picker.selectedSegment]
        useCanvas()
        view.canvas.tool = tool
        refreshControls()
    }
    @objc private func widthChanged(_ sender: NSSlider) { activeView?.canvas.applyLineWidth(CGFloat(sender.doubleValue)) }
    @objc private func mosaicChanged(_ sender: NSSlider) { activeView?.canvas.applyMosaicStrength(CGFloat(sender.doubleValue)) }
    @objc private func mosaicStyleChanged(_ sender: NSSegmentedControl) {
        if let style = MosaicStyle(rawValue: sender.selectedSegment) { activeView?.canvas.applyMosaicStyle(style) }
    }
    @objc private func undo() { activeView?.canvas.undo() }
    @objc private func redo() { activeView?.canvas.redo() }
    @objc private func deleteAnnotation() { activeView?.canvas.deleteSelected() }
    @objc private func clear() { activeView?.canvas.clearAll() }
    @objc private func cancel() { close() }
    @objc private func copyTapped() { actions?.copyTapped() }
    @objc private func save() { actions?.saveTapped() }
    @objc private func zoomIn() { activeView?.canvas.zoomIn() }
    @objc private func zoomOut() { activeView?.canvas.zoomOut() }
    @objc private func fit() { activeView?.canvas.resetZoom() }
    @objc private func pin() { actions?.pinTapped() }
    @objc private func eyedropper() { useCanvas(); actions?.eyedropperTapped(); refreshControls() }
    @objc private func measure() { useCanvas(); actions?.measureTapped(); refreshControls() }
    @objc private func magnifier() { useCanvas(); activeView?.canvas.tool = .magnifier; refreshControls() }
    @objc private func quickAction(_ sender: NSButton) {
        useCanvas()
        // Clear the secondary-selection presentation before switching actions so
        // a completed or cancelled recognition drag cannot leave the canvas routed
        // around the normal screenshot-selection handles.
        activeView?.setRecognitionSelectionActive(false)
        switch sender.tag {
        case 0:
            if !showRecognitionMenu(for: .ocr, from: sender) { useCurrentSelection(.ocr) }
        case 1: actions?.barcodeTapped()
        case 2:
            if !showRecognitionMenu(for: .translate, from: sender) { useCurrentSelection(.translate) }
        case 3: actions?.askAITapped()
        case 4: actions?.uploadTapped()
        default: break
        }
        refreshControls()
    }

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
            useCurrentSelection(action)
        } else {
            beginRecognition(action)
        }
        refreshControls()
    }

    private func useCurrentSelection(_ action: AnnotationCanvas.RecognitionAction) {
        activeView?.setRecognitionSelectionActive(false)
        actions?.recognizeCurrentSelection(action)
    }

    private func beginRecognition(_ action: AnnotationCanvas.RecognitionAction) {
        switch action {
        case .ocr: actions?.ocrTapped()
        case .barcode: actions?.barcodeTapped()
        case .translate: actions?.translateTapped()
        }
        activeView?.setRecognitionSelectionActive(activeView?.canvas.recognitionAction != nil)
    }

    private func restoreWindows() {
        guard isActive else { return }
        windows.forEach { $0.orderFrontRegardless() }
        activeView?.window?.makeKey()
        refreshControls()
    }

    func close() {
        sessionID = UUID()
        preparing = false
        suspensionCount = 0
        Toast.dismiss()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panels.forEach { $0.close() }
        toolbar = nil
        quickRail = nil
        properties = nil
        windows.forEach { $0.close() }
        windows.removeAll()
        activeView = nil
        actions = nil
        toolPicker = nil
        adjustButton = nil
        undoButton = nil
        redoButton = nil
        copyButton = nil
        saveButton = nil
        magnifierButton = nil
        eyedropperButton = nil
        measureButton = nil
        zoomLabel = nil
        colorPicker = nil
        widthSlider = nil
        mosaicSlider = nil
        mosaicPicker = nil
        colorProperties = nil
        mosaicProperties = nil
        quickButtons.removeAll()
        let previous = previousApp
        previousApp = nil
        if let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier { previous.activate() }
    }
}

private final class InlineScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class InlineScreenshotView: NSView {
    let canvas: AnnotationCanvas
    private let selectionOverlay: InlineScreenshotSelectionView
    var onSelectionChanged: (() -> Void)?
    var adjustingSelection = true {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    private var recognitionSelectionActive = false
    var selection: CGRect? {
        guard let rect = canvas.exportRegion else { return nil }
        let a = canvas.viewPoint(rect.origin)
        let b = canvas.viewPoint(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private enum Drag { case create(CGPoint), move(CGPoint, CGRect), resize(Int, CGRect) }
    private var drag: Drag?

    init(frame: CGRect, image: CGImage) {
        canvas = AnnotationCanvas(frame: CGRect(origin: .zero, size: frame.size))
        selectionOverlay = InlineScreenshotSelectionView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
        canvas.baseImage = image
        canvas.usesExportCrop = true
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        selectionOverlay.owner = self
        selectionOverlay.autoresizingMask = [.width, .height]
        addSubview(selectionOverlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelection(_ rect: CGRect?, notify: Bool = true) {
        let clipped = rect?.standardized.intersection(bounds)
        if let clipped, !clipped.isNull, clipped.width >= 2, clipped.height >= 2, let image = canvas.baseImage {
            let a = canvas.imagePoint(clipped.origin)
            let b = canvas.imagePoint(CGPoint(x: clipped.maxX, y: clipped.maxY))
            let pixels = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            canvas.exportRegion = pixels.isNull || pixels.isEmpty ? nil : pixels
        } else { canvas.exportRegion = nil }
        refreshSelection()
        if notify, selection != nil { onSelectionChanged?() }
    }

    func refreshSelection() {
        selectionOverlay.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func setRecognitionSelectionActive(_ active: Bool) {
        recognitionSelectionActive = active
        refreshSelection()
    }

    var pixelSelection: CGRect? {
        canvas.exportRegion?.integral
    }

    static func pixelRect(_ rect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let scaled = CGRect(x: rect.minX * imageSize.width / viewSize.width,
                            y: rect.minY * imageSize.height / viewSize.height,
                            width: rect.width * imageSize.width / viewSize.width,
                            height: rect.height * imageSize.height / viewSize.height)
            .integral.intersection(CGRect(origin: .zero, size: imageSize))
        return scaled.isNull || scaled.isEmpty ? nil : scaled
    }

    func renderedSelection() -> CGImage? {
        canvas.finishTextEditing()
        guard pixelSelection != nil else { return nil }
        return canvas.renderedImage()
    }

    private var handles: [CGPoint] {
        guard let r = selection else { return [] }
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    private func handle(at point: CGPoint) -> Int? {
        if let index = handles.firstIndex(where: { abs($0.x - point.x) <= 7 && abs($0.y - point.y) <= 7 }) {
            return index
        }
        guard let selection, selection.insetBy(dx: -7, dy: -7).contains(point) else { return nil }
        if abs(point.x - selection.minX) <= 7 { return 7 }
        if abs(point.x - selection.maxX) <= 7 { return 3 }
        if abs(point.y - selection.minY) <= 7 { return 1 }
        if abs(point.y - selection.maxY) <= 7 { return 5 }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if recognitionSelectionActive {
            return canvas.hitTest(convert(local, to: canvas.superview)) ?? canvas
        }
        if !adjustingSelection, let selection, selection.insetBy(dx: 7, dy: 7).contains(local), handle(at: local) == nil {
            return canvas.hitTest(convert(local, to: canvas.superview))
        }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) { canvas.scrollWheel(with: event); refreshSelection() }
    override func magnify(with event: NSEvent) { canvas.magnify(with: event); refreshSelection() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addVisibleCursorRect(bounds, cursor: .crosshair)
        if recognitionSelectionActive { return }
        guard let selection else { return }
        addVisibleCursorRect(selection.insetBy(dx: 7, dy: 7), cursor: adjustingSelection ? .openHand : .arrow)
        for (index, point) in handles.enumerated() {
            let cursor: NSCursor = [1, 5].contains(index) ? .resizeUpDown : ([3, 7].contains(index) ? .resizeLeftRight : .crosshair)
            addVisibleCursorRect(CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14), cursor: cursor)
        }
    }

    private func addVisibleCursorRect(_ rect: CGRect, cursor: NSCursor) {
        // Insetting a tiny selection or clipping an offscreen handle can produce
        // CGRect.null (infinite origin), which AppKit rejects with an exception.
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return }
        let visible = rect.intersection(bounds)
        guard visible.origin.x.isFinite, visible.origin.y.isFinite,
              visible.width.isFinite, visible.height.isFinite,
              visible.width > 0, visible.height > 0 else { return }
        addCursorRect(visible, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        canvas.finishTextEditing()
        let point = convert(event.locationInWindow, from: nil)
        if let selection, let handle = handle(at: point) {
            drag = .resize(handle, selection)
        } else if let selection, selection.contains(point), adjustingSelection {
            drag = .move(point, selection)
        } else {
            drag = .create(point)
            adjustingSelection = true
        }
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .create(let anchor):
            setSelection(CGRect(x: min(point.x, anchor.x), y: min(point.y, anchor.y),
                                width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)))
        case .move(let anchor, let rect):
            setSelection(CGRect(x: max(0, min(bounds.width - rect.width, rect.minX + point.x - anchor.x)),
                                y: max(0, min(bounds.height - rect.height, rect.minY + point.y - anchor.y)),
                                width: rect.width, height: rect.height))
        case .resize(let index, let rect):
            var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
            if [0, 6, 7].contains(index) { left = min(right - 2, max(0, point.x)) }
            if [2, 3, 4].contains(index) { right = max(left + 2, min(bounds.width, point.x)) }
            if [0, 1, 2].contains(index) { top = min(bottom - 2, max(0, point.y)) }
            if [4, 5, 6].contains(index) { bottom = max(top + 2, min(bounds.height, point.y)) }
            setSelection(CGRect(x: left, y: top, width: right - left, height: bottom - top))
        case nil: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        drag = nil
    }

    fileprivate func drawSelection() {
        if recognitionSelectionActive {
            guard let selection else { return }
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1
            border.setLineDash([5, 4], count: 2, phase: 0)
            NSColor.systemBlue.withAlphaComponent(0.72).setStroke()
            border.stroke()
            return
        }
        let mask = NSBezierPath(rect: bounds)
        if let selection { mask.appendRect(selection) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill()
        mask.fill()
        if let selection {
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
            for point in handles {
                let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                NSColor.white.setFill()
                handle.fill()
                handle.stroke()
            }
            if let pixels = pixelSelection {
                let text = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.white
                ]
                let size = text.size(withAttributes: attributes)
                let label = CGRect(x: max(8, min(bounds.maxX - size.width - 20, selection.minX)),
                                   y: max(8, min(bounds.maxY - 26, selection.minY - 27)),
                                   width: size.width + 12, height: 21)
                NSColor.black.withAlphaComponent(0.65).setFill()
                NSBezierPath(roundedRect: label, xRadius: 5, yRadius: 5).fill()
                text.draw(at: CGPoint(x: label.minX + 6, y: label.minY + 3), withAttributes: attributes)
            }
        } else {
            let text = L("拖动选择截图区域 · Esc 取消")
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium),
                                                            .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: 40), withAttributes: attributes)
        }
    }
}

private final class InlineScreenshotSelectionView: NSView {
    weak var owner: InlineScreenshotView?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { owner?.drawSelection() }
}
