import AppKit

/// 「定住」：把图片干干净净地贴在屏幕上（无边框、无标题栏），四周只有一圈红色虚线框。
/// 右上角有关闭 / 放大 / 缩小按钮；鼠标滚轮可等比例缩放；拖动可移动；双击关闭。
@MainActor
final class PinnedImageController {
    static let shared = PinnedImageController()
    private var windows: [PinnedImageWindow] = []

    func pin(_ image: CGImage) {
        let window = PinnedImageWindow(image: image, offsetIndex: windows.count) { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
        }
        windows.append(window)
        window.orderFrontRegardless()
    }
}

final class PinnedImageWindow: NSWindow {
    private let pinnedView = PinnedImageView()
    private let onClose: (PinnedImageWindow) -> Void
    private let baseSize: NSSize
    private var zoom: CGFloat = 1
    private let minZoom: CGFloat
    private let maxZoom: CGFloat

    init(image: CGImage, offsetIndex: Int, onClose: @escaping (PinnedImageWindow) -> Void) {
        self.onClose = onClose
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = min(1, min(visible.width * 0.8 / CGFloat(image.width), visible.height * 0.8 / CGFloat(image.height)))
        baseSize = NSSize(width: max(40, CGFloat(image.width) * scale), height: max(40, CGFloat(image.height) * scale))
        minZoom = max(0.01, 6 / max(baseSize.width, baseSize.height)) // 可以小到一个点
        maxZoom = max(1, min(visible.width / baseSize.width, visible.height / baseSize.height)) // 可以大到全屏

        super.init(contentRect: NSRect(origin: .zero, size: baseSize),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly // 可用于录制里当参考图
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
        pinnedView.frame = NSRect(origin: .zero, size: baseSize)
        pinnedView.autoresizingMask = [.width, .height]
        pinnedView.image = image
        contentView = pinnedView

        let controls = NSStackView(views: [
            makeControl("minus.magnifyingglass", #selector(zoomOutTapped)),
            makeControl("plus.magnifyingglass", #selector(zoomInTapped)),
            makeControl("xmark", #selector(closeTapped)),
        ])
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        pinnedView.controls = controls
        pinnedView.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: pinnedView.topAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: pinnedView.trailingAnchor, constant: -8),
        ])

        let stagger = CGFloat(offsetIndex % 5) * 24
        setFrameOrigin(NSPoint(x: visible.midX - baseSize.width / 2 + stagger,
                               y: visible.midY - baseSize.height / 2 + stagger))
    }

    private func makeControl(_ symbol: String, _ action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 12
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        button.contentTintColor = .white
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    /// 等比例缩放，保持「左上角」不动
    func zoomBy(_ factor: CGFloat) {
        let newZoom = min(maxZoom, max(minZoom, zoom * factor))
        guard abs(newZoom - zoom) > 0.0001 else { return }
        zoom = newZoom
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        let size = NSSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
    }

    @objc private func zoomInTapped() { zoomBy(1.12) }
    @objc private func zoomOutTapped() { zoomBy(0.89) }
    @objc private func closeTapped() { close() }

    override func close() {
        super.close()
        onClose(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PinnedImageView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    weak var controls: NSView?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { controls?.isHidden = false }
    override func mouseExited(with event: NSEvent) { controls?.isHidden = true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)

        // 红色虚线边框
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        border.lineWidth = 2
        let pattern: [CGFloat] = [6, 4]
        border.setLineDash(pattern, count: 2, phase: 0)
        NSColor.systemRed.setStroke()
        border.stroke()
    }

    override func scrollWheel(with event: NSEvent) {
        // 降敏：每格约 ±1.5%
        let factor = min(1.12, max(0.9, pow(1.012, event.scrollingDeltaY)))
        (window as? PinnedImageWindow)?.zoomBy(factor)
    }
}
