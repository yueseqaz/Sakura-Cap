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
    private let colorWell = NSColorWell()
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let widthLabel = NSTextField(labelWithString: L("粗细"))
    private let widthSlider = NSSlider()
    private let widthValue = NSTextField(labelWithString: "4")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let deleteButton = NSButton()

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

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        let bar = buildToolbar()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bar.topAnchor),
        ])
        contentView = container
        // 保证宽度至少能放下工具栏（按“马赛克”控件显示时的最宽状态量），避免按钮重叠
        mosaicLabel.isHidden = false
        mosaicSegment.isHidden = false
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
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        zoomLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let saveButton = NSButton(title: L("保存"), target: self, action: #selector(saveTapped))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [toolSegment, mosaicLabel, mosaicSegment, colorWell,
                                        widthLabel, widthSlider, widthValue, undoButton, redoButton,
                                        deleteButton, clearButton, spacer,
                                        zoomOutButton, zoomLabel, zoomInButton, fitButton, pinButton,
                                        copyButton, saveButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
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
