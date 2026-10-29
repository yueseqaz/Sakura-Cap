import AppKit

func L(_ key: String) -> String { key }

@main
@MainActor
enum WindowPresentationChecks {
    private static var checks = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await verifyWindows()
            verifyAlerts()
            print("Window presentation regressions passed: \(checks) assertions")
            exit(0)
        }
        app.run()
    }

    private static func makeWindow(_ title: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 280),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        return window
    }

    private static func verifyWindows() async {
        let window = makeWindow("Test document")
        defer { window.close() }
        WindowPresentation.configure(window, supportsFullScreen: true)
        WindowPresentation.configure(window, supportsFullScreen: true)
        check(window.level == .normal, "Documents must start at the normal level")
        check(window.collectionBehavior == [.fullScreenPrimary], "Documents must not join all Spaces or other apps' fullscreen")
        check(window.styleMask.contains(.miniaturizable), "Documents must allow minimization")
        check(window.titlebarAccessoryViewControllers.count == 1, "Repeated registration must not duplicate pin controls")
        let accessory = window.titlebarAccessoryViewControllers[0]
        let pin = accessory.view.subviews.compactMap { $0 as? NSButton }.first!
        check(pin.identifier?.rawValue == "windowPinToggle" && pin.state == .off, "Pinning must be explicit and off by default")
        pin.performClick(nil)
        check(WindowPresentation.isPinned(window) && window.level == .floating, "Pin button must enable floating")
        check(!window.collectionBehavior.contains(.canJoinAllSpaces), "Pinning must not silently join every Space")
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
        check(window.level == .normal && !pin.isEnabled, "Fullscreen must suspend floating")
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        check(window.level == .floating && pin.isEnabled, "Fullscreen exit must restore explicit pinning")
        WindowPresentation.setFullScreen(true, for: window)
        WindowPresentation.setFullScreen(false, for: window)
        check(window.level == .floating, "Failed fullscreen entry must restore explicit pinning")
        pin.performClick(nil)
        check(!WindowPresentation.isPinned(window) && window.level == .normal, "Unpinning must restore the normal level")
        window.makeKeyAndOrderFront(nil)
        check(WindowPresentation.openedWindows.contains(window), "Open documents must be recoverable from the menu")
        window.miniaturize(nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        check(window.isMiniaturized && WindowPresentation.openedWindows.contains(window), "Minimized documents must remain recoverable")
        let menu = WindowPresentation.windowsMenuItem().submenu!
        let index = menu.items.firstIndex { ($0.representedObject as? NSWindow) === window }!
        menu.performActionForItem(at: index)
        try? await Task.sleep(nanoseconds: 300_000_000)
        check(!window.isMiniaturized && window.isVisible && window.level == .normal, "Window menu must restore without pinning")
        window.close()
        check(!WindowPresentation.openedWindows.contains(window), "Closed retained documents must not appear in the menu")
        window.makeKeyAndOrderFront(nil)
        check(WindowPresentation.openedWindows.contains(window), "Reopening retained documents must restore their menu entry")

        let overlay = makeWindow("Capture overlay")
        overlay.level = .screenSaver
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.orderFront(nil)
        defer { overlay.close() }
        check(!WindowPresentation.openedWindows.contains(overlay), "Capture overlays must not be registered as documents")
        check(overlay.level == .screenSaver, "The document policy must not change capture overlays")

        let progress = makeWindow("Background progress")
        defer { progress.close() }
        WindowPresentation.configure(progress, allowsPinning: false)
        check(progress.level == .normal && progress.titlebarAccessoryViewControllers.isEmpty,
              "Background progress must not float or require a pin control")
    }

    private static func verifyAlerts() {
        let owner = makeWindow("Alert owner")
        WindowPresentation.configure(owner)
        owner.makeKeyAndOrderFront(nil)
        defer { owner.close() }
        for pinned in [false, true] {
            WindowPresentation.setPinned(pinned, for: owner)
            let alert = NSAlert()
            alert.messageText = "Document confirmation"
            alert.addButton(withTitle: "OK")
            dismiss(alert) {
                check(alert.window.sheetParent === owner, "Document confirmations must be attached sheets")
                check(alert.window.level < .screenSaver, "Document sheets must never use the capture-overlay level")
            }
            check(runModalAlert(alert, for: owner) == .alertFirstButtonReturn, "Sheet must preserve synchronous response semantics")
            check(owner.level == (pinned ? .floating : .normal), "Closing a sheet must not alter the owner's pin setting")
        }
        owner.orderOut(nil)
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        let originalLevel = alert.window.level
        dismiss(alert) {
            check(alert.window.sheetParent == nil && alert.window.level == .modalPanel, "Standalone alerts must use an ordinary modal level")
        }
        check(runModalAlert(alert, for: owner) == .alertFirstButtonReturn, "Standalone response must be preserved")
        check(alert.window.level == originalLevel, "Standalone alert level must be restored")

        let overlay = makeWindow("Active capture")
        overlay.level = .screenSaver + 2
        overlay.orderFront(nil)
        defer { overlay.close() }
        let captureAlert = NSAlert()
        captureAlert.addButton(withTitle: "OK")
        let captureLevel = captureAlert.window.level
        dismiss(captureAlert) {
            check(captureAlert.window.level > overlay.level, "An overlay alert must be above its own overlay (alert \(captureAlert.window.level.rawValue), overlay \(overlay.level.rawValue))")
        }
        check(runModalAlert(captureAlert, for: overlay) == .alertFirstButtonReturn, "Capture alert must remain operable")
        check(captureAlert.window.level == captureLevel, "Temporary capture elevation must be restored")
    }

    private static func dismiss(_ alert: NSAlert, inspect: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated {
                inspect()
                alert.buttons[0].performClick(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        RunLoop.main.add(timer, forMode: .common)
    }
}
