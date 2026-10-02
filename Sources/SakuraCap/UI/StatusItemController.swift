import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// 状态栏交互：点击弹出菜单（开始录制 / 设置 / 退出）；
/// 「开始录制」进入可视化选择层（点屏/点窗口/框区域）；录制中图标切换并显示计时。
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: RecordingController
    private var viewModel: PanelViewModel!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    /// 状态栏图标：与设置面板标题前的图标保持一致（camera.aperture），并指定颜色
    private static let baseSymbol = "camera.aperture"
    private func baseIcon(tint: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        let image = NSImage(systemSymbolName: Self.baseSymbol, accessibilityDescription: "Sakura-Cap")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }

    init(controller: RecordingController) {
        self.controller = controller
        super.init()

        let viewModel = PanelViewModel(controller: controller)
        self.viewModel = viewModel

        if let button = item.button {
            button.image = baseIcon(tint: .systemPink)
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
        controller.$isPaused
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
        if controller.state == .ready {
            menu.addItem(makeItem(L("开始录制"), #selector(menuToggle)))
            menu.addItem(makeItem(L("取消"), #selector(menuCancelArmed)))
        } else if controller.state == .recording {
            let mmss = Self.mmss(controller.elapsed)
            let pauseTitle = controller.isPaused
                ? String(format: L("继续录制（%@）"), mmss)
                : String(format: L("暂停录制（%@）"), mmss)
            menu.addItem(makeItem(pauseTitle, #selector(menuPause)))
            menu.addItem(makeItem(String(format: L("停止录制（%@）"), mmss), #selector(menuToggle)))
        } else if controller.isBusy {
            menu.addItem(makeItem(L("取消录制"), #selector(menuToggle)))
        } else {
            let record = NSMenuItem(title: L("开始录制"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(makeItem(L("全屏录制"), #selector(recordDisplay)))
            submenu.addItem(makeItem(L("框选区域"), #selector(recordRegion)))
            submenu.addItem(makeItem(L("窗口录制…"), #selector(recordWindow)))
            record.submenu = submenu
            menu.addItem(record)

            let shot = NSMenuItem(title: L("截图"), action: nil, keyEquivalent: "")
            let shotMenu = NSMenu()
            shotMenu.addItem(makeItem(L("全屏截图"), #selector(screenshotDisplay)))
            shotMenu.addItem(makeItem(L("区域截图"), #selector(screenshotRegion)))
            shotMenu.addItem(makeItem(L("识别文字（OCR）"), #selector(ocrRegion)))
            shotMenu.addItem(makeItem(L("滚动截屏…"), #selector(scrollingCapture)))
            shot.submenu = shotMenu
            menu.addItem(shot)
        }
        menu.addItem(.separator())
        menu.addItem(makeItem(L("打开文件夹"), #selector(menuOpenFolder)))
        menu.addItem(makeItem(L("标注图片…"), #selector(annotateImage)))
        menu.addItem(makeItem(L("裁剪视频…"), #selector(menuTrim)))
        menu.addItem(makeItem(L("设置…"), #selector(menuSettings)))
        menu.addItem(makeItem(L("检查更新…"), #selector(menuCheckUpdates)))
        menu.addItem(makeItem(L("欢迎使用…"), #selector(menuWelcome)))
        menu.addItem(makeItem(L("关于"), #selector(menuAbout)))
        menu.addItem(makeItem(L("退出"), #selector(menuQuit)))
        return menu
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuToggle() { controller.toggle() }
    @objc private func menuCancelArmed() { controller.cancelArmed() }
    @objc private func menuPause() { controller.togglePause() }

    // 菜单项 / 全局快捷键 共用入口
    func recordFullScreen() { beginSelection(.displayOnly) }
    func recordRegionSelection() { beginSelection(.regionOnly) }
    func screenshotFullScreen() { beginSelection(.displayOnly, purpose: .screenshot) }
    func screenshotRegionSelection() { beginSelection(.regionOnly, purpose: .screenshot) }
    func recognizeText() { beginSelection(.regionOnly, purpose: .ocr) }
    func scrollingScreenshot() { beginSelection(.regionOnly, purpose: .scrolling) }

    @objc private func recordDisplay() { recordFullScreen() }
    @objc private func recordRegion() { recordRegionSelection() }
    @objc private func screenshotDisplay() { screenshotFullScreen() }
    @objc private func screenshotRegion() { screenshotRegionSelection() }
    @objc private func ocrRegion() { recognizeText() }
    @objc private func scrollingCapture() { scrollingScreenshot() }
    @objc private func recordWindow() { startWindowRecording() }

    func startWindowRecording() {
        Task { @MainActor in
            guard #available(macOS 14.0, *) else {
                let alert = NSAlert()
                alert.messageText = L("窗口录制需要 macOS 14 或更高版本")
                alert.addButton(withTitle: L("好"))
                runModalAlert(alert)
                return
            }
            guard PermissionCenter.screenCaptureGranted() else {
                PermissionCenter.openScreenCaptureSettings()
                return
            }
            WindowPicker.shared.onPicked = { [weak self] in self?.controller.arm() }
            WindowPicker.shared.present()
        }
    }

    private func beginSelection(_ intent: SelectionIntent, purpose: SelectionPurpose = .record) {
        Task { @MainActor in
            guard PermissionCenter.screenCaptureGranted() else {
                PermissionCenter.openScreenCaptureSettings()
                let alert = NSAlert()
                alert.messageText = L("需要「屏幕录制」权限")
                alert.informativeText = L("请在「系统设置 → 隐私与安全性 → 屏幕录制」中允许 Sakura-Cap，然后重新开始录制。")
                alert.addButton(withTitle: L("好"))
                runModalAlert(alert)
                return
            }
            // 刷新显示器列表（同时验证权限有效），再进入对应的选择层
            _ = try? await DisplayCatalog.shared.refresh()
            SelectionController.shared.begin(intent, purpose: purpose)
        }
    }

    @objc private func menuSettings() { showSettings() }
    @objc private func menuCheckUpdates() { UpdateChecker.check(manual: true) }
    @objc private func menuWelcome() { OnboardingWindowController.shared.show() }
    @objc private func menuAbout() { AboutWindowController.shared.show() }
    @objc private func annotateImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = L("选择要标注的图片")
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let base = url.deletingPathExtension().lastPathComponent
        AnnotationEditorController.shared.open(image: cg, suggestedName: "\(base) - \(L("标注")).png")
    }
    @objc private func menuTrim() {
        if let url = controller.lastSavedFiles.first, FileManager.default.fileExists(atPath: url.path) {
            TrimWindowController.shared.show(url: url, origin: .manual)
        } else {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.movie]
            panel.allowsMultipleSelection = false
            panel.message = "选择要裁剪的视频"
            if panel.runModal() == .OK, let url = panel.url {
                TrimWindowController.shared.show(url: url, origin: .manual)
            }
        }
    }
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
            button.image = baseIcon(tint: .systemPink)
            button.title = ""
        case .ready:
            // 已选定范围、待用户确认开始
            button.contentTintColor = nil
            button.image = baseIcon(tint: .systemOrange)
            button.title = ""
        case .preparing, .countdown:
            button.contentTintColor = nil
            button.image = baseIcon(tint: .systemOrange)
        case .finalizing:
            button.contentTintColor = nil
            button.image = baseIcon(tint: .systemOrange)
        case .recording:
            button.contentTintColor = nil
            button.image = baseIcon(tint: controller.isPaused ? .systemOrange : .systemRed)
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
