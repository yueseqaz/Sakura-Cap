import AppKit
import Combine

/// Shows the measured incoming video frame rate without adding it to the recording.
@MainActor
final class FPSOverlay {
    private let controller: RecordingController
    private var window: NSWindow?
    private let label = NSTextField(labelWithString: "--")
    private var subscriptions = Set<AnyCancellable>()

    init(controller: RecordingController) {
        self.controller = controller
        controller.$state.combineLatest(controller.$measuredFPS, AppSettings.shared.$showFPSOverlay)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &subscriptions)
    }

    private func sync() {
        guard AppSettings.shared.showFPSOverlay, controller.state == .recording,
              let target = RecordingTarget.rect() else {
            window?.orderOut(nil)
            return
        }
        let window = window ?? makeWindow()
        self.window = window
        label.stringValue = controller.measuredFPS > 0 ? "\(controller.measuredFPS)" : "--"
        window.setFrameOrigin(NSPoint(x: target.maxX - window.frame.width - 16,
                                      y: target.maxY - window.frame.height - 16))
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 52, height: 38),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        // This is intentionally a capture-visible overlay when enabled.
        window.sharingType = .readOnly
        label.frame = NSRect(x: 0, y: 0, width: 52, height: 38)
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        label.textColor = NSColor.systemGreen.withAlphaComponent(0.86)
        window.contentView = label
        return window
    }
}
