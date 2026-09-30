import AppKit
import SwiftUI
import Combine

/// 状态栏交互：点击弹出菜单（开始录制 / 设置 / 退出）；
/// 「开始录制」进入可视化选择层（点屏/点窗口/框区域）；录制中图标切换并显示计时。
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: RecordingController
    private var viewModel: PanelViewModel!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(controller: RecordingController) {
        self.controller = controller
        super.init()

        let viewModel = PanelViewModel(controller: controller)
        self.viewModel = viewModel
        viewModel.requestClosePanel = { [weak self] in self?.closeSettings() }
        viewModel.requestOpenPanel = { [weak self] in self?.showSettings() }

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "record.circle",
                                   accessibilityDescription: "Sakura-Cap")?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
        controller.$elapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTimerTitle() }
            .store(in: &cancellables)
        refreshIcon()
    }

    // MARK: - 菜单

    @objc private func statusClicked() {
        guard let button = item.button else { return }
        item.menu = buildMenu()
        button.performClick(nil) // 同步弹出菜单
        item.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if controller.isBusy {
            menu.addItem(makeItem("停止录制（\(Self.mmss(controller.elapsed))）", #selector(menuToggle)))
        } else {
            let record = NSMenuItem(title: "开始录制", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(makeItem("全屏录制", #selector(recordDisplay)))
            submenu.addItem(makeItem("框选区域", #selector(recordRegion)))
            record.submenu = submenu
            menu.addItem(record)
        }
        menu.addItem(.separator())
        menu.addItem(makeItem("打开文件夹", #selector(menuOpenFolder)))
        menu.addItem(makeItem("设置…", #selector(menuSettings)))
        menu.addItem(makeItem("退出 Sakura-Cap", #selector(menuQuit)))
        return menu
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuToggle() { controller.toggle() }

    @objc private func recordDisplay() { beginSelection(.displayOnly) }
    @objc private func recordRegion() { beginSelection(.regionOnly) }

    private func beginSelection(_ intent: SelectionIntent) {
        Task { @MainActor in
            guard PermissionCenter.screenCaptureGranted() else {
                PermissionCenter.openScreenCaptureSettings()
                let alert = NSAlert()
                alert.messageText = "需要「屏幕录制」权限"
                alert.informativeText = "请在 系统设置 → 隐私与安全性 → 屏幕录制 中勾选 Sakura-Cap，然后重新点击「开始录制」。"
                alert.addButton(withTitle: "好")
                alert.runModal()
                return
            }
            // 刷新显示器列表（同时验证权限有效），再进入对应的选择层
            _ = try? await DisplayCatalog.shared.refresh()
            SelectionController.shared.begin(intent)
        }
    }

    @objc private func menuSettings() { showSettings() }
    @objc private func menuOpenFolder() {
        guard let directory = AppSettings.shared.outputDirectory else {
            showSettings()
            return
        }
        NSWorkspace.shared.open(directory)
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - 设置窗口

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let window = ensureSettingsWindow()
        window.makeKeyAndOrderFront(nil)
    }

    func closeSettings() {
        settingsWindow?.performClose(nil)
    }

    private func ensureSettingsWindow() -> NSWindow {
        if let window = settingsWindow { return window }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Sakura-Cap"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.sharingType = .none // 设置窗口永不进入录制画面
        window.contentView = NSHostingView(rootView: PanelView(viewModel: viewModel))
        window.center()
        settingsWindow = window
        return window
    }

    // MARK: - 图标与计时

    private func refreshIcon() {
        guard let button = item.button else { return }
        switch controller.state {
        case .idle:
            RegionFrameOverlay.shared.hide()
            button.contentTintColor = nil
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
            button.title = ""
        case .preparing, .countdown:
            button.contentTintColor = .systemOrange
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)
        case .finalizing:
            button.contentTintColor = .systemOrange
            button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: nil)
        case .recording:
            button.contentTintColor = .systemRed
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
        }
        refreshTimerTitle()
    }

    private func refreshTimerTitle() {
        item.button?.title = controller.state == .recording ? " " + Self.mmss(controller.elapsed) : ""
    }

    static func mmss(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
