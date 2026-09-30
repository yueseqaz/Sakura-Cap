import AppKit
import QuartzCore

/// 点击标记覆盖层：小尺寸 borderless 窗口，只盖住点击点附近。
/// 不可点击穿透失败——ignoresMouseEvents = true 保证不拦截任何鼠标事件；
/// sharingType 保持 .shared，保证被 ScreenCaptureKit 录进视频；
/// canJoinAllSpaces + fullScreenAuxiliary 保证全屏应用之上也能显示。
final class IndicatorWindow: NSWindow {
    private var onFinished: ((IndicatorWindow) -> Void)?
    private let content: IndicatorContentView

    init(atCGPoint point: CGPoint, onScreen screen: NSScreen, onFinished: @escaping (IndicatorWindow) -> Void) {
        let settings = AppSettings.shared
        let side = max(64, settings.indicatorSize * 2.4)
        let appKitPoint = ScreenCoordinate.appKitPoint(fromCG: point)
        let frame = NSRect(x: appKitPoint.x - side / 2,
                           y: appKitPoint.y - side / 2,
                           width: side,
                           height: side)
        content = IndicatorContentView(frame: NSRect(origin: .zero, size: frame.size))
        self.onFinished = onFinished
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver + 1
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // 关键：.none 会被 ScreenCaptureKit 排除出录制。SCK 只需“可读”权限，
        // .readOnly（NSWindow 默认值）即可被录进视频；新 SDK 已移除 .shared。
        sharingType = .readOnly
        hasShadow = false
        contentView = content
    }

    func play() {
        // 关键：无边框窗口必须显式上屏（否则永远不可见）；下一 runloop 再起动画，
        // 确保窗口上屏后 backing layer 就绪
        orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            self?.content.play { [weak self] in
                guard let self else { return }
                self.orderOut(nil)
                self.onFinished?(self)
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 动画绘制：指向点击点的箭头，时长来自设置
final class IndicatorContentView: NSView {
    private var completion: (() -> Void)?
    private var started = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func play(completion: @escaping () -> Void) {
        guard !started else { return }
        started = true
        self.completion = completion
        guard let layer else {
            completion()
            return
        }
        let settings = AppSettings.shared
        let color = NSColor(settings.indicatorColor).withAlphaComponent(0.95).cgColor
        let duration = max(0.2, settings.indicatorDuration)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.completion?()
        }

        let arrow = CAShapeLayer()
        arrow.path = Self.arrowPath(bounds: bounds)
        arrow.fillColor = color
        layer.addSublayer(arrow)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        arrow.add(group, forKey: "fade")
        arrow.opacity = 0

        CATransaction.commit()
    }

    /// 尖端恰好位于视图中心（即点击点）、指向右下方的箭头
    private static func arrowPath(bounds: CGRect) -> CGPath {
        let length = min(bounds.width, bounds.height) * 0.58
        let angle = CGFloat.pi / 4
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // 使尖端 (u=0.34) 落在中心点
        let origin = CGPoint(x: center.x - cos(angle) * length * 0.34,
                             y: center.y - sin(angle) * length * 0.34)
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            let x = u * cos(angle) - v * sin(angle)
            let y = u * sin(angle) + v * cos(angle)
            return CGPoint(x: origin.x + x * length, y: origin.y + y * length)
        }
        let path = CGMutablePath()
        path.move(to: point(-0.52, 0.20))
        path.addLine(to: point(0.34, 0.0))
        path.addLine(to: point(-0.52, -0.20))
        path.addLine(to: point(-0.30, 0.0))
        path.closeSubpath()
        return path
    }
}
