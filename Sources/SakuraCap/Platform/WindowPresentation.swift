import AppKit

/// Ordinary windows stay in the normal desktop stack. Capture overlays and HUDs
/// deliberately do not use this policy.
@MainActor
enum WindowPresentation {
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    private static let menuActions = WindowMenuActions()

    static func configure(_ window: NSWindow, supportsFullScreen: Bool = false, allowsPinning: Bool = true) {
        guard !windows.contains(window) else { return }
        windows.add(window)
        window.level = .normal
        window.collectionBehavior = supportsFullScreen ? [.fullScreenPrimary] : []
        window.hidesOnDeactivate = false
        if window.styleMask.contains(.closable) { window.styleMask.insert(.miniaturizable) }
        if allowsPinning {
            window.addTitlebarAccessoryViewController(WindowPinControl(window: window))
        }
    }

    static func isPinned(_ window: NSWindow) -> Bool {
        pinControl(for: window)?.isPinned ?? false
    }

    static func setPinned(_ pinned: Bool, for window: NSWindow) {
        pinControl(for: window)?.setPinned(pinned)
    }

    static func setFullScreen(_ active: Bool, for window: NSWindow) {
        pinControl(for: window)?.setFullScreen(active)
    }

    static var openedWindows: [NSWindow] {
        windows.allObjects.filter { $0.isVisible || $0.isMiniaturized }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.windowNumber < $1.windowNumber : order == .orderedAscending
        }
    }

    static func windowsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("已打开的窗口"), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for window in openedWindows {
            let entry = NSMenuItem(title: window.title, action: #selector(WindowMenuActions.reveal(_:)), keyEquivalent: "")
            entry.target = menuActions
            entry.representedObject = window
            entry.state = window.isKeyWindow ? .on : .off
            if isPinned(window) { entry.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: L("置顶")) }
            menu.addItem(entry)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: L("没有已打开的窗口"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        item.submenu = menu
        return item
    }

    private static func pinControl(for window: NSWindow) -> WindowPinControl? {
        window.titlebarAccessoryViewControllers.compactMap { $0 as? WindowPinControl }.first
    }
}

@MainActor
private final class WindowMenuActions: NSObject {
    @objc func reveal(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class WindowPinControl: NSTitlebarAccessoryViewController {
    private weak var owner: NSWindow?
    private let button = NSButton()
    private(set) var isPinned = false
    private var isFullScreen = false

    init(window: NSWindow) {
        owner = window
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        button.frame = NSRect(x: 4, y: 2, width: 28, height: 24)
        button.identifier = .init("windowPinToggle")
        button.bezelStyle = .inline
        button.setButtonType(.toggle)
        button.isBordered = false
        button.target = self
        button.action = #selector(togglePin)
        container.addSubview(button)
        view = container
        refresh()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willEnterFullScreen), name: NSWindow.willEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(didExitFullScreen), name: NSWindow.didExitFullScreenNotification, object: window)
    }

    required init?(coder: NSCoder) { nil }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        refresh()
    }

    func setFullScreen(_ active: Bool) {
        isFullScreen = active
        refresh()
    }

    @objc private func togglePin() { setPinned(!isPinned) }
    @objc private func willEnterFullScreen() { setFullScreen(true) }
    @objc private func didExitFullScreen() { setFullScreen(false) }

    private func refresh() {
        owner?.level = isPinned && !isFullScreen ? .floating : .normal
        button.state = isPinned ? .on : .off
        button.isEnabled = !isFullScreen
        let title = isPinned ? L("取消置顶") : L("置顶")
        button.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }
}
