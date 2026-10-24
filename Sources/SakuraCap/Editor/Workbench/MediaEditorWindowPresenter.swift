import AppKit
import SwiftUI

// MARK: - 统一呈现层

/// 快捷键接管型编辑窗口：空格/S/Delete/⌘Z 等编辑快捷键由 keyHandler 处理（输入框的 field editor 除外）。
final class KeyHandlingWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// 媒体编辑窗口的统一呈现层：同一文件去重（重开复用原窗、状态保留）、悬浮 + 跟随所有空间、
/// 关窗前确认丢弃、willClose / 全屏观察者随窗口关闭一并移除。
/// 视频工作台（WorkbenchView）与音频编辑器（AudioEditorView）共用，只是 Kind 配置不同。
@MainActor
final class MediaEditorWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = MediaEditorWindowPresenter()

    enum Kind {
        case workbench
        case audioEditor

        var titleFormat: String { self == .workbench ? L("剪辑 — %@") : L("音频编辑 — %@") }

        func contentSize(screen: NSRect) -> NSSize {
            switch self {
            case .workbench:
                return NSSize(width: min(1280, screen.width * 0.86), height: min(860, screen.height * 0.88))
            case .audioEditor:
                return NSSize(width: min(640, screen.width * 0.46), height: min(460, screen.height * 0.56))
            }
        }

        var styleMask: NSWindow.StyleMask {
            switch self {
            case .workbench: return [.titled, .closable, .resizable, .fullSizeContentView]
            case .audioEditor: return [.titled, .closable, .resizable]
            }
        }

        var minSize: NSSize? {
            switch self {
            case .workbench: return nil
            case .audioEditor: return NSSize(width: 540, height: 400)
            }
        }

        /// 全屏联动（isFullscreen 驱动工作台 HUD）只有工作台需要
        var observesFullscreen: Bool { self == .workbench }

        func makeContentView(model: WorkbenchViewModel) -> NSView {
            switch self {
            case .workbench: return NSHostingView(rootView: WorkbenchView(model: model))
            case .audioEditor: return NSHostingView(rootView: AudioEditorView(model: model))
            }
        }
    }

    private var entries: [(window: KeyHandlingWindow, model: WorkbenchViewModel, kind: Kind)] = []
    /// 每扇窗口的观察者 token（willClose + 可选的全屏联动），关窗时一并移除，
    /// 否则 NotificationCenter 会无限累积 block 注册。
    private var observers: [NSWindow: [NSObjectProtocol]] = [:]

    func show(url: URL, origin: TrimOrigin, kind: Kind) {
        if let existing = entries.first(where: { $0.model.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            NSApp.activate(ignoringOtherApps: true)
            existing.window.makeKeyAndOrderFront(nil)
            existing.window.orderFrontRegardless()
            return
        }
        let model = WorkbenchViewModel(url: url)
        model.origin = origin
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
        let window = KeyHandlingWindow(contentRect: NSRect(origin: .zero, size: kind.contentSize(screen: screen)),
                                       styleMask: kind.styleMask,
                                       backing: .buffered, defer: false)
        window.title = String(format: kind.titleFormat, url.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // 菜单栏应用：悬浮于其他应用之上、跟随所有空间，点别处不会被压到后面
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 远程桌面与录屏里不可见
        window.sharingType = .readOnly
        if let minSize = kind.minSize { window.minSize = minSize }
        window.contentView = kind.makeContentView(model: model)
        window.delegate = self
        model.requestClose = { [weak window] in window?.close() }
        window.center()
        window.keyHandler = { [weak self] event in
            guard let self else { return false }
            return self.handleKey(event, model: model, kind: kind)
        }
        entries.append((window, model, kind))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        observe(window: window, kind: kind)
    }

    private func observe(window: NSWindow, kind: Kind) {
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        if kind.observesFullscreen {
            tokens.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                                             object: window, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.syncFullscreen(note, isFullscreen: true) }
            })
            tokens.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                             object: window, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.syncFullscreen(note, isFullscreen: false) }
            })
        }
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

    // MARK: - 全屏与关窗

    func toggleFullscreen(of model: WorkbenchViewModel) {
        guard let entry = entries.first(where: { $0.model === model }) else { return }
        entry.window.toggleFullScreen(nil)
    }

    /// 点左上角关闭 / ⌘W 时先确认（程序内 close() 靠 isProgrammaticClose 跳过）
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let entry = entries.first(where: { $0.window === sender }) else { return true }
        if entry.model.isProgrammaticClose { return true }
        return entry.model.confirmDiscard()
    }

    // MARK: - 快捷键

    private func handleKey(_ event: NSEvent, model: WorkbenchViewModel, kind: Kind) -> Bool {
        // 输入框编辑中不拦截
        if let view = NSApp.keyWindow?.firstResponder as? NSTextView, view.isFieldEditor { return false }
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
        case "\u{F702}": // ←（工作台逐帧步进会顺手暂停播放，音频保持 seek 语义）
            if kind == .workbench {
                if shift { model.seek(to: model.currentTime - 1) } else { model.stepFrames(-1) }
            } else {
                model.seek(to: model.currentTime - (shift ? 1 : 1 / 30.0))
            }
            return true
        case "\u{F703}": // →
            if kind == .workbench {
                if shift { model.seek(to: model.currentTime + 1) } else { model.stepFrames(1) }
            } else {
                model.seek(to: model.currentTime + (shift ? 1 : 1 / 30.0))
            }
            return true
        case "s", "S":
            model.splitAtPlayhead()
            return true
        case "f", "F":
            guard kind == .workbench else { return false }
            toggleFullscreen(of: model)
            return true
        case "\u{7F}", "\u{8}": // Delete / Backspace
            switch model.selection {
            case .clip(let id):
                model.deleteClip(id)
                return true
            case .audioGain(let id):
                guard kind == .audioEditor else { return false }
                model.removeGain(id)
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}
