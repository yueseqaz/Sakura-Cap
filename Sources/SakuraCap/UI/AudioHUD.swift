import AppKit

/// 录音悬浮条：脉动红点 + 律动条 + 时间 + 暂停/停止。
/// 胶囊造型、毛玻璃、可拖动、不进入截屏/录屏画面。
@MainActor
final class AudioHUDController {
    static let shared = AudioHUDController()

    private var panel: NSPanel?

    func show(controller: AudioRecorderController) {
        hide()
        let content = AudioHUDView()
        content.onPause = { [weak controller] in controller?.togglePause() }
        content.onStop = { [weak controller] in controller?.stop() }
        content.onStateChanged = { [weak controller] in
            guard let controller else { return }
            content.apply(state: controller.state, elapsed: controller.elapsed)
        }
        // 状态与计时刷新：轻量 KVO 轮询由控制器 @Published 驱动不可直接订阅 NSView，
        // 用 0.5s 定时器与控制器自身节拍同步
        content.apply(state: .recording, elapsed: 0)
        content.scheduledRefresh { [weak controller] in
            guard let controller else { return false }
            guard controller.isBusy else { return false }
            content.apply(state: controller.state, elapsed: controller.elapsed)
            return controller.isBusy
        }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 232, height: 48)
        let panel = NSPanel(contentRect: NSRect(x: screen.midX - size.width / 2,
                                                y: screen.maxY - size.height - 12,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // 不出现在任何截屏 / 录屏里
        panel.sharingType = .none
        panel.contentView = content
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 胶囊内容视图（纯 AppKit 绘制）
final class AudioHUDView: NSView {
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?

    private let dot = NSView()
    private let timeField = NSTextField(labelWithString: "00:00")
    private var bars: [NSView] = []
    private let pauseButton = NSButton()
    private let stopButton = NSButton()
    private var refreshTimer: Timer?
    private var paused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true

        let material = NSVisualEffectView(frame: .zero)
        material.material = .hudWindow
        material.blendingMode = .withinWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        addSubview(material)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        dot.frame = NSRect(x: 16, y: 19, width: 10, height: 10)
        addSubview(dot)

        // 律动条（4 根，相位错开）
        for index in 0..<4 {
            let bar = NSView(frame: NSRect(x: 34 + CGFloat(index) * 5, y: 18, width: 3, height: 12))
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
            bar.layer?.cornerRadius = 1.5
            addSubview(bar)
            bars.append(bar)
        }

        timeField.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timeField.textColor = .white
        timeField.backgroundColor = .clear
        timeField.isBezeled = false
        timeField.isEditable = false
        timeField.frame = NSRect(x: 60, y: 14, width: 62, height: 20)
        addSubview(timeField)

        configureIconButton(pauseButton, symbol: "pause.fill", action: #selector(pauseTapped))
        pauseButton.frame = NSRect(x: 134, y: 10, width: 28, height: 28)
        configureIconButton(stopButton, symbol: "stop.fill", action: #selector(stopTapped))
        stopButton.frame = NSRect(x: 172, y: 10, width: 28, height: 28)
        stopButton.contentTintColor = .systemRed

        startPulse()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        button.contentTintColor = .white
        button.target = self
        button.action = action
        addSubview(button)
    }

    @objc private func pauseTapped() { onPause?() }
    @objc private func stopTapped() { onStop?() }

    // MARK: 动画

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(pulse, forKey: "pulse")

        for (index, bar) in bars.enumerated() {
            let bounce = CABasicAnimation(keyPath: "transform.scale.y")
            bounce.fromValue = 0.35
            bounce.toValue = 1.5
            bounce.duration = 0.5
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.beginTime = CACurrentMediaTime() + Double(index) * 0.12
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.layer?.add(bounce, forKey: "bounce")
        }
        paused = false
    }

    private func stopAnimations() {
        dot.layer?.removeAnimation(forKey: "pulse")
        bars.forEach { $0.layer?.removeAnimation(forKey: "bounce") }
        paused = true
    }

    // MARK: 状态

    var onStateChanged: (() -> Void)?

    func apply(state: AudioRecorderController.State, elapsed: TimeInterval) {
        let seconds = Int(elapsed)
        timeField.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        if state == .paused, !paused {
            stopAnimations()
            pauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            dot.layer?.backgroundColor = NSColor.systemYellow.cgColor
            bars.forEach { $0.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.9).cgColor }
        } else if state == .recording, paused {
            startPulse()
            pauseButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            bars.forEach { $0.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor }
        }
    }

    /// 0.5s 刷新；回调返回 false 时停止
    func scheduledRefresh(_ tick: @escaping () -> Bool) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !tick() {
                    self.refreshTimer?.invalidate()
                    self.refreshTimer = nil
                }
            }
        }
    }
}
