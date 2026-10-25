import AppKit
import UniformTypeIdentifiers

/// 对比工具：菜单「工具 → 对比…」打开，左右两栏各放一张图片，
/// **原比例 1:1 展示、绝不缩放适配**——图比视口大就只显示一部分，滚动查看；
/// 两侧滚动位置联动，方便对齐同一区域比较。
@MainActor
final class ImageCompareToolController: NSObject {
    static let shared = ImageCompareToolController()

    private var window: NSWindow?
    private var leftPane: ImageComparePane?
    private var rightPane: ImageComparePane?
    private var hintLabel: NSTextField?
    private var syncLock = false
    private var boundsObservers: [NSObjectProtocol] = []

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

        let left = ImageComparePane(title: L("左图"))
        let right = ImageComparePane(title: L("右图"))
        left.onImageChange = { [weak self] in self?.refreshHint() }
        right.onImageChange = { [weak self] in self?.refreshHint() }
        leftPane = left
        rightPane = right

        // 滚动联动：一侧滚动，另一侧跟随相同偏移（syncLock 防循环）
        for (source, target) in [(left, right), (right, left)] {
            source.scrollView.contentView.postsBoundsChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: source.scrollView.contentView, queue: .main
            ) { [weak self, weak source, weak target] _ in
                MainActor.assumeIsolated {
                    guard let self, let source, let target, !self.syncLock else { return }
                    self.syncLock = true
                    defer { self.syncLock = false }
                    let origin = source.scrollView.contentView.bounds.origin
                    target.scrollView.contentView.scroll(to: origin)
                    target.scrollView.reflectScrolledClipView(target.scrollView.contentView)
                }
            }
            boundsObservers.append(observer)
        }

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

        let hint = NSTextField(labelWithString: L("拖入图片或点击上方按钮，原比例 1:1 对比，滚动自动联动"))
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

        let split = NSSplitView()
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
        hintLabel.stringValue = String(format: L("左：%@　右：%@　·　原比例 1:1，滚动联动"), left, right)
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

    deinit {
        boundsObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

/// 对比窗口的单侧：滚动视图 + 1:1 绘制的图片文档视图，支持拖入文件
@MainActor
final class ImageComparePane: NSView {
    let scrollView = NSScrollView()
    private let imageView = OriginalScaleImageView()
    private let placeholder: String
    var onImageChange: (() -> Void)?

    init(title: String) {
        placeholder = String(format: L("%@\n拖入图片，或点击上方「选择」按钮"), title)
        super.init(frame: .zero)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = imageView
        imageView.placeholderText = placeholder
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        registerForDraggedTypes([.fileURL])
        postsFrameChangedNotifications = true
    }

    required init?(coder: NSCoder) { nil }

    var image: CGImage? { imageView.image }

    func setImage(_ image: CGImage?) {
        imageView.image = image
        tileDocumentView()
        needsDisplay = true
        onImageChange?()
    }

    func imageDescription() -> String {
        guard let image else { return L("未选择") }
        return String(format: L("%d × %d px"), image.width, image.height)
    }

    /// 文档视图尺寸 = max(图片尺寸, 视口尺寸)：大图可滚动，小图居中不放大
    private func tileDocumentView() {
        let viewport = scrollView.contentView.bounds.size
        let imageSize = imageView.image.map { NSSize(width: $0.width, height: $0.height) } ?? .zero
        imageView.setFrameSize(NSSize(width: max(imageSize.width, viewport.width),
                                      height: max(imageSize.height, viewport.height)))
    }

    override func layout() {
        super.layout()
        tileDocumentView()
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

/// 1:1 绘制图片的文档视图：一个图像像素 = 一个界面点，绝不缩放
final class OriginalScaleImageView: NSView {
    var image: CGImage?
    var placeholderText: String?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let image else {
            guard let placeholderText else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    style.lineSpacing = 4
                    return style
                }(),
            ]
            let size = (placeholderText as NSString).size(withAttributes: attributes)
            (placeholderText as NSString).draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes)
            return
        }
        // 居中绘制原尺寸（图像尺寸即点尺寸，1 图像像素 = 1pt）
        let rect = NSRect(x: (bounds.width - CGFloat(image.width)) / 2,
                          y: (bounds.height - CGFloat(image.height)) / 2,
                          width: CGFloat(image.width),
                          height: CGFloat(image.height))
        NSImage(cgImage: image, size: rect.size).draw(in: rect)
    }
}
