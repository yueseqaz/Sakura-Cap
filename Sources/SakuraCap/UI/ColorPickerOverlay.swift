import AppKit
import ScreenCaptureKit

/// 全局取色：十字准心、跟随色块，单击复制 HEX 并退出，Esc / 右键取消。
@MainActor
final class ColorPickerSession: NSObject {
    static let shared = ColorPickerSession()

    private var windows: [ColorPickerOverlayWindow] = []
    private var timer: Timer?
    private var keyMonitor: Any?
    private var captures: [CGDirectDisplayID: ScreenCapturer] = [:]
    private var preparationTask: Task<Void, Never>?
    private var samplingTask: Task<Void, Never>?
    private var commitTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var previousApp: NSRunningApplication?
    private var nativeSampler: NSColorSampler?
    private var lastSampleAt = Date.distantPast
    private var currentColor: NSColor?
    private var currentHex = ""
    private var hoveredDisplayID: CGDirectDisplayID?
    private var committing = false

    private static let pollInterval: TimeInterval = 1.0 / 60.0
    private static let sampleInterval: TimeInterval = 0.1

    func start() {
        guard sessionID == nil else { return }
        // macOS 13 没有 SCScreenshotManager，使用系统取色器，而不是打开无法采样的覆盖层。
        guard #available(macOS 14.0, *) else {
            let id = UUID()
            sessionID = id
            let sampler = NSColorSampler()
            nativeSampler = sampler
            sampler.show { [weak self] color in
                Task { @MainActor in
                    guard let self, self.sessionID == id else { return }
                    if let color { self.finish(with: Self.hex(of: color), sessionID: id) }
                    else { self.stop() }
                }
            }
            return
        }
        guard PermissionCenter.screenCaptureGranted() else {
            Toast.show(title: L("需要「屏幕录制」权限"), detail: nil,
                       actionTitle: L("打开设置"), action: PermissionCenter.openScreenCaptureSettings)
            return
        }

        let id = UUID()
        sessionID = id
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = ColorPickerOverlayWindow(screen: screen, session: self)
            windows.append(window)
            window.orderFrontRegardless()
        }
        guard let activeWindow = windowAndLocalPoint(at: NSEvent.mouseLocation)?.0 ?? windows.first else {
            stop()
            return
        }
        activeWindow.makeKeyAndOrderFront(nil)
        activeWindow.makeFirstResponder(activeWindow.overlayView)
        activeWindow.invalidateCursorRects(for: activeWindow.overlayView)
        activeWindow.overlayView.pickerCursor.set()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
        Toast.show(title: L("点击屏幕任意位置取色"), detail: L("按 Esc 取消"))

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()

        let screens = NSScreen.screens
        let excludeIDs = Set(windows.map(\.windowNumber))
        preparationTask = Task { @MainActor in
            for screen in screens {
                let capturer = await ScreenCapturer(displayID: screen.displayID, excludingWindowNumbers: excludeIDs)
                guard self.sessionID == id, !Task.isCancelled else { return }
                guard let capturer else {
                    self.samplingFailed(sessionID: id)
                    return
                }
                self.captures[screen.displayID] = capturer
            }
        }
    }

    private func stop() {
        sessionID = nil
        timer?.invalidate()
        timer = nil
        preparationTask?.cancel()
        preparationTask = nil
        samplingTask?.cancel()
        samplingTask = nil
        commitTask?.cancel()
        commitTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        captures.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        nativeSampler = nil
        currentColor = nil
        currentHex = ""
        hoveredDisplayID = nil
        lastSampleAt = .distantPast
        committing = false
        NSCursor.arrow.set()
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func tick() {
        guard let id = sessionID, !committing else { return }
        let mouse = NSEvent.mouseLocation
        for window in windows where !window.screenFrame.contains(mouse) {
            window.overlayView.cursorPoint = nil
            window.overlayView.color = nil
            window.overlayView.needsDisplay = true
        }
        guard let (window, local) = windowAndLocalPoint(at: mouse) else { return }
        // 菜单收起、窗口激活及跨屏会重置系统光标；会话期间持续恢复准心。
        window.overlayView.ensurePickerCursor()
        if hoveredDisplayID != window.displayID {
            hoveredDisplayID = window.displayID
            currentColor = nil
            currentHex = ""
        }
        window.overlayView.cursorPoint = local
        window.overlayView.color = currentColor
        window.overlayView.hex = currentHex
        window.overlayView.needsDisplay = true

        let now = Date()
        guard samplingTask == nil, now.timeIntervalSince(lastSampleAt) >= Self.sampleInterval,
              let capturer = captures[window.displayID] else { return }
        lastSampleAt = now
        let size = window.overlayView.bounds.size
        samplingTask = Task { @MainActor in
            defer { if self.sessionID == id { self.samplingTask = nil } }
            let color = await capturer.color(at: local, in: size)
            guard self.sessionID == id, !Task.isCancelled, !self.committing,
                  self.hoveredDisplayID == window.displayID else { return }
            guard let color else {
                self.samplingFailed(sessionID: id)
                return
            }
            self.currentColor = color
            self.currentHex = Self.hex(of: color)
        }
    }

    private func windowAndLocalPoint(at global: NSPoint) -> (ColorPickerOverlayWindow, NSPoint)? {
        for window in windows where window.screenFrame.contains(global) {
            // 通过视图换算处理 isFlipped，不能把屏幕左下原点坐标直接用于绘制。
            let local = window.overlayView.convert(window.convertPoint(fromScreen: global), from: nil)
            return (window, local)
        }
        return nil
    }

    fileprivate func commit(at global: NSPoint) {
        guard let id = sessionID, !committing,
              let (window, local) = windowAndLocalPoint(at: global) else { return }
        committing = true
        timer?.invalidate()
        timer = nil
        let size = window.overlayView.bounds.size
        let preparation = preparationTask
        let preview = samplingTask
        commitTask = Task { @MainActor in
            // 刚进入就点击也要等待采集器就绪；提交不能复用滞后的悬停色值。
            await preparation?.value
            await preview?.value
            guard self.sessionID == id, !Task.isCancelled else { return }
            guard let capturer = self.captures[window.displayID],
                  let color = await capturer.color(at: local, in: size) else {
                self.samplingFailed(sessionID: id)
                return
            }
            guard self.sessionID == id, !Task.isCancelled else { return }
            self.finish(with: Self.hex(of: color), sessionID: id)
        }
    }

    fileprivate func cancel() { stop() }

    private func samplingFailed(sessionID id: UUID) {
        guard sessionID == id else { return }
        stop()
        Toast.show(title: L("无法读取屏幕颜色"), detail: L("请检查屏幕录制权限后重试"))
    }

    private func finish(with hex: String, sessionID id: UUID) {
        guard sessionID == id else { return }
        stop()
        guard !hex.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        Toast.show(title: String(format: L("已复制颜色 %@"), hex),
                   detail: L("（HEX 已进剪贴板）"))
    }

    private static func hex(of color: NSColor) -> String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X",
                      Int((srgb.redComponent * 255).rounded()),
                      Int((srgb.greenComponent * 255).rounded()),
                      Int((srgb.blueComponent * 255).rounded()))
    }
}

/// 排除覆盖层后采样；按实际截图尺寸定位，兼容 Retina、缩放及多显示器。
@MainActor
final class ScreenCapturer {
    private let filter: SCContentFilter
    private let config: SCStreamConfiguration

    init?(displayID: CGDirectDisplayID, excludingWindowNumbers: Set<Int>) async {
        guard #available(macOS 14.0, *) else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let controls = content.windows.filter { excludingWindowNumbers.contains(Int($0.windowID)) }
        let pixels = DisplayPixelMetrics.size(displayID)
        let config = SCStreamConfiguration()
        config.width = pixels.width
        config.height = pixels.height
        config.showsCursor = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        self.filter = SCContentFilter(display: display, excludingWindows: controls)
        self.config = config
    }

    func color(at point: NSPoint, in size: NSSize) async -> NSColor? {
        guard #available(macOS 14.0, *), !Task.isCancelled,
              let full = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              !Task.isCancelled else { return nil }
        return Self.color(in: full, at: point, viewSize: size)
    }

    static func color(in image: CGImage, at point: NSPoint, viewSize: NSSize) -> NSColor? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let px = min(max(Int(floor(point.x / viewSize.width * CGFloat(image.width))), 0), image.width - 1)
        let py = min(max(Int(floor(point.y / viewSize.height * CGFloat(image.height))), 0), image.height - 1)
        // 单像素采样：边界不越界，也不会误取裁剪后 3x3 区域中的相邻像素。
        guard let pixel = image.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // NSBitmapImageRep.colorAt 会经过设备色彩空间；显式转换成 sRGB 再读取字节。
        var rgba = [UInt8](repeating: 0, count: 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { return nil }
        let alpha = CGFloat(rgba[3])
        let divisor = max(alpha, 1)
        return NSColor(srgbRed: CGFloat(rgba[0]) / divisor, green: CGFloat(rgba[1]) / divisor,
                       blue: CGFloat(rgba[2]) / divisor, alpha: alpha / 255)
    }
}

@MainActor
final class ColorPickerOverlayWindow: NSWindow {
    let overlayView: ColorPickerOverlayView
    let screenFrame: NSRect
    let displayID: CGDirectDisplayID

    init(screen: NSScreen, session: ColorPickerSession) {
        screenFrame = screen.frame
        displayID = screen.displayID
        overlayView = ColorPickerOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), session: session)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ColorPickerOverlayView: NSView {
    weak var session: ColorPickerSession?
    var cursorPoint: NSPoint?
    var color: NSColor?
    var hex = ""
    private var cursorTrackingArea: NSTrackingArea?

    let pickerCursor: NSCursor = .crosshair

    init(frame: NSRect, session: ColorPickerSession) {
        self.session = session
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() { addCursorRect(bounds, cursor: pickerCursor) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    func ensurePickerCursor() {
        pickerCursor.set()
    }

    override func cursorUpdate(with event: NSEvent) { ensurePickerCursor() }
    override func mouseMoved(with event: NSEvent) { ensurePickerCursor() }
    override func mouseEntered(with event: NSEvent) { ensurePickerCursor() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        session?.commit(at: window.convertPoint(toScreen: event.locationInWindow))
    }

    override func rightMouseDown(with event: NSEvent) { session?.cancel() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { session?.cancel(); return }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 完全透明的像素会让 WindowServer 将点击和光标命中穿透给下方应用。
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill()
        guard let cursorPoint else { return }
        // 准心也直接绘制在覆盖层上，即使系统重置或隐藏光标，取样位置仍始终可见。
        let crosshair = NSBezierPath()
        crosshair.move(to: NSPoint(x: cursorPoint.x - 7, y: cursorPoint.y))
        crosshair.line(to: NSPoint(x: cursorPoint.x + 7, y: cursorPoint.y))
        crosshair.move(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y - 7))
        crosshair.line(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y + 7))
        NSColor.white.setStroke()
        crosshair.lineWidth = 3
        crosshair.stroke()
        NSColor.black.setStroke()
        crosshair.lineWidth = 1
        crosshair.stroke()
        guard let color else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (hex as NSString).size(withAttributes: attributes)
        let size = NSSize(width: textSize.width + 38, height: max(textSize.height + 12, 28))
        var origin = NSPoint(x: cursorPoint.x + 16, y: cursorPoint.y + 16)
        if origin.x + size.width > bounds.maxX - 8 { origin.x = cursorPoint.x - size.width - 16 }
        if origin.y + size.height > bounds.maxY - 8 { origin.y = cursorPoint.y - size.height - 16 }
        origin.x = max(bounds.minX + 8, origin.x)
        origin.y = max(bounds.minY + 8, origin.y)
        let pill = NSRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        let swatch = NSBezierPath(ovalIn: NSRect(x: pill.minX + 7, y: pill.midY - 7, width: 14, height: 14))
        color.setFill()
        swatch.fill()
        NSColor.white.setStroke()
        swatch.lineWidth = 1
        swatch.stroke()
        (hex as NSString).draw(at: NSPoint(x: pill.minX + 28, y: pill.midY - textSize.height / 2),
                              withAttributes: attributes)
    }
}
