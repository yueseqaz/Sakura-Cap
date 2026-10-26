import AppKit
import UniformTypeIdentifiers

@MainActor
final class ImageStitchToolController: NSObject, NSWindowDelegate {
    static let shared = ImageStitchToolController()

    private var window: NSWindow?
    private var canvas: StitchCanvasView?
    private var summary: NSTextField?
    private var selectionLabel: NSTextField?
    private var zoomLabel: NSTextField?
    private var gapField: NSTextField?
    private var scaleField: NSTextField?
    private var backgroundPopup: NSPopUpButton?
    private var editControls: [NSControl] = []
    private var selectionControls: [NSControl] = []
    private var exportControls: [NSControl] = []
    private var task: Task<Void, Never>?
    private var operation = UUID()
    private var busy = false
    private var gap: CGFloat = 0
    private var historyPreviews: [UUID: Int] = [:]

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("图片拼接")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 580)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .readOnly
        window.delegate = self
        self.window = window

        let canvas = StitchCanvasView(frame: .zero)
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onCommit = { [weak self] previous, name in self?.registerUndo(previous, name: name) }
        canvas.onDrop = { [weak self] in self?.add(urls: $0) }
        canvas.onDelete = { [weak self] in self?.removeSelected() }
        self.canvas = canvas

        let add = button("添加图片…", #selector(addTapped))
        let horizontal = button("横向排列", #selector(horizontalTapped))
        let vertical = button("纵向排列", #selector(verticalTapped))
        let gapLabel = label("间距", secondary: true)
        let gapField = NSTextField(string: String(Int(gap)))
        gapField.identifier = .init("stitchGap")
        gapField.alignment = .right
        gapField.target = self
        gapField.action = #selector(gapChanged)
        gapField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        self.gapField = gapField
        let background = NSPopUpButton(frame: .zero, pullsDown: false)
        background.addItems(withTitles: StitchBackground.allCases.map(\.title))
        background.target = self
        background.action = #selector(backgroundChanged)
        self.backgroundPopup = background
        let clear = button("清空", #selector(clearTapped))
        editControls = [add, horizontal, vertical, gapField, background, clear]
        let top = stack([add, separator(), horizontal, vertical, gapLabel, gapField,
                         label("px", secondary: true), spacer(), background, clear], spacing: 8)

        let inspectorTitle = label("所选图片")
        inspectorTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let selected = label("未选择图片", secondary: true)
        selected.identifier = .init("stitchSelection")
        selected.maximumNumberOfLines = 3
        selected.lineBreakMode = .byTruncatingMiddle
        self.selectionLabel = selected
        let scale = NSTextField(string: "100")
        scale.identifier = .init("stitchScale")
        scale.alignment = .right
        scale.target = self
        scale.action = #selector(scaleChanged)
        scale.widthAnchor.constraint(equalToConstant: 70).isActive = true
        self.scaleField = scale
        let scaleRow = stack([label("缩放"), scale, label("%", secondary: true)], spacing: 6)
        let original = button("恢复原始尺寸", #selector(originalTapped))
        let front = button("移到最前", #selector(frontTapped))
        let back = button("移到最后", #selector(backTapped))
        let delete = button("移除图片", #selector(deleteTapped))
        selectionControls = [scale, original, front, back, delete]
        let hint = label("拖动图片移动位置\n拖动四角等比缩放\n方向键微调，⇧ 加速\n⌘Z 撤销，⌘⇧Z 重做\n\n滚动平移画布\n⌘ + 滚动缩放\n按住空格拖动画布\n按住 ⌥ 暂停对齐吸附", secondary: true)
        hint.font = .systemFont(ofSize: 11)
        hint.maximumNumberOfLines = 0
        let inspectorContent = NSStackView(views: [inspectorTitle, selected, scaleRow, original, front, back, delete, separator(horizontal: true), hint])
        inspectorContent.orientation = .vertical
        inspectorContent.alignment = .leading
        inspectorContent.spacing = 10
        inspectorContent.setHuggingPriority(.init(1), for: .vertical)
        inspectorContent.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let inspector = NSVisualEffectView()
        inspector.material = .sidebar
        inspector.blendingMode = .withinWindow
        inspectorContent.translatesAutoresizingMaskIntoConstraints = false
        inspector.addSubview(inspectorContent)
        NSLayoutConstraint.activate([
            inspectorContent.leadingAnchor.constraint(equalTo: inspector.leadingAnchor),
            inspectorContent.trailingAnchor.constraint(equalTo: inspector.trailingAnchor),
            inspectorContent.topAnchor.constraint(equalTo: inspector.topAnchor),
            inspectorContent.bottomAnchor.constraint(lessThanOrEqualTo: inspector.bottomAnchor),
        ])
        inspector.widthAnchor.constraint(equalToConstant: 208).isActive = true
        selected.widthAnchor.constraint(equalToConstant: 176).isActive = true

        let summary = label("拖入图片开始拼接", secondary: true)
        summary.identifier = .init("stitchSummary")
        summary.lineBreakMode = .byTruncatingTail
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.summary = summary
        let minus = button("−", #selector(zoomOutTapped))
        let plus = button("+", #selector(zoomInTapped))
        let zoom = label("100%", secondary: true)
        zoom.alignment = .center
        zoom.widthAnchor.constraint(equalToConstant: 48).isActive = true
        self.zoomLabel = zoom
        let fit = button("适应画布", #selector(fitTapped))
        let copy = button("复制图片", #selector(copyTapped))
        let save = button("导出 PNG…", #selector(saveTapped))
        exportControls = [copy, save]
        let bottom = stack([summary, spacer(), minus, zoom, plus, fit, separator(), copy, save], spacing: 8)

        let topBar = bar(top)
        let bottomBar = bar(bottom)
        let divider = NSBox()
        divider.boxType = .separator
        let root = StitchWorkspaceView(top: topBar, bottom: bottomBar, canvas: canvas, sidebar: inspector, divider: divider)
        window.contentView = root
        window.contentMinSize = NSSize(width: 860, height: 548)
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let result = NSButton(title: L(title), target: self, action: action)
        result.bezelStyle = .rounded
        return result
    }

    private func label(_ title: String, secondary: Bool = false) -> NSTextField {
        let result = NSTextField(labelWithString: L(title))
        result.font = .systemFont(ofSize: 12)
        result.textColor = secondary ? .secondaryLabelColor : .labelColor
        return result
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentHuggingPriority(.init(1), for: .vertical)
        return view
    }

    private func separator(horizontal: Bool = false) -> NSBox {
        let result = NSBox()
        result.boxType = .separator
        if horizontal { result.widthAnchor.constraint(equalToConstant: 176).isActive = true }
        else { result.heightAnchor.constraint(equalToConstant: 20).isActive = true }
        return result
    }

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = .horizontal
        result.spacing = spacing
        result.alignment = .centerY
        return result
    }

    private func bar(_ content: NSStackView) -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        content.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func refresh() {
        guard let canvas else { return }
        let document = canvas.document
        let selected = document.images.first { $0.id == canvas.selectedID }
        editControls.forEach { $0.isEnabled = !busy }
        selectionControls.forEach { $0.isEnabled = !busy && selected != nil }
        exportControls.forEach { $0.isEnabled = !busy && document.canExport }
        canvas.isBusy = busy
        backgroundPopup?.selectItem(at: document.background.rawValue)
        if let selected {
            selectionLabel?.stringValue = "\(selected.url.lastPathComponent)\n\(Int(selected.frame.width.rounded())) × \(Int(selected.frame.height.rounded())) px"
            scaleField?.doubleValue = Double((selected.frame.width / selected.pixelSize.width * 1000).rounded() / 10)
        } else {
            selectionLabel?.stringValue = L("未选择图片")
            scaleField?.stringValue = "100"
        }
        if busy { summary?.stringValue = L("正在处理图片…") }
        else if document.images.isEmpty { summary?.stringValue = L("拖入图片开始拼接") }
        else {
            let size = document.outputBounds.size
            summary?.stringValue = String(format: L("%d 张 · %d × %d px"), document.images.count, Int(size.width), Int(size.height))
                + (document.canExport ? "" : " · " + L("超出导出限制，请缩小图片"))
        }
        summary?.textColor = !document.images.isEmpty && !document.canExport ? .systemOrange : .secondaryLabelColor
        summary?.toolTip = document.canExport ? nil : StitchFailure.tooLarge.localizedDescription
        zoomLabel?.stringValue = "\(Int((canvas.zoom * 100).rounded()))%"
    }

    private func registerUndo(_ previous: StitchDocument, name: String) {
        guard let canvas else { return }
        for image in previous.images + canvas.document.images {
            historyPreviews[image.id] = image.preview.bytesPerRow * image.preview.height
        }
        // Repeated remove/import cycles must not retain unbounded decoded thumbnails in undo.
        if !canvas.history.isUndoing && !canvas.history.isRedoing,
           historyPreviews.values.reduce(0, +) > 64 * 1024 * 1024 {
            canvas.history.removeAllActions()
            historyPreviews.removeAll()
            for image in previous.images + canvas.document.images {
                historyPreviews[image.id] = image.preview.bytesPerRow * image.preview.height
            }
        }
        let grouping = !canvas.history.isUndoing && !canvas.history.isRedoing
        if grouping { canvas.history.beginUndoGrouping() }
        canvas.history.registerUndo(withTarget: self) { target in
            guard let canvas = target.canvas else { return }
            let current = canvas.document
            target.registerUndo(current, name: name)
            canvas.document = previous
            if !previous.images.contains(where: { $0.id == canvas.selectedID }) { canvas.selectedID = nil }
            target.refresh()
        }
        canvas.history.setActionName(L(name))
        if grouping { canvas.history.endUndoGrouping() }
        refresh()
    }

    private func change(_ name: String, _ body: (inout StitchDocument) -> Void) {
        guard !busy, let canvas else { return }
        canvas.finishGesture()
        let previous = canvas.document
        body(&canvas.document)
        registerUndo(previous, name: name)
        window?.makeFirstResponder(canvas)
    }

    func add(urls: [URL]) {
        guard !busy, let canvas, !urls.isEmpty else { return }
        canvas.finishGesture()
        let capacity = StitchDocument.imageLimit - canvas.document.images.count
        guard capacity > 0 else { showError(L("最多可添加 32 张图片。")); return }
        let input = Array(urls.prefix(capacity))
        let truncated = urls.count > capacity
        let token = UUID()
        operation = token
        busy = true
        refresh()
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> ([StitchImage], [String]) in
                var loaded: [StitchImage] = []
                var failures: [String] = []
                for url in input {
                    if Task.isCancelled { break }
                    do { loaded.append(try StitchRenderer.load(url)) }
                    catch { failures.append(error.localizedDescription) }
                }
                return (loaded, failures)
            }
            let (loaded, failures) = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self, self.operation == token, let canvas = self.canvas else { return }
            self.busy = false
            if !loaded.isEmpty {
                self.change("添加图片") { $0.append(loaded, gap: self.gap) }
                canvas.selectedID = loaded.last?.id
                canvas.fit()
            }
            self.refresh()
            if !failures.isEmpty || truncated {
                let reason = failures.first.map { "\n\n" + $0 } ?? ""
                self.showError(String(format: L("已添加 %d 张图片。无法读取 %d 张；画布最多容纳 32 张。"), loaded.count, failures.count) + reason)
            }
        }
    }

    @objc private func addTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK { self?.add(urls: panel.urls) }
        }
    }

    @objc private func gapChanged() {
        gap = CGFloat(max(0, min(4096, gapField?.doubleValue ?? 0))).rounded()
        gapField?.doubleValue = gap
        window?.makeFirstResponder(canvas)
    }

    private func arrange(vertical: Bool) {
        gapChanged()
        change(vertical ? "纵向排列" : "横向排列") { $0.arrange(vertical: vertical, gap: gap) }
        canvas?.fit()
    }

    @objc private func horizontalTapped() { arrange(vertical: false) }
    @objc private func verticalTapped() { arrange(vertical: true) }
    @objc private func clearTapped() { change("清空") { $0.images.removeAll() }; canvas?.selectedID = nil; refresh() }
    @objc private func backgroundChanged() {
        guard let value = StitchBackground(rawValue: backgroundPopup?.indexOfSelectedItem ?? 0) else { return }
        change("更改背景") { $0.background = value }
    }

    @objc private func scaleChanged() {
        let scale = CGFloat(scaleField?.doubleValue ?? 100) / 100
        changeSelection("缩放图片") { $0.frame = StitchDocument.resizedFrame($0, scale: scale) }
    }

    @objc private func originalTapped() {
        changeSelection("恢复原始尺寸") { $0.frame.size = $0.pixelSize }
    }

    private func changeSelection(_ name: String, _ body: (inout StitchImage) -> Void) {
        guard let id = canvas?.selectedID, let index = canvas?.document.images.firstIndex(where: { $0.id == id }) else { return }
        change(name) { body(&$0.images[index]) }
    }

    private func reorder(front: Bool) {
        guard let id = canvas?.selectedID, let index = canvas?.document.images.firstIndex(where: { $0.id == id }) else { return }
        change(front ? "移到最前" : "移到最后") {
            let image = $0.images.remove(at: index)
            $0.images.insert(image, at: front ? $0.images.count : 0)
        }
    }

    @objc private func frontTapped() { reorder(front: true) }
    @objc private func backTapped() { reorder(front: false) }
    @objc private func deleteTapped() { removeSelected() }
    private func removeSelected() {
        guard let id = canvas?.selectedID else { return }
        change("移除图片") { $0.images.removeAll { $0.id == id } }
        canvas?.selectedID = nil
        refresh()
    }

    @objc private func fitTapped() { canvas?.fit() }
    @objc private func zoomInTapped() { canvas?.setZoom((canvas?.zoom ?? 1) * 1.25) }
    @objc private func zoomOutTapped() { canvas?.setZoom((canvas?.zoom ?? 1) / 1.25) }
    @objc private func copyTapped() { export(to: nil) }
    @objc private func saveTapped() {
        guard !busy, canvas?.document.canExport == true else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = L("拼接图片") + ".png"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let url = panel.url { self?.export(to: url) }
        }
    }

    private func export(to url: URL?) {
        guard !busy, let canvas, canvas.document.canExport else { return }
        canvas.finishGesture()
        let document = canvas.document
        busy = true
        let token = UUID()
        operation = token
        refresh()
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () throws -> Data? in
                try autoreleasepool {
                    let data = try StitchRenderer.pngData(document)
                    try Task.checkCancellation()
                    if let url { try data.write(to: url, options: .atomic); return nil }
                    return data
                }
            }
            do {
                let data = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let self, self.operation == token else { return }
                self.busy = false
                self.refresh()
                if let data {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setData(data, forType: .png)
                    self.summary?.stringValue = L("已复制拼接图片")
                } else { self.summary?.stringValue = L("拼接图片已保存") }
            } catch {
                guard !Task.isCancelled, let self, self.operation == token else { return }
                self.busy = false
                self.refresh()
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L("图片拼接")
        alert.informativeText = message
        alert.addButton(withTitle: L("好"))
        alert.beginSheetModal(for: window)
    }

    func windowWillClose(_ notification: Notification) {
        operation = UUID()
        task?.cancel()
        task = nil
        busy = false
        canvas?.finishGesture()
        canvas?.history.removeAllActions()
        historyPreviews.removeAll()
        canvas?.onChange = nil
        canvas?.onCommit = nil
        canvas?.document = StitchDocument()
        canvas = nil
        window = nil
        editControls = []
        selectionControls = []
        exportControls = []
    }
}

/// A flexible drawing surface must not inherit a stack view's preferred window height.
@MainActor
private final class StitchWorkspaceView: NSView {
    private let top: NSView
    private let bottom: NSView
    private let canvas: NSView
    private let sidebar: NSView
    private let divider: NSView

    init(top: NSView, bottom: NSView, canvas: NSView, sidebar: NSView, divider: NSView) {
        self.top = top
        self.bottom = bottom
        self.canvas = canvas
        self.sidebar = sidebar
        self.divider = divider
        super.init(frame: CGRect(x: 0, y: 0, width: 1060, height: 720))
        autoresizingMask = [.width, .height]
        for view in [top, bottom, canvas, sidebar, divider] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let height = max(0, bounds.height - 108)
        let width = max(0, bounds.width - 209)
        top.frame = CGRect(x: 0, y: bounds.height - 54, width: bounds.width, height: 54)
        bottom.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 54)
        canvas.frame = CGRect(x: 0, y: 54, width: width, height: height)
        divider.frame = CGRect(x: width, y: 54, width: 1, height: height)
        sidebar.frame = CGRect(x: width + 1, y: 54, width: 208, height: height)
    }
}

@MainActor
final class StitchCanvasView: NSView {
    var document = StitchDocument() { didSet { needsDisplay = true } }
    var selectedID: UUID? { didSet { needsDisplay = true; onChange?() } }
    var onChange: (() -> Void)?
    var onCommit: ((StitchDocument, String) -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onDelete: (() -> Void)?
    var isBusy = false
    let history = UndoManager()
    private(set) var zoom: CGFloat = 1
    private(set) var offset = CGPoint(x: 48, y: 48)
    private var gestureStart: StitchDocument?
    private var dragPoint = CGPoint.zero
    private var initialFrame = CGRect.zero
    private var resizeCorner: Int?
    private var panning = false
    private var spaceDown = false
    private var moved = false
    private var guides: [(Bool, CGFloat)] = []
    private var focusObserver: NSObjectProtocol?
    private static let checker: NSColor = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            NSColor(calibratedWhite: 0.9, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: image)
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        history.levelsOfUndo = 30
        history.groupsByEvent = false
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("图片拼接画布"))
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var undoManager: UndoManager? { history }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = nil
        if let window {
            focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                  object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.spaceDown = false
                    self?.finishGesture()
                }
            }
        }
    }

    deinit {
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
    }

    func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * zoom + offset.x, y: rect.minY * zoom + offset.y,
               width: rect.width * zoom, height: rect.height * zoom)
    }

    private func worldPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom)
    }

    func fit() {
        guard !document.images.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let rect = document.bounds
        zoom = max(0.005, min(1, (bounds.width - 96) / rect.width, (bounds.height - 96) / rect.height))
        offset = CGPoint(x: bounds.midX - rect.midX * zoom, y: bounds.midY - rect.midY * zoom)
        needsDisplay = true
        onChange?()
    }

    func setZoom(_ value: CGFloat, anchor: CGPoint? = nil) {
        guard value.isFinite else { return }
        let anchor = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let world = worldPoint(anchor)
        zoom = max(0.005, min(8, value))
        offset = CGPoint(x: anchor.x - world.x * zoom, y: anchor.y - world.y * zoom)
        needsDisplay = true
        onChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard !document.images.isEmpty else {
            let title = L("把图片拖到这里")
            let subtitle = L("自由拖动拼接，或使用上方按钮横向／纵向排列")
            drawText(title, y: bounds.midY - 25, font: .systemFont(ofSize: 22, weight: .medium), color: .labelColor)
            drawText(subtitle, y: bounds.midY + 12, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            return
        }
        let output = viewRect(document.outputBounds)
        let color: NSColor = document.background == .transparent ? Self.checker : (document.background == .white ? .white : .black)
        color.setFill()
        output.intersection(bounds).fill()
        for image in document.images {
            let rect = viewRect(image.frame)
            guard rect.intersects(dirtyRect) else { continue }
            NSImage(cgImage: image.preview, size: image.pixelSize).draw(in: rect, from: .zero, operation: .sourceOver,
                                                                      fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: output)
        border.lineWidth = 1
        border.stroke()
        if let selected = document.images.first(where: { $0.id == selectedID }) {
            let rect = viewRect(selected.frame)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2
            outline.stroke()
            for point in corners(rect) {
                let handle = NSBezierPath(roundedRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8), xRadius: 2, yRadius: 2)
                NSColor.white.setFill(); handle.fill()
                NSColor.controlAccentColor.setStroke(); handle.stroke()
            }
        }
        NSColor.systemPink.setStroke()
        let guide = NSBezierPath()
        guide.lineWidth = 1
        for (vertical, value) in guides {
            if vertical {
                let x = value * zoom + offset.x
                guide.move(to: CGPoint(x: x, y: 0)); guide.line(to: CGPoint(x: x, y: bounds.height))
            } else {
                let y = value * zoom + offset.y
                guide.move(to: CGPoint(x: 0, y: y)); guide.line(to: CGPoint(x: bounds.width, y: y))
            }
        }
        guide.stroke()
    }

    private func drawText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let value = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = value.size(withAttributes: attributes)
        value.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attributes)
    }

    private func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    override func mouseDown(with event: NSEvent) {
        guard !isBusy else { return }
        finishGesture()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        dragPoint = point
        moved = false
        panning = spaceDown || event.modifierFlags.contains(.control)
        if panning { NSCursor.closedHand.push(); return }
        if let selected = document.images.first(where: { $0.id == selectedID }),
           let corner = corners(viewRect(selected.frame)).firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) < 9 }) {
            resizeCorner = corner
            initialFrame = selected.frame
            gestureStart = document
            return
        }
        selectedID = document.images.last(where: { viewRect($0.frame).contains(point) })?.id
        if let selected = document.images.first(where: { $0.id == selectedID }) {
            initialFrame = selected.frame
            gestureStart = document
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isBusy else { return }
        let point = convert(event.locationInWindow, from: nil)
        if panning {
            offset.x += point.x - dragPoint.x
            offset.y += point.y - dragPoint.y
            dragPoint = point
            needsDisplay = true
            return
        }
        guard gestureStart != nil, let index = document.images.firstIndex(where: { $0.id == selectedID }) else { return }
        moved = true
        guides = []
        if let corner = resizeCorner {
            let anchor = corners(initialFrame)[(corner + 2) % 4]
            let initial = corners(initialFrame)[corner]
            let current = worldPoint(point)
            let dx = initial.x - anchor.x, dy = initial.y - anchor.y
            let factor = ((current.x - anchor.x) * dx + (current.y - anchor.y) * dy) / (dx * dx + dy * dy)
            let source = document.images[index].pixelSize
            let scale = min(8, max(0.01, initialFrame.width / source.width * factor))
            let size = CGSize(width: source.width * scale, height: source.height * scale)
            document.images[index].frame = CGRect(x: corner == 0 || corner == 3 ? anchor.x - size.width : anchor.x,
                                                  y: corner < 2 ? anchor.y - size.height : anchor.y,
                                                  width: size.width, height: size.height)
        } else {
            var frame = initialFrame.offsetBy(dx: (point.x - dragPoint.x) / zoom, dy: (point.y - dragPoint.y) / zoom)
            if !event.modifierFlags.contains(.option) { snap(&frame, excluding: index) }
            // Keep document coordinates bounded, even after very long drags at tiny zoom.
            frame.origin.x = min(1_000_000, max(-1_000_000, frame.origin.x.rounded()))
            frame.origin.y = min(1_000_000, max(-1_000_000, frame.origin.y.rounded()))
            document.images[index].frame = frame
        }
        onChange?()
    }

    private func snap(_ frame: inout CGRect, excluding index: Int) {
        let others = document.images.enumerated().filter { $0.offset != index }.map { $0.element.frame }
        let xs = others.flatMap { [$0.minX, $0.midX, $0.maxX] }
        let ys = others.flatMap { [$0.minY, $0.midY, $0.maxY] }
        func match(_ values: [CGFloat], _ targets: [CGFloat]) -> (CGFloat, CGFloat)? {
            var best: (CGFloat, CGFloat)?
            for value in values {
                for target in targets where abs(target - value) <= 7 / zoom {
                    if best == nil || abs(target - value) < abs(best!.0) { best = (target - value, target) }
                }
            }
            return best
        }
        if let (delta, target) = match([frame.minX, frame.midX, frame.maxX], xs) {
            frame.origin.x += delta; guides.append((true, target))
        }
        if let (delta, target) = match([frame.minY, frame.midY, frame.maxY], ys) {
            frame.origin.y += delta; guides.append((false, target))
        }
    }

    override func mouseUp(with event: NSEvent) { finishGesture() }

    func finishGesture() {
        let previous = gestureStart
        gestureStart = nil
        resizeCorner = nil
        guides = []
        if panning { NSCursor.pop() }
        panning = false
        if moved, let previous { onCommit?(previous, "移动或缩放图片") }
        moved = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            setZoom(zoom * exp(-event.scrollingDeltaY * 0.015), anchor: convert(event.locationInWindow, from: nil))
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            offset.x += event.scrollingDeltaX * multiplier
            offset.y += event.scrollingDeltaY * multiplier
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        guard !isBusy else { return }
        if event.keyCode == 49 { spaceDown = true; return }
        if event.keyCode == 51 || event.keyCode == 117 { finishGesture(); onDelete?(); return }
        if event.keyCode == 53 {
            if let previous = gestureStart { document = previous; moved = false; finishGesture() }
            else { selectedID = nil }
            onChange?()
            return
        }
        guard [123, 124, 125, 126].contains(event.keyCode),
              let index = document.images.firstIndex(where: { $0.id == selectedID }) else { super.keyDown(with: event); return }
        finishGesture()
        let previous = document
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: document.images[index].frame.origin.x -= step
        case 124: document.images[index].frame.origin.x += step
        case 125: document.images[index].frame.origin.y += step
        default: document.images[index].frame.origin.y -= step
        }
        onCommit?(previous, "移动图片")
        onChange?()
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceDown = false }
        else { super.keyUp(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        spaceDown = false
        finishGesture()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isBusy, window?.firstResponder === self,
              event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" else {
            return super.performKeyEquivalent(with: event)
        }
        finishGesture()
        if event.modifierFlags.contains(.shift) { history.redo() } else { history.undo() }
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        !isBusy && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isBusy,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
