import AppKit
import UniformTypeIdentifiers

/// 对比工具：菜单「工具 → 对比…」打开，左右两栏各放一张图片，
/// 在当前窗口内**完整显示两张图**（只保持宽高比缩放、不变形、不放大超原尺寸），
/// 用于整图层面的对比。
@MainActor
final class ImageCompareToolController: NSObject {
    static let shared = ImageCompareToolController()

    private var window: NSWindow?
    private var leftPane: ImageComparePane?
    private var rightPane: ImageComparePane?
    private var hintLabel: NSTextField?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("对比")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 420)
        // 与其它工具窗口一致：悬浮、跟随所有空间、不进录屏/远程共享
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .readOnly

        let left = ImageComparePane()
        let right = ImageComparePane()
        left.onImageChange = { [weak self] in self?.refreshHint() }
        right.onImageChange = { [weak self] in self?.refreshHint() }
        leftPane = left
        rightPane = right

        let chooseLeft = NSButton(title: L("选择左图…"), target: nil, action: nil)
        chooseLeft.bezelStyle = .rounded
        chooseLeft.target = left
        chooseLeft.action = #selector(ImageComparePane.chooseTapped)
        let chooseRight = NSButton(title: L("选择右图…"), target: nil, action: nil)
        chooseRight.bezelStyle = .rounded
        chooseRight.target = right
        chooseRight.action = #selector(ImageComparePane.chooseTapped)
        let swap = NSButton(title: L("交换"), target: self, action: #selector(swapTapped))
        swap.bezelStyle = .rounded
        let clear = NSButton(title: L("清空"), target: self, action: #selector(clearTapped))
        clear.bezelStyle = .rounded

        let hint = NSTextField(labelWithString: L("拖入图片或点击上方按钮，两张图完整显示、保持宽高比"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hintLabel = hint

        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        let stack = NSStackView(views: [chooseLeft, chooseRight, swap, clear, hint])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        let split = EvenSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(left)
        split.addArrangedSubview(right)

        let container = NSView()
        split.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(split)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: container.topAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            left.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            right.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        window.contentView = container
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func refreshHint() {
        guard let hintLabel else { return }
        let left = leftPane?.imageDescription() ?? L("未选择")
        let right = rightPane?.imageDescription() ?? L("未选择")
        hintLabel.stringValue = String(format: L("左：%@　右：%@　·　完整显示，保持宽高比"), left, right)
    }

    @objc private func swapTapped() {
        guard let leftPane, let rightPane else { return }
        let image = leftPane.image
        leftPane.setImage(rightPane.image)
        rightPane.setImage(image)
        refreshHint()
    }

    @objc private func clearTapped() {
        leftPane?.setImage(nil)
        rightPane?.setImage(nil)
        refreshHint()
    }
}

/// 对比窗口的单侧：在自身边界内按宽高比完整绘制图片（不超过原尺寸），支持拖入文件
@MainActor
final class ImageComparePane: NSView {
    private(set) var image: CGImage?
    var onImageChange: (() -> Void)?

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    func setImage(_ image: CGImage?) {
        self.image = image
        needsDisplay = true
        onImageChange?()
    }

    func imageDescription() -> String {
        guard let image else { return L("未选择") }
        return String(format: L("%d × %d px"), image.width, image.height)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let image else {
            let text = L("拖入图片，或点击上方「选择」按钮")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes)
            return
        }
        // 完整显示：按宽高比缩放到刚好放满可视区域；小图不放大，保持锐利
        let imageWidth = CGFloat(image.width), imageHeight = CGFloat(image.height)
        guard imageWidth > 0, imageHeight > 0, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / imageWidth, bounds.height / imageHeight, 1)
        let width = imageWidth * scale, height = imageHeight * scale
        let rect = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                          width: width, height: height)
        NSImage(cgImage: image, size: rect.size).draw(in: rect)
    }

    // MARK: 拖放

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first,
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        setImage(image)
        return true
    }

    @objc func chooseTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = L("选择要对比的图片")
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        setImage(image)
    }
}

/// 左右两栏默认始终平分（50/50）；用户拖过分隔条后不再自动平分
final class EvenSplitView: NSSplitView {
    var keepEven = true

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isNearDivider(point) { keepEven = false }
        super.mouseDown(with: event)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        if keepEven, subviews.count == 2, bounds.width > 0 {
            setPosition(bounds.width / 2, ofDividerAt: 0)
        }
    }

    private func isNearDivider(_ point: NSPoint) -> Bool {
        guard subviews.count == 2 else { return false }
        return abs(point.x - subviews[0].frame.maxX) <= max(4, dividerThickness + 2)
    }
}
