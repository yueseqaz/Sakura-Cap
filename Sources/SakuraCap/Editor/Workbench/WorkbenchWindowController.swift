import AppKit
import SwiftUI

/// 裁剪面板的来源：录屏结束后自动打开，还是用户主动打开/选文件
enum TrimOrigin { case recording, manual }

/// 工作台窗口：接管方向键/空格/S/F/⌘Z 等编辑快捷键（避开输入框的 field editor）
final class WorkbenchWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// 录屏后期工作台窗口管理：同一文件去重、关窗确认、全屏联动。
/// 对外接口与旧 TrimWindowController 一致（show(url:origin:)），直接替换入口。
@MainActor
final class WorkbenchWindowController: NSObject, NSWindowDelegate {
    static let shared = WorkbenchWindowController()

    private var entries: [(window: WorkbenchWindow, model: WorkbenchViewModel)] = []
    /// 每扇窗口的观察者 token（全屏联动 + willClose），关窗时一并移除，
    /// 否则 NotificationCenter 会无限累积 block 注册。
    private var observers: [NSWindow: [NSObjectProtocol]] = [:]

    func show(url: URL, origin: TrimOrigin) {
        if let existing = entries.first(where: { $0.model.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            NSApp.activate(ignoringOtherApps: true)
            existing.window.makeKeyAndOrderFront(nil)
            existing.window.orderFrontRegardless()
            return
        }
        let model = WorkbenchViewModel(url: url)
        model.origin = origin
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
        let window = WorkbenchWindow(contentRect: NSRect(x: 0, y: 0,
                                                         width: min(1280, screen.width * 0.86),
                                                         height: min(860, screen.height * 0.88)),
                                     styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        window.title = String(format: L("剪辑 — %@"), url.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // 菜单栏应用：悬浮于其他应用之上、跟随所有空间，点别处不会被压到后面
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 远程桌面与录屏里不可见（同旧裁剪窗）
        window.sharingType = .readOnly
        window.contentView = NSHostingView(rootView: WorkbenchView(model: model))
        window.delegate = self
        model.requestClose = { [weak window] in window?.close() }
        window.center()
        window.keyHandler = { [weak self, weak model] event in
            guard let self, let model else { return false }
            return self.handleKey(event, model: model)
        }
        entries.append((window, model))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        observe(window: window)
    }

    private func observe(window: NSWindow) {
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        tokens.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                                         object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.syncFullscreen(note, isFullscreen: true) }
        })
        tokens.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                         object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.syncFullscreen(note, isFullscreen: false) }
        })
        tokens.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                         object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let closed = note.object as? NSWindow else { return }
                self?.removeEntry(for: closed)
            }
        })
        observers[window] = tokens
    }

    private func syncFullscreen(_ note: Notification, isFullscreen: Bool) {
        guard let window = note.object as? NSWindow,
              let entry = entries.first(where: { $0.window === window }) else { return }
        entry.model.isFullscreen = isFullscreen
    }

    private func removeEntry(for closed: NSWindow) {
        entries.removeAll { $0.window === closed }
        observers[closed]?.forEach(NotificationCenter.default.removeObserver)
        observers[closed] = nil
    }

    func toggleFullscreen(of model: WorkbenchViewModel) {
        guard let entry = entries.first(where: { $0.model === model }) else { return }
        entry.window.toggleFullScreen(nil)
    }

    private func handleKey(_ event: NSEvent, model: WorkbenchViewModel) -> Bool {
        // 输入框编辑中不拦截
        if let view = window(for: model)?.firstResponder as? NSTextView, view.isFieldEditor { return false }
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let key = event.charactersIgnoringModifiers ?? ""

        if command {
            switch key {
            case "z":
                if shift { model.redo() } else { model.undo() }
                return true
            default:
                return false
            }
        }
        switch key {
        case " ":
            model.togglePlay()
            return true
        case "\u{F702}": // ←
            if shift { model.seek(to: model.currentTime - 1) } else { model.stepFrames(-1) }
            return true
        case "\u{F703}": // →
            if shift { model.seek(to: model.currentTime + 1) } else { model.stepFrames(1) }
            return true
        case "s", "S":
            model.splitAtPlayhead()
            return true
        case "f", "F":
            toggleFullscreen(of: model)
            return true
        case "\u{7F}", "\u{8}": // Delete / Backspace
            guard case .clip(let id)? = model.selection else { return false }
            model.deleteClip(id)
            return true
        default:
            return false
        }
    }

    private func window(for model: WorkbenchViewModel) -> NSWindow? {
        entries.first(where: { $0.model === model })?.window
    }

    /// 点左上角关闭 / ⌘W 时先确认（程序内 close() 靠 isProgrammaticClose 跳过）
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let entry = entries.first(where: { $0.window === sender }) else { return true }
        if entry.model.isProgrammaticClose { return true }
        return entry.model.confirmDiscard()
    }
}
