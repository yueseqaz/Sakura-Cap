import AppKit
import AVKit
import SwiftUI

@main
@MainActor
enum ChatAppearanceChecks {
    private static var checks = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private static func settle(_ window: NSWindow) async {
        for _ in 0..<4 {
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await verifySurfaces()
            await verifyFullscreen()
            await verifyStreamingFollow()
            await verifyChat()
            let result = "Chat / appearance / fullscreen regressions passed: \(checks) assertions"
            if let completion = ProcessInfo.processInfo.environment["SAKURA_UI_TEST_COMPLETION"] {
                try! result.write(toFile: completion, atomically: true, encoding: .utf8)
            }
            print(result)
            exit(0)
        }
        app.run()
        preconditionFailure("AppKit exited before regression checks completed")
    }

    private static func pixel(_ view: NSView) -> NSColor {
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
    }

    private static func verifySurfaces() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let header = WorkbenchHeaderColumn(frame: NSRect(x: 0, y: 0, width: 132, height: 180))
        let surface = NSView(frame: NSRect(x: 150, y: 0, width: 120, height: 180))
        SettingsAppearance.applySurface(to: surface, fill: SettingsAppearance.sidebar, radius: 6)
        window.contentView!.addSubview(header)
        window.contentView!.addSubview(surface)
        window.orderFront(nil)

        // Create under the opposite application appearance, then switch the window
        // repeatedly. Colors must be resolved in the view, not frozen at init.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp.appearance = nil }
        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            window.appearance = NSAppearance(named: name)
            header.needsDisplay = true
            await settle(window)
            let expected: CGFloat = name == .aqua ? 0.97 : 0.095
            for view in [header, surface] {
                let color = pixel(view)
                check(abs(color.redComponent - expected) < 0.04, "Surface must match its window's \(name) appearance: \(color)")
            }
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                let text = SettingsAppearance.secondary.usingColorSpace(.sRGB)!
                let background = SettingsAppearance.sidebar.usingColorSpace(.sRGB)!
                check(contrast(text, background) >= 4.5, "Small hint text must meet 4.5:1 contrast in \(name)")
            }
        }
    }

    private static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return linear(color.redComponent) * 0.2126 + linear(color.greenComponent) * 0.7152
                + linear(color.blueComponent) * 0.0722
        }
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func verifyFullscreen() async {
        let model = WorkbenchViewModel(url: URL(fileURLWithPath: "/nonexistent/fullscreen-test.mp4"))
        let host = NSHostingView(rootView: WorkbenchView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = host
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        window.orderFront(nil)
        await settle(window)
        let player = descendants(host).compactMap { $0 as? AVPlayerView }.first!
        let coordinator = player.delegate as! PlayerView.Coordinator
        check(descendants(host).contains { $0 is WorkbenchTimelineContainer }, "Normal editing must include the timeline")
        check(player.bounds.width < host.bounds.width - 200, "Normal editing must reserve the properties panel")

        model.editingAnnotationID = UUID()
        coordinator.playerViewWillEnterFullScreen(player)
        check(model.editingAnnotationID == nil, "Fullscreen must commit and close an active annotation editor")
        check(window.level == .normal, "Editor must not float above AVKit's fullscreen movie")
        check(!window.collectionBehavior.contains(.canJoinAllSpaces)
              && !window.collectionBehavior.contains(.fullScreenAuxiliary),
              "Editor must not follow AVKit into its fullscreen Space")
        coordinator.playerViewWillEnterFullScreen(player)
        coordinator.playerViewDidEnterFullScreen(player)
        check(!window.isVisible, "Native fullscreen must hide the editor window, including on other displays")
        var restored = false
        coordinator.playerView(player, restoreUserInterfaceForFullScreenExitWithCompletionHandler: { restored = $0 })
        check(restored && window.isVisible && window.level == .normal,
              "AVKit exit must restore its destination before restoring floating presentation")
        coordinator.playerViewDidExitFullScreen(player)
        check(window.level == .floating
              && window.collectionBehavior == [.canJoinAllSpaces, .fullScreenPrimary],
              "Leaving AVKit fullscreen must restore the original window presentation")

        model.isFullscreen = true
        await settle(window)
        check(!descendants(host).contains { $0 is WorkbenchTimelineContainer }, "Window fullscreen must hide the timeline")
        check(descendants(host).contains { $0 === player }, "Fullscreen layout must retain the same AVPlayerView")
        check(abs(player.bounds.width - host.bounds.width) < 2
              && abs(player.bounds.height - host.bounds.height) < 2,
              "Fullscreen preview must fill the window without edit toolbar, properties or margins")
        snapshot(host, name: "workbench-fullscreen")
        model.isFullscreen = false
        await settle(window)
        check(descendants(host).contains { $0 is WorkbenchTimelineContainer }, "Exiting fullscreen must restore the timeline")
        check(player.bounds.width < host.bounds.width - 200, "Exiting fullscreen must restore the properties panel")
        coordinator.playerViewWillEnterFullScreen(player)
        coordinator.restoreEditorWindow()
        coordinator.restoreEditorWindow()
        check(window.level == .floating && window.collectionBehavior.contains(.canJoinAllSpaces),
              "Dismantling the player must safely restore its editor window")
    }

    private final class FlippedDocument: NSView {
        override var isFlipped: Bool { true }
    }

    private static func verifyStreamingFollow() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
        let state = ChatScrollState()
        let tracking = ChatScrollTracking.TrackingView(frame: .zero)
        tracking.state = state
        tracking.onFollowChange = { state.followsLatestMessage = $0 }
        document.addSubview(tracking)
        scroll.documentView = document
        window.contentView!.addSubview(scroll)
        window.orderFront(nil)
        await settle(window)
        check(abs(scroll.documentVisibleRect.maxY - 1000) < 2, "Initial layout must follow the latest message")
        document.setFrameSize(NSSize(width: 400, height: 1400))
        await settle(window)
        check(abs(scroll.documentVisibleRect.maxY - 1400) < 2, "Streaming content growth must follow the bottom")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        document.setFrameSize(NSSize(width: 400, height: 1800))
        await settle(window)
        check(!state.followsLatestMessage && abs(scroll.documentVisibleRect.minY - 180) < 2,
              "Streaming growth must preserve manual history position")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1500))
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        document.setFrameSize(NSSize(width: 400, height: 2200))
        await settle(window)
        check(state.followsLatestMessage && abs(scroll.documentVisibleRect.maxY - 2200) < 2,
              "Returning to the bottom must resume following subsequent output")
    }

    private static func snapshot(_ view: NSView, name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SAKURA_UI_SNAPSHOTS"] else { return }
        try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to:
            URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }

    private static func verifyChat() async {
        let markdown = "# Heading\nA paragraph with **bold**, `code`, and a [link](https://example.com).\n\n"
            + String(repeating: "Wrapped text that must retain its measured height while scrolling. ", count: 12)
            + "\n\n```swift\nlet value = 42\n```\n"
        let messages = (0..<40).map { index in
            AIChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant,
                          text: index.isMultiple(of: 2) ? "Question \(index)" : markdown)
        }
        let model = AIChatViewModel(session: AIChatSession(messages: messages))
        let host = NSHostingView(rootView: AIChatView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        await settle(window)
        let tracking = descendants(host).compactMap { $0 as? ChatScrollTracking.TrackingView }.first!
        guard let scroll = tracking.enclosingScrollView, let document = scroll.documentView else {
            preconditionFailure("Follow-mode observer must be attached to the transcript scroll view")
        }
        check(document.bounds.height > 2000 && document.bounds.height < 100_000,
              "Long mixed Markdown history must have a finite usable height: \(document.bounds)")
        check(document.isFlipped, "Transcript coordinates must be top-down")
        check(abs(document.bounds.maxY - scroll.documentVisibleRect.maxY) < 60,
              "Opening a history must show the latest message: \(scroll.documentVisibleRect) / \(document.bounds)")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: name)
            await settle(window)
            snapshot(host, name: "chat-\(name.rawValue)")
        }

        for fraction in [0.75, 0.25, 0.6] {
            let target = document.bounds.height * fraction
            scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
            scroll.reflectScrolledClipView(scroll.contentView)
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
            await settle(window)
            let origin = scroll.documentVisibleRect.minY
            model.input += "Unrelated refresh "
            await settle(window)
            check(abs(scroll.documentVisibleRect.minY - origin) < 2,
                  "Refreshing chat while reading must not jump to the first message")
        }

        // An attachment increments the same scroll stamp used by streaming.
        // It must not pull readers away from an older message.
        let origin = scroll.documentVisibleRect.minY
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        model.attach(image: bitmap.cgImage!)
        defer {
            for name in model.stagedImages {
                try? FileManager.default.removeItem(at: AIChatStore.shared.directory
                    .appendingPathComponent("images").appendingPathComponent(name))
            }
        }
        await settle(window)
        check(abs(scroll.documentVisibleRect.minY - origin) < 2,
              "A new scroll stamp must not override manual history scrolling")

        var following: Bool?
        tracking.onFollowChange = { following = $0 }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        check(following == true, "User returning to the bottom must resume follow mode")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        check(following == false, "User scrolling up must pause follow mode")

        let textView = descendants(host).compactMap { $0 as? MarkdownTextView.AutoHeightTextView }.first!
        let narrow = textView.contentSize(for: 240)
        let wide = textView.contentSize(for: 460)
        check(narrow.height > wide.height, "Markdown must measure height against the proposed width")
        textView.setSelectedRange(NSRange(location: 3, length: 8))
        model.input += "Selection refresh"
        await settle(window)
        check(textView.selectedRange() == NSRange(location: 3, length: 8),
              "Unchanged Markdown updates must preserve selection")
    }
}
