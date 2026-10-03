import AppKit

/// 顶部居中的小提示条（toast），自动消失；可选一个操作按钮。
@MainActor
final class Toast {
    private static var window: NSWindow?
    private static var timer: Timer?
    private static var actionTarget: ToastAction?

    private static let maxWidth: CGFloat = 340

    /// 仅提示
    static func show(title: String, detail: String?) {
        present(title: title, detail: detail, actionTitle: nil, action: nil)
    }

    /// 带操作按钮（如「打开」）
    static func show(title: String, detail: String?, actionTitle: String, action: @escaping () -> Void) {
        present(title: title, detail: detail, actionTitle: actionTitle, action: action)
    }

    private static func present(title: String, detail: String?, actionTitle: String?, action: (() -> Void)?) {
        dismiss()

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 2
        infoStack.addArrangedSubview(titleLabel)
        infoStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if let detail, !detail.isEmpty {
            let shown = detail.count > 60 ? String(detail.prefix(60)) + "…" : detail
            let detailLabel = NSTextField(labelWithString: shown)
            detailLabel.font = .systemFont(ofSize: 11.5)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.lineBreakMode = .byTruncatingTail
            detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            infoStack.addArrangedSubview(detailLabel)
        }

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.addArrangedSubview(infoStack)

        let hasAction = actionTitle != nil && action != nil
        if let actionTitle, let action {
            let target = ToastAction(action)
            actionTarget = target
            let button = NSButton(title: actionTitle, target: target, action: #selector(ToastAction.fire))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(button)
        }

        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        var size = container.fittingSize
        size.width = min(max(size.width, 160), maxWidth)
        let window = ToastWindow(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 5)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = !hasAction
        window.sharingType = .none
        container.frame = NSRect(origin: .zero, size: size)
        window.contentView = container
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24))
        }
        window.orderFrontRegardless()
        Self.window = window
        let duration: TimeInterval = hasAction ? 6.0 : 2.6
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            Task { @MainActor in dismiss() }
        }
    }

    static func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        actionTarget = nil
    }
}

/// 让无边框 toast 能接收按钮点击
private final class ToastWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ToastAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() {
        handler()
        Toast.dismiss()
    }
}
