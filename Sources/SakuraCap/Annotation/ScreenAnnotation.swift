import AppKit

/// Transparent, capture-visible canvases for annotating the live desktop.
@MainActor
final class ScreenAnnotationController: NSObject {
    static let shared = ScreenAnnotationController()

    private var overlays: [NSWindow] = []
    private var canvases: [AnnotationCanvas] = []
    private var toolbar: NSPanel?
    private var toolPicker: NSSegmentedControl?
    private var colorPicker: AnnotationColorPicker?
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private var clearButton: NSButton?
    private var deleteButton: NSButton?
    private var measureButton: NSButton?
    private var widthLabel: NSTextField?
    private var widthSlider: NSSlider?
    private var widthValue: NSTextField?
    private var mosaicControls: NSStackView?
    private var widthControls: NSStackView?
    private var mosaicSegment: NSSegmentedControl?
    private var mosaicSlider: NSSlider?
    private var mosaicValue: NSTextField?
    private var passButton: NSButton?
    private weak var lastEditedCanvas: AnnotationCanvas?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var passingThrough = false
    private let tools: [AnnotationTool] = [.select, .pen, .arrow, .rectangle, .text, .number, .mosaic]

    var isActive: Bool { toolbar != nil }

    func toggle() {
        if isActive { close() } else { open() }
    }

    private func open() {
        guard !NSScreen.screens.isEmpty else { return }
        passingThrough = false
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let canvas = AnnotationCanvas(frame: NSRect(origin: .zero, size: screen.frame.size))
            canvas.tool = .pen
            canvas.color = .systemRed
            canvas.measurementScale = screen.backingScaleFactor
            canvas.onChange = { [weak self, weak canvas] in
                guard let self, let canvas else { return }
                self.lastEditedCanvas = canvas
                self.refreshControls()
            }
            canvas.onMeasurementCompleted = { [weak self, weak canvas] in
                guard let self, let canvas else { return }
                self.canvases.filter { $0 !== canvas && $0.isMeasuring }.forEach { $0.endMeasure() }
                self.refreshControls()
            }
            let overlay = ScreenAnnotationWindow(contentRect: screen.frame, styleMask: .borderless,
                                                 backing: .buffered, defer: false)
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.hasShadow = false
            overlay.level = .screenSaver
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            overlay.sharingType = .readOnly
            overlay.contentView = canvas
            overlay.ignoresMouseEvents = false
            canvas.captureSource = { [weak overlay, weak screen] rect in
                guard let overlay, let screen, let primary = NSScreen.screens.first else { return nil }
                // Window-list capture excludes this overlay and every window above it.
                let screenRect = CGRect(x: screen.frame.minX + rect.minX,
                                        y: primary.frame.maxY - screen.frame.maxY + rect.minY,
                                        width: rect.width, height: rect.height)
                return CGWindowListCreateImage(screenRect, .optionOnScreenBelowWindow,
                                               CGWindowID(overlay.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution])
            }
            overlay.orderFrontRegardless()
            canvases.append(canvas)
            overlays.append(overlay)
        }
        makeToolbar()
        // Refresh the hit-test region after the transparent windows enter the window server.
        // Without this, the first launch may treat them as click-through until the toggle changes.
        overlays.forEach {
            $0.ignoresMouseEvents = true
            $0.ignoresMouseEvents = false
        }
        (overlays.first { $0.frame.contains(NSEvent.mouseLocation) } ?? overlays.first)?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z",
               !(event.window?.firstResponder is NSTextView) {
                if event.modifierFlags.contains(.shift) {
                    self?.editingCanvas()?.redo()
                } else {
                    self?.editingCanvas()?.undo()
                }
                return nil
            }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func makeToolbar() {
        let picker = NSSegmentedControl()
        picker.segmentCount = tools.count
        picker.trackingMode = .selectOne
        for (index, tool) in tools.enumerated() {
            picker.setImage(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: nil), forSegment: index)
            picker.setWidth(30, forSegment: index)
        }
        picker.selectedSegment = 1
        picker.segmentStyle = .rounded
        picker.target = self
        picker.action = #selector(toolChanged)
        picker.toolTip = L("选择工具后在屏幕上绘制；Esc 退出")
        toolPicker = picker

        let color = AnnotationColorPicker()
        color.onSelect = { [weak self] chosen in
            guard let self else { return }
            self.canvases.forEach { $0.applyColor(chosen) }
        }
        colorPicker = color
        let undo = iconButton("arrow.uturn.backward", L("撤销"), #selector(undoTapped))
        undoButton = undo
        let redo = iconButton("arrow.uturn.forward", L("下一步"), #selector(redoTapped))
        redoButton = redo
        let delete = iconButton("trash", L("删除选中标注"), #selector(deleteTapped))
        deleteButton = delete
        let measure = iconButton("ruler", L("测量：点击两个点量距离（像素）"), #selector(measureTapped))
        measureButton = measure
        let clear = NSButton(title: L("清空"), target: self, action: #selector(clearTapped))
        clear.bezelStyle = .rounded
        clear.toolTip = L("清空标注")
        clearButton = clear
        let pass = iconButton("cursorarrow", L("穿透：关"), #selector(passTapped))
        passButton = pass
        let exit = AnnotationCloseButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L("结束标注")) ?? NSImage(),
                                         target: self, action: #selector(exitTapped))
        exit.configureAppearance()
        exit.toolTip = L("结束标注")
        exit.setAccessibilityLabel(L("结束标注"))
        exit.widthAnchor.constraint(equalToConstant: 30).isActive = true
        exit.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let grip = NSImageView(image: NSImage(systemSymbolName: "circle.grid.2x3.fill", accessibilityDescription: L("拖动移动")) ?? NSImage())
        grip.contentTintColor = .secondaryLabelColor
        grip.toolTip = L("拖动移动")
        grip.widthAnchor.constraint(equalToConstant: 17).isActive = true
        let top = NSStackView(views: [grip, picker, color, undo, redo, delete, measure, clear, pass, divider, exit])
        top.orientation = .horizontal
        top.spacing = 6
        top.setCustomSpacing(14, after: pass)
        top.setCustomSpacing(11, after: divider)

        let width = NSSlider(value: 4, minValue: 1, maxValue: 20, target: self, action: #selector(widthChanged(_:)))
        width.widthAnchor.constraint(equalToConstant: 110).isActive = true
        widthSlider = width
        let widthNumber = NSTextField(labelWithString: "4")
        widthNumber.widthAnchor.constraint(equalToConstant: 22).isActive = true
        widthValue = widthNumber
        let widthTitle = NSTextField(labelWithString: L("粗细"))
        widthLabel = widthTitle
        let widthRow = NSStackView(views: [widthTitle, width, widthNumber])
        widthRow.spacing = 6
        widthControls = widthRow

        let styles = NSSegmentedControl()
        styles.segmentCount = MosaicStyle.allCases.count
        styles.trackingMode = .selectOne
        for (index, style) in MosaicStyle.allCases.enumerated() {
            styles.setLabel(style.label, forSegment: index)
            styles.setWidth(54, forSegment: index)
        }
        styles.selectedSegment = 0
        styles.target = self
        styles.action = #selector(mosaicChanged(_:))
        mosaicSegment = styles
        let strength = NSSlider(value: 4, minValue: 1, maxValue: 10, target: self, action: #selector(mosaicStrengthChanged(_:)))
        strength.widthAnchor.constraint(equalToConstant: 90).isActive = true
        mosaicSlider = strength
        let strengthNumber = NSTextField(labelWithString: "4")
        strengthNumber.widthAnchor.constraint(equalToConstant: 22).isActive = true
        mosaicValue = strengthNumber
        let mosaicRow = NSStackView(views: [NSTextField(labelWithString: L("马赛克")), styles,
                                            NSTextField(labelWithString: L("程度")), strength, strengthNumber])
        mosaicRow.spacing = 6
        mosaicControls = mosaicRow
        let properties = NSStackView(views: [widthRow, mosaicRow])
        properties.orientation = .vertical
        properties.alignment = .centerX
        mosaicRow.isHidden = true
        let stack = NSStackView(views: [top, properties])
        stack.alignment = .centerX
        stack.orientation = .vertical
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 13, bottom: 10, right: 13)
        let size = stack.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .none
        panel.isMovableByWindowBackground = true
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.style = .regular
            glass.cornerRadius = 22
            glass.contentView = stack
            background = glass
        } else {
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 22
            blur.layer?.masksToBounds = true
            blur.addSubview(stack)
            background = blur
        }
        stack.frame = NSRect(origin: .zero, size: size)
        stack.autoresizingMask = [.width, .height]
        panel.contentView = background
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                     y: screen.visibleFrame.minY + 32))
        panel.orderFrontRegardless()
        toolbar = panel
        refreshControls()
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
                              target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    @objc private func toolChanged() {
        guard let picker = toolPicker, tools.indices.contains(picker.selectedSegment) else { return }
        canvases.forEach {
            $0.endMeasure()
            $0.tool = tools[picker.selectedSegment]
        }
        refreshControls()
    }

    @objc private func undoTapped() {
        editingCanvas()?.undo()
    }

    @objc private func redoTapped() {
        editingCanvas()?.redo()
    }

    @objc private func deleteTapped() { editingCanvas()?.deleteSelected() }

    @objc private func measureTapped() {
        if canvases.contains(where: { $0.isMeasuring }) {
            canvases.forEach { $0.endMeasure() }
        } else {
            canvases.forEach { $0.beginMeasure() }
        }
        refreshControls()
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        widthValue?.stringValue = "\(Int(value.rounded()))"
        canvases.forEach { $0.applyLineWidth(value) }
    }

    @objc private func mosaicChanged(_ sender: NSSegmentedControl) {
        guard let style = MosaicStyle(rawValue: sender.selectedSegment) else { return }
        canvases.forEach { $0.applyMosaicStyle(style) }
    }

    @objc private func mosaicStrengthChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        mosaicValue?.stringValue = "\(Int(value.rounded()))"
        canvases.forEach { $0.applyMosaicStrength(value) }
    }

    @objc private func clearTapped() {
        canvases.forEach {
            $0.endMeasure()
            if !$0.annotations.isEmpty { $0.clearAll() }
        }
        refreshControls()
    }

    @objc private func passTapped() {
        passingThrough.toggle()
        overlays.forEach { $0.ignoresMouseEvents = passingThrough }
        passButton?.image = NSImage(systemSymbolName: passingThrough ? "cursorarrow.rays" : "cursorarrow",
                                    accessibilityDescription: nil)
        passButton?.toolTip = passingThrough ? L("穿透：开") : L("穿透：关")
        refreshControls()
    }

    @objc private func exitTapped() { close() }

    private func canvasUnderPointer() -> AnnotationCanvas? {
        let point = NSEvent.mouseLocation
        guard let index = overlays.firstIndex(where: { $0.frame.contains(point) }) else { return canvases.first }
        return canvases[index]
    }

    private func editingCanvas() -> AnnotationCanvas? {
        lastEditedCanvas ?? canvasUnderPointer()
    }

    private func refreshControls() {
        toolPicker?.isEnabled = !passingThrough
        colorPicker?.isEnabled = !passingThrough
        let mosaic = tools.indices.contains(toolPicker?.selectedSegment ?? -1)
            && tools[toolPicker!.selectedSegment] == .mosaic
        mosaicControls?.isHidden = !mosaic
        widthControls?.isHidden = mosaic
        mosaicSegment?.isEnabled = !passingThrough
        mosaicSlider?.isEnabled = !passingThrough
        widthSlider?.isEnabled = !passingThrough
        deleteButton?.isEnabled = !passingThrough && !(editingCanvas()?.annotations.isEmpty ?? true)
        measureButton?.isEnabled = !passingThrough
        measureButton?.state = canvases.contains(where: { $0.isMeasuring }) ? .on : .off
        measureButton?.contentTintColor = canvases.contains(where: { $0.isMeasuring }) ? .controlAccentColor : .labelColor
        passButton?.contentTintColor = passingThrough ? .controlAccentColor : .labelColor
        undoButton?.isEnabled = !passingThrough && (editingCanvas()?.canUndo ?? false)
        redoButton?.isEnabled = !passingThrough && (editingCanvas()?.canRedo ?? false)
        clearButton?.isEnabled = !passingThrough && canvases.contains { !$0.annotations.isEmpty || $0.hasMeasurement }
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        toolbar?.orderOut(nil)
        toolbar = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        canvases.removeAll()
        toolPicker = nil
        colorPicker = nil
        undoButton = nil
        redoButton = nil
        clearButton = nil
        deleteButton = nil
        measureButton = nil
        widthLabel = nil
        widthSlider = nil
        widthValue = nil
        mosaicControls = nil
        widthControls = nil
        mosaicSegment = nil
        mosaicSlider = nil
        mosaicValue = nil
        passButton = nil
        lastEditedCanvas = nil
    }
}

private final class ScreenAnnotationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class AnnotationCloseButton: NSButton {
    private var hoverTracking: NSTrackingArea?
    private var isHovered = false

    func configureAppearance() { updateAppearance() }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = isHovered ? NSColor.systemRed.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
        contentTintColor = isHovered ? .systemRed : .secondaryLabelColor
    }
}
