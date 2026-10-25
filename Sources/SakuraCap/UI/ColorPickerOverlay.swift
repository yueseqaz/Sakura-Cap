import AppKit
import ScreenCaptureKit

/// 全局取色器：自绘取色会话——画笔形光标 + 跟随光标的小色块（实时颜色 + HEX），
/// 点击提交、Esc 退出。轮询 NSEvent.mouseLocation（无需输入监控权限），
/// 颜色用 ScreenCaptureKit 采样并排除自己的覆盖层（约 10fps 节流）。
@MainActor
final class ColorPickerSession: NSObject {
    static let shared = ColorPickerSession()

    private var windows: [ColorPickerOverlayWindow] = []
    private var timer: Timer?
    private var captures: [CGDirectDisplayID: ScreenCapturer] = [:]
    private var sampling = false
    private var lastSampleAt = Date.distantPast
    private var currentColor: NSColor?
    private var currentHex = ""

    private static let pollInterval: TimeInterval = 1.0 / 20.0
    private static let sampleInterval: TimeInterval = 0.1

    func start() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = ColorPickerOverlayWindow(screen: screen, session: self)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKey()

        Toast.show(title: L("点击屏幕任意位置取色"), detail: L("按 Esc 取消"))

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // 预构建各屏采集器（排除自己的覆盖层）；未就绪前色块先跟随不显色
        Task { @MainActor in
            let excludeIDs = Set(self.windows.compactMap { $0.windowNumber })
            for screen in NSScreen.screens {
                let displayID = screen.displayID
                guard let capturer = await ScreenCapturer(displayID: displayID, excludingWindowNumbers: excludeIDs) else { continue }
                self.captures[displayID] = capturer
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        captures.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        currentColor = nil
        currentHex = ""
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        for window in windows where window.screen?.frame.contains(mouse) != true {
            window.overlayView.color = nil
            window.overlayView.needsDisplay = true
        }
        guard let (window, local) = windowAndLocalPoint(at: mouse) else { return }
        window.overlayView.cursorPoint = local
        window.overlayView.color = currentColor
        window.overlayView.hex = currentHex
        window.overlayView.needsDisplay = true

        let now = Date()
        guard !sampling, now.timeIntervalSince(lastSampleAt) >= Self.sampleInterval,
              let displayID = window.screen?.displayID, let capturer = captures[displayID] else { return }
        sampling = true
        lastSampleAt = now
        Task { @MainActor in
            defer { sampling = false }
            // AppKit 局部点（左下原点）→ 图像像素（SCK 左上原点）
            guard let screen = window.screen else { return }
            let (scaleX, scaleY) = DisplayPixelMetrics.scale(displayID)
            let px = Int((local.x * scaleX).rounded())
            let py = Int(((screen.frame.height - local.y) * scaleY).rounded())
            if let color = await capturer.colorAt(px: px, py: py) {
                self.currentColor = color
                self.currentHex = Self.hex(of: color)
            }
        }
    }

    private func windowAndLocalPoint(at global: NSPoint) -> (ColorPickerOverlayWindow, NSPoint)? {
        for window in windows {
            guard let frame = window.screen?.frame, frame.contains(global) else { continue }
            return (window, NSPoint(x: global.x - frame.minX, y: global.y - frame.minY))
        }
        return nil
    }

    /// 点击提交：在点击点做一次精确采样后复制
    fileprivate func commit(at global: NSPoint) {
        let mouse = global
        guard let (window, local) = windowAndLocalPoint(at: mouse) else { stop(); return }
        guard let displayID = window.screen?.displayID, let capturer = captures[displayID] else {
            finish(with: currentHex); return
        }
        guard let screen = window.screen else { stop(); return }
        let (scaleX, scaleY) = DisplayPixelMetrics.scale(displayID)
        let px = Int((local.x * scaleX).rounded())
        let py = Int(((screen.frame.height - local.y) * scaleY).rounded())
        Task { @MainActor in
            let hex = await capturer.colorAt(px: px, py: py).map { Self.hex(of: $0) } ?? self.currentHex
            self.finish(with: hex)
        }
    }

    fileprivate func cancel() { stop() }

    private func finish(with hex: String) {
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

/// 单屏采集器：整屏采样后按像素取色（排除取色覆盖层自身）
@MainActor
final class ScreenCapturer {
    private let filter: SCContentFilter
    private let config: SCStreamConfiguration
    private let scaleX: CGFloat
    private let scaleY: CGFloat
    private var busy = false

    init?(displayID: CGDirectDisplayID, excludingWindowNumbers: Set<Int>) async {
        guard #available(macOS 14.0, *) else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let controls = content.windows.filter { excludingWindowNumbers.contains(Int($0.windowID)) }
        let pixels = DisplayPixelMetrics.size(displayID)
        let (sx, sy) = DisplayPixelMetrics.scale(displayID)
        let config = SCStreamConfiguration()
        config.width = pixels.width
        config.height = pixels.height
        config.showsCursor = false
        config.captureResolution = .best
        self.filter = SCContentFilter(display: display, excludingWindows: controls)
        self.config = config
        self.scaleX = sx
        self.scaleY = sy
    }

    /// 取 (px, py) 处 3×3 像素均值颜色
    func colorAt(px: Int, py: Int) async -> NSColor? {
        guard !busy, #available(macOS 14.0, *) else { return nil }
        busy = true
        defer { busy = false }
        guard let full = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return nil
        }
        let rect = CGRect(x: px - 1, y: py - 1, width: 3, height: 3)
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard rect.width > 0, rect.height > 0, let cropped = full.cropping(to: rect) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cropped)
        guard let color = rep.colorAt(x: 1, y: 1) ?? rep.colorAt(x: 0, y: 0) else { return nil }
        return color
    }
}

/// 取色覆盖层：全屏透明、接收点击、画笔光标，绘制跟随光标的小色块
@MainActor
final class ColorPickerOverlayWindow: NSWindow {
    let overlayView: ColorPickerOverlayView

    init(screen: NSScreen, session: ColorPickerSession) {
        overlayView = ColorPickerOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), session: session)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly
        hasShadow = false
        contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
}

final class ColorPickerOverlayView: NSView {
    weak var session: ColorPickerSession?
    var cursorPoint: NSPoint = .zero
    var color: NSColor?
    var hex: String = ""

    init(frame: NSRect, session: ColorPickerSession) {
        self.session = session
        super.init(frame: frame)
        // 自定义「小画笔」光标：SF Symbol eyedropper 渲染成光标图
        if let base = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .medium)) {
            let size = NSSize(width: 20, height: 20)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = 1.5
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
                shadow.set()
                base.draw(in: rect)
                return true
            }
            cursor = NSCursor(image: image, hotSpot: NSPoint(x: 3, y: 16))
        } else {
            cursor = .crosshair
        }
    }

    required init?(coder: NSCoder) { nil }

    private var cursor: NSCursor? { didSet { if let cursor { cursor.push() } } }
    override func resetCursorRects() { if let cursor { addCursorRect(bounds, cursor: cursor) } }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        session?.commit(at: NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        session?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { session?.cancel(); return }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cursorColor = color else { return }
        let point = cursorPoint
        // 色块：小圆点（描白边）+ HEX 药丸，偏移在光标右下，不挡住取样点
        let swatchRect = NSRect(x: point.x + 14, y: point.y + 14, width: 14, height: 14)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(ovalIn: swatchRect.insetBy(dx: -1.5, dy: -1.5))
        ring.lineWidth = 1.5
        ring.stroke()
        cursorColor.setFill()
        NSBezierPath(ovalIn: swatchRect).fill()

        let label = hex
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let pillRect = NSRect(x: swatchRect.maxX + 6, y: point.y + 13,
                              width: textSize.width + 12, height: textSize.height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()
        (label as NSString).draw(at: NSPoint(x: pillRect.minX + 6, y: pillRect.minY + 4),
                                 withAttributes: attributes)
    }
}
