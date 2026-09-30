import AppKit
import SwiftUI

/// 按键显示引擎：录制期间收到按键 → 在「录制区域左下角」浮出按键文本，约 1 秒后淡出。
/// 窗口 sharingType = .readOnly（可被 ScreenCaptureKit 录进视频，与点击指示同理）。
@MainActor
final class KeyDisplay: ObservableObject {
    static let shared = KeyDisplay()

    @Published private(set) var isMonitoring = false
    @Published private(set) var permissionDenied = false

    private let monitor = KeyboardMonitor()
    private var window: KeyDisplayWindow?
    private var fadeTimer: Timer?
    private var capturing = false

    private init() {
        monitor.onKey = { [weak self] label in self?.handle(label) }
    }

    /// 启动监听（面板打开开关或开始录制时调用）。返回 false = 缺输入监控权限。
    @discardableResult
    func start() -> Bool {
        permissionDenied = false
        // CGEvent.tapCreate 无权限时也可能返回非 nil 但收不到事件，故先用 preflight 判定
        if !PermissionCenter.inputMonitoringGranted() {
            PermissionCenter.requestInputMonitoring()
        }
        let granted = PermissionCenter.inputMonitoringGranted()
        let ok = granted && monitor.start()
        isMonitoring = ok
        permissionDenied = !ok
        if !ok {
            Log.indicator.error("按键监听不可用：缺少「输入监控」权限（kTCCServiceListenEvent）")
        }
        return ok
    }

    func stop() {
        monitor.stop()
        isMonitoring = false
        fadeTimer?.invalidate()
        fadeTimer = nil
        window?.orderOut(nil)
    }

    func beginCapture() {
        capturing = true
        start()
    }

    func endCapture() {
        capturing = false
        fadeTimer?.invalidate()
        fadeTimer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func handle(_ label: String) {
        guard capturing, isMonitoring, !label.isEmpty, AppSettings.shared.keyDisplayEnabled else { return }
        show(label)
    }

    private func show(_ label: String) {
        guard let rect = Self.targetRect() else { return }
        let size = KeyDisplayView.size(for: label)
        let window = self.window ?? KeyDisplayWindow(size: size)
        self.window = window
        let inset: CGFloat = 24
        window.setFrame(NSRect(x: rect.minX + inset, y: rect.minY + inset,
                               width: size.width, height: size.height), display: true)
        window.update(label: label)
        window.alphaValue = 1
        window.orderFrontRegardless()
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fadeOut() }
        }
    }

    private func fadeOut() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.window?.orderOut(nil) }
        }
    }

    /// 目标区域：全屏模式取所录屏幕；区域模式取选区内。按键窗口落在其左下角。
    private static func targetRect() -> NSRect? {
        let settings = AppSettings.shared
        if settings.captureMode == .region, let region = settings.lastRegion,
           let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }) {
            let local = ScreenCoordinate.appKitLocalRect(fromSCKRect: region.sckRect, in: screen)
            return NSRect(x: screen.frame.minX + local.minX,
                          y: screen.frame.minY + local.minY,
                          width: local.width, height: local.height)
        }
        let screen = NSScreen.screens.first { $0.displayID == settings.selectedDisplayID }
            ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.frame
    }
}

/// 按键覆盖层窗口：不可点击穿透、置顶、可被录制
final class KeyDisplayWindow: NSWindow {
    private let displayView: KeyDisplayView

    init(size: NSSize) {
        displayView = KeyDisplayView(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver + 1
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly // 与点击指示同理：可被 SCK 录进视频
        hasShadow = false
        contentView = displayView
        alphaValue = 0
    }

    func update(label: String) {
        displayView.label = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 绘制：半透明深色圆角框 + 白色按键文本
final class KeyDisplayView: NSView {
    var label: String = "" { didSet { needsDisplay = true } }

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]

    static func size(for label: String) -> NSSize {
        let textSize = NSAttributedString(string: label, attributes: textAttributes).size()
        return NSSize(width: ceil(textSize.width) + 40, height: ceil(textSize.height) + 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.62).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = NSAttributedString(string: label, attributes: Self.textAttributes)
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}
