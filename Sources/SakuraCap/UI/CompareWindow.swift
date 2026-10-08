import AppKit
import UniformTypeIdentifiers

/// 截图对比：在原图与另一张图之间拖动分割线对比，支持左右 / 上下。
@MainActor
final class CompareController {
    static let shared = CompareController()

    private var windows: [CompareWindowController] = []
    private var pendingCapture: ((CGImage) -> Void)?

    func open(original: CGImage) {
        NSApp.activate(ignoringOtherApps: true)
        let controller = CompareWindowController(original: original)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.windows.removeAll { $0 === controller }
        }
        windows.append(controller)
        controller.show()
    }

    /// 进入框选截图，选完把图交给 completion
    func requestCapture(_ completion: @escaping (CGImage) -> Void) {
        pendingCapture = completion
        SelectionController.shared.begin(.regionOnly, purpose: .compare)
    }

    func deliver(_ image: CGImage) {
        let completion = pendingCapture
        pendingCapture = nil
        completion?(image)
    }

    /// 取消框选时丢弃待处理回调
    func cancelPendingCapture() { pendingCapture = nil }
}

@MainActor
final class CompareWindowController {
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let compareView = CompareView()
    private let saveButton = NSButton()
    private let orientationSegment = NSSegmentedControl()
    private let hintLabel = NSTextField(labelWithString: "")

    init(original: CGImage) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = L("截图对比")
        window.isReleasedWhenClosed = false
        window.sharingType = .none // 永不进入录制/截图
        window.minSize = NSSize(width: 480, height: 360)

        compareView.imageA = original

        let container = NSView()
        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow

        let captureButton = NSButton(title: L("框选截图"), target: self, action: #selector(captureTapped))
        captureButton.bezelStyle = .rounded
        let uploadButton = NSButton(title: L("选择图片…"), target: self, action: #selector(uploadTapped))
        uploadButton.bezelStyle = .rounded

        orientationSegment.segmentCount = 2
        orientationSegment.setLabel(L("左右"), forSegment: 0)
        orientationSegment.setLabel(L("上下"), forSegment: 1)
        orientationSegment.selectedSegment = 0
        orientationSegment.target = self
        orientationSegment.action = #selector(orientationChanged)

        saveButton.title = L("保存")
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.isEnabled = false

        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.stringValue = L("框选截图或选择图片后，拖动分割线对比")
        hintLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [captureButton, uploadButton, orientationSegment, hintLabel, saveButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        compareView.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(compareView)
        container.addSubview(bar)
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            compareView.topAnchor.constraint(equalTo: container.topAnchor),
            compareView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            compareView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            compareView.bottomAnchor.constraint(equalTo: bar.topAnchor),
        ])
        window.contentView = container

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClose?() }
        }
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func setSecond(_ image: CGImage) {
        compareView.imageB = image
        saveButton.isEnabled = true
        hintLabel.stringValue = L("拖动分割线对比，可切换左右 / 上下")
    }

    @objc private func captureTapped() {
        CompareController.shared.requestCapture { [weak self] image in self?.setSecond(image) }
    }

    @objc private func uploadTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = L("选择要对比的图片")
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        setSecond(cg)
    }

    @objc private func orientationChanged() {
        compareView.orientation = orientationSegment.selectedSegment == 1 ? .vertical : .horizontal
    }

    @objc private func saveTapped() {
        guard let cg = compareView.snapshot(),
              let dir = OutputDirectoryPicker.ensureDirectory(current: AppSettings.shared.outputDirectory),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        let url = dir.appendingPathComponent(FileName.make(ext: "png"))
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            Toast.show(title: L("已保存对比图"), detail: url.lastPathComponent)
        } catch {
            Toast.show(title: L("保存失败"), detail: error.localizedDescription)
        }
    }
}

/// 对比视图：A 铺满，B 按分割线裁剪叠加，可拖动分割线。
final class CompareView: NSView {
    enum Orientation { case horizontal, vertical }

    var imageA: CGImage? { didSet { needsDisplay = true } }
    var imageB: CGImage? { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var orientation: Orientation = .horizontal {
        didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }
    var divider: CGFloat = 0.5 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard imageB != nil else { return }
        addCursorRect(bounds, cursor: orientation == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    private func fittedRect(for image: CGImage) -> NSRect {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / iw, bounds.height / ih)
        let w = iw * scale, h = ih * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    private var imageRect: NSRect { imageA.map(fittedRect) ?? bounds }

    override func draw(_ dirtyRect: NSRect) {
        guard let imageA else { return }
        let rect = fittedRect(for: imageA)
        NSImage(cgImage: imageA, size: rect.size).draw(in: rect)

        guard let imageB else { return }
        NSGraphicsContext.saveGraphicsState()
        let lineAt: CGFloat
        let clip: NSRect
        if orientation == .horizontal {
            lineAt = rect.minX + rect.width * divider
            clip = NSRect(x: lineAt, y: rect.minY, width: rect.maxX - lineAt, height: rect.height)
        } else {
            lineAt = rect.minY + rect.height * divider
            clip = NSRect(x: rect.minX, y: lineAt, width: rect.width, height: rect.maxY - lineAt)
        }
        NSBezierPath(rect: clip).addClip()
        NSImage(cgImage: imageB, size: rect.size).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        // 分割线 + 手柄
        let line = NSBezierPath()
        line.lineWidth = 2
        let mid: NSPoint
        if orientation == .horizontal {
            line.move(to: NSPoint(x: lineAt, y: rect.minY))
            line.line(to: NSPoint(x: lineAt, y: rect.maxY))
            mid = NSPoint(x: lineAt, y: rect.midY)
        } else {
            line.move(to: NSPoint(x: rect.minX, y: lineAt))
            line.line(to: NSPoint(x: rect.maxX, y: lineAt))
            mid = NSPoint(x: rect.midX, y: lineAt)
        }
        NSColor.white.withAlphaComponent(0.92).setStroke()
        line.stroke()
        let handle = NSBezierPath(ovalIn: NSRect(x: mid.x - 13, y: mid.y - 13, width: 26, height: 26))
        NSColor.controlAccentColor.setFill()
        handle.fill()
        NSColor.white.setStroke()
        handle.lineWidth = 2
        handle.stroke()
    }

    override func mouseDown(with event: NSEvent) { updateDivider(with: event) }
    override func mouseDragged(with event: NSEvent) { updateDivider(with: event) }

    private func updateDivider(with event: NSEvent) {
        guard imageB != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        if orientation == .horizontal {
            divider = max(0, min(1, (point.x - rect.minX) / max(1, rect.width)))
        } else {
            divider = max(0, min(1, (point.y - rect.minY) / max(1, rect.height)))
        }
    }

    func snapshot() -> CGImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }
}
