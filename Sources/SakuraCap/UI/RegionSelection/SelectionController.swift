import AppKit
import CoreGraphics

/// 选择意图（菜单「开始录制」子菜单 / 设置面板入口）：
/// - displayOnly：全屏录制——蓝框高亮光标所在屏，单击即录该屏
/// - regionOnly ：框选区域——拖拽蓝框选区域
enum SelectionIntent {
    case displayOnly
    case regionOnly
}

/// 选区用途：录制 / 截图 / OCR
enum SelectionPurpose {
    case record
    case screenshot
    case ocr
    case scrolling
}

enum SelectionResult {
    case display(CGDirectDisplayID)
    case region(RegionSelection)
}

@MainActor
final class SelectionController: NSObject {
    static let shared = SelectionController()

    var onPicked: ((SelectionResult) -> Void)?
    var onCancelled: ((SelectionIntent) -> Void)?

    private(set) var currentIntent: SelectionIntent = .displayOnly
    private(set) var currentPurpose: SelectionPurpose = .record

    private var windows: [SelectionOverlayWindow] = []
    private var keyMonitor: Any?
    private var hoverTimer: Timer?
    private var hoveredDisplayID: CGDirectDisplayID = 0

    var isActive: Bool { !windows.isEmpty }

    func begin(_ intent: SelectionIntent, purpose: SelectionPurpose = .record) {
        guard windows.isEmpty else { return }
        currentIntent = intent
        currentPurpose = purpose
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = SelectionOverlayWindow(screen: screen, controller: self)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.overlayView)
            windows.append(window)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.finish(result: nil)
                return nil
            }
            return event
        }
        startHoverTimer()
        updateHover()
    }

    fileprivate func finish(result: SelectionResult?) {
        guard !windows.isEmpty else { return }
        hoverTimer?.invalidate()
        hoverTimer = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        hoveredDisplayID = 0
        if let result {
            onPicked?(result)
        } else {
            onCancelled?(currentIntent)
        }
    }

    private func startHoverTimer() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    /// 悬停高亮光标所在屏（30ms 轮询 NSEvent.mouseLocation，无需权限，跨屏可靠）
    private func updateHover() {
        guard currentIntent == .displayOnly, !windows.isEmpty else { return }
        let mouse = NSEvent.mouseLocation // AppKit 全局（左下原点）
        let displayHit = NSScreen.screens.first { $0.frame.contains(mouse) }?.displayID ?? 0
        guard displayHit != hoveredDisplayID else { return }
        hoveredDisplayID = displayHit
        for window in windows {
            window.overlayView.refreshHover(displayID: displayHit)
        }
    }
}

@MainActor
final class RegionFrameOverlay {
    static let shared = RegionFrameOverlay()

    private var window: NSWindow?

    func show(region: RegionSelection) {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }) else { return }
        let localRect = ScreenCoordinate.appKitLocalRect(fromSCKRect: region.sckRect, in: screen)
        let frame = CGRect(x: screen.frame.minX + localRect.minX,
                           y: screen.frame.minY + localRect.minY,
                           width: localRect.width,
                           height: localRect.height)
        let window = NSWindow(contentRect: frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver + 2
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.sharingType = .none
        window.contentView = RegionFrameView(frame: NSRect(origin: .zero, size: frame.size))
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class RegionFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 3
        path.stroke()
    }
}

final class SelectionOverlayWindow: NSWindow {
    let overlayView: SelectionOverlayView
    private weak var controller: SelectionController?

    init(screen: NSScreen, controller: SelectionController) {
        self.controller = controller
        overlayView = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                           screen: screen,
                                           controller: controller)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .none // 选择界面永不进入录制
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.finish(result: nil)
            return
        }
        super.keyDown(with: event)
    }
}

final class SelectionOverlayView: NSView {
    private let screen: NSScreen
    private weak var controller: SelectionController?

    private var anchor: NSPoint?
    private var currentPoint: NSPoint?
    private var isDraggingRegion = false
    private var hoveredDisplayID: CGDirectDisplayID = 0

    init(frame: CGRect, screen: NSScreen, controller: SelectionController) {
        self.screen = screen
        self.controller = controller
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func refreshHover(displayID: CGDirectDisplayID) {
        hoveredDisplayID = displayID
        needsDisplay = true
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        currentPoint = anchor
        isDraggingRegion = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard anchor != nil, controller?.currentIntent == .regionOnly else { return } // 仅框选模式响应拖拽
        currentPoint = convert(event.locationInWindow, from: nil)
        if !isDraggingRegion, let a = anchor, let c = currentPoint,
           Self.distance(a, c) > 6 {
            isDraggingRegion = true
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let a = anchor, let c = currentPoint else { return }
        anchor = nil
        currentPoint = nil
        let dragging = isDraggingRegion
        isDraggingRegion = false

        if dragging {
            // 拖拽 → 区域（intersection(bounds)：越界部分钳制在本屏，区域不跨屏）
            let rect = Self.normalized(a, c).intersection(bounds)
            guard rect.width >= 24, rect.height >= 24 else {
                needsDisplay = true
                return
            }
            let selection = RegionSelection(
                displayID: screen.displayID,
                sckRect: ScreenCoordinate.sckSourceRect(fromAppKitLocalRect: rect, in: screen),
                pixelWidth: Int(rect.width * screen.backingScaleFactor),
                pixelHeight: Int(rect.height * screen.backingScaleFactor))
            controller?.finish(result: .region(selection))
            return
        }

        // 单击：全屏模式 → 录该屏；框选模式 → 单击无操作
        if controller?.currentIntent == .displayOnly {
            controller?.finish(result: .display(screen.displayID))
        } else {
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.finish(result: nil)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor

        // 拖拽框选进行中
        if isDraggingRegion, let a = anchor, let c = currentPoint {
            let rect = Self.normalized(a, c).intersection(bounds)
            fillDim(cutout: rect)
            drawBorder(rect, color: accent, lineWidth: 3)
            drawPill("\(Int(rect.width)) × \(Int(rect.height))",
                     center: NSPoint(x: rect.midX, y: min(bounds.height - 34, rect.maxY + 24)))
            return
        }

        switch controller?.currentIntent ?? .displayOnly {
        case .displayOnly:
            fillDim(cutout: nil)
            if hoveredDisplayID == screen.displayID {
                drawBorder(bounds.insetBy(dx: 4, dy: 4), color: accent, lineWidth: 8)
            }
            drawPill(L("点击要录制的屏幕 · Esc 取消"),
                     center: NSPoint(x: bounds.midX, y: bounds.height - 48))
        case .regionOnly:
            fillDim(cutout: nil)
            drawPill(L("拖拽框选录制区域（区域不跨屏）· Esc 取消"),
                     center: NSPoint(x: bounds.midX, y: bounds.height - 48))
        }
    }

    /// 全屏压暗，cutout 区域镂空不压暗
    private func fillDim(cutout: CGRect?) {
        let mask = NSBezierPath(rect: bounds)
        if let cutout {
            mask.append(NSBezierPath(rect: cutout))
        }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.22).setFill()
        mask.fill()
    }

    private func drawBorder(_ rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        color.setStroke()
        let outer = NSBezierPath(rect: rect)
        outer.lineWidth = lineWidth
        outer.stroke()
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let inner = NSBezierPath(rect: rect.insetBy(dx: lineWidth + 1, dy: lineWidth + 1))
        inner.lineWidth = 1
        inner.stroke()
    }

    private func drawPill(_ string: String, center: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let size = attributed.size()
        let pillRect = NSRect(x: center.x - size.width / 2 - 12,
                              y: center.y - 10,
                              width: size.width + 24,
                              height: size.height + 14)
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.55).setFill()
        pill.fill()
        attributed.draw(at: NSPoint(x: pillRect.minX + 12, y: pillRect.minY + 7))
    }

    private static func normalized(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private static func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
