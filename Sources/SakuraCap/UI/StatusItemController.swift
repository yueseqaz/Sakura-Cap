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
        // Keep the symbol inside the status item's 22pt-high menu bar slot.
        // A symbol image without an explicit size can be clipped by NSStatusBarButton.
        image?.size = NSSize(width: 17, height: 17)
        image?.isTemplate = false
        return image
    }

    init(controller: RecordingController) {
        self.controller = controller
        super.init()

        let viewModel = PanelViewModel(controller: controller)
        self.viewModel = viewModel

        if let button = item.button {
            button.image = baseIcon(tint: .systemYellow)
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
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
        // The recording HUD already shows elapsed time. Keep the status item icon-only
        // so its title never collides with the icon in the menu bar.
        item.length = NSStatusItem.squareLength
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
            menu.addItem(audioMenuItem())
        } else if controller.state == .recording {
            let mmss = Self.mmss(controller.elapsed)
            let pauseTitle = controller.isPaused
                ? String(format: L("继续录制（%@）"), mmss)
                : String(format: L("暂停录制（%@）"), mmss)
            menu.addItem(makeItem(pauseTitle, #selector(menuPause)))
            menu.addItem(makeItem(String(format: L("停止录制（%@）"), mmss), #selector(menuToggle)))
            menu.addItem(audioMenuItem())
        } else if controller.isBusy {
            menu.addItem(makeItem(L("取消录制"), #selector(menuToggle)))
            menu.addItem(audioMenuItem())
        } else {
            let shot = NSMenuItem(title: L("截屏"), action: nil, keyEquivalent: "")
            let shotMenu = NSMenu()
            shotMenu.addItem(makeItem(L("全屏截图"), #selector(screenshotDisplay)))
            shotMenu.addItem(makeItem(L("区域截图"), #selector(screenshotRegion)))
            shotMenu.addItem(makeItem(L("识别文字（OCR）"), #selector(ocrRegion)))
            shotMenu.addItem(makeItem(L("识别二维码"), #selector(qrRegion)))
            shotMenu.addItem(makeItem(L("滚动截屏…"), #selector(scrollingCapture)))
            shot.submenu = shotMenu
            menu.addItem(shot)

            let record = NSMenuItem(title: L("开始录制"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(makeItem(L("全屏录制"), #selector(recordDisplay)))
            submenu.addItem(makeItem(L("框选区域"), #selector(recordRegion)))
            submenu.addItem(makeItem(L("窗口录制…"), #selector(recordWindow)))
            record.submenu = submenu
            menu.addItem(record)

            menu.addItem(audioMenuItem())

            let translate = NSMenuItem(title: L("翻译"), action: nil, keyEquivalent: "")
            let translateMenu = NSMenu()
            translateMenu.addItem(makeItem(L("文本翻译…"), #selector(openTranslateWindow)))
            translateMenu.addItem(makeItem(L("识别屏幕翻译"), #selector(translateRegion)))
            translate.submenu = translateMenu
            menu.addItem(translate)

            let ai = NSMenuItem(title: L("AI"), action: nil, keyEquivalent: "")
            let aiMenu = NSMenu()
            aiMenu.addItem(makeItem(L("AI 聊天…"), #selector(openAIChat)))
            aiMenu.addItem(makeItem(L("截屏问 AI（图片）"), #selector(askAIImage)))
            aiMenu.addItem(makeItem(L("截屏问 AI（OCR）"), #selector(askAIOCR)))
            aiMenu.addItem(makeItem(L("聊天记录"), #selector(openAIHistory)))
            ai.submenu = aiMenu
            menu.addItem(ai)
        }
        menu.addItem(.separator())
        // 工具合集：避免一级菜单过长
        let tools = NSMenuItem(title: L("工具"), action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu()
        let annotation = makeItem(ScreenAnnotationController.shared.isActive
            ? L("结束屏幕标注") : L("屏幕标注"), #selector(menuScreenAnnotation))
        annotation.state = ScreenAnnotationController.shared.isActive ? .on : .off
        toolsMenu.addItem(annotation)
        let preview = makeItem(L("镜头预览"), #selector(menuCameraPreview))
        preview.state = CameraPiP.shared.previewEnabled ? .on : .off
        toolsMenu.addItem(preview)
        toolsMenu.addItem(makeItem(L("标注图片…"), #selector(annotateImage)))
        toolsMenu.addItem(makeItem(L("裁剪视频…"), #selector(menuTrim)))
        toolsMenu.addItem(makeItem(L("编辑音频…"), #selector(menuEditAudio)))
        toolsMenu.addItem(makeItem(L("对比…"), #selector(menuImageCompare)))
        tools.submenu = toolsMenu
        menu.addItem(tools)
        menu.addItem(makeItem(L("设置…"), #selector(menuSettings)))
        menu.addItem(makeItem(L("退出"), #selector(menuQuit)))
        return menu
    }

    /// 「录音」菜单项：空闲时给三种声源；录音中给 暂停/停止
    private func audioMenuItem() -> NSMenuItem {
        let audio = AudioRecorderController.shared
        let item = NSMenuItem(title: L("录音"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if audio.state == .idle {
            for source in AudioRecorderController.Source.allCases {
                let sourceItem = makeItem(source.label, #selector(audioStart(_:)))
                sourceItem.representedObject = source.rawValue
                submenu.addItem(sourceItem)
            }
        } else {
            let mmss = Self.mmss(audio.elapsed)
            submenu.addItem(makeItem(audio.state == .paused
                ? String(format: L("继续录音（%@）"), mmss)
                : String(format: L("暂停录音（%@）"), mmss), #selector(audioPause)))
            submenu.addItem(makeItem(String(format: L("停止录音（%@）"), mmss), #selector(audioStop)))
        }
        item.submenu = submenu
        return item
    }

    @objc private func audioStart(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let source = AudioRecorderController.Source(rawValue: raw) else { return }
        AudioRecorderController.shared.start(source)
    }

    @objc private func menuImageCompare() { ImageCompareToolController.shared.show() }

    @objc private func menuEditAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = L("选择要编辑的音频")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AudioEditorPresenter.shared.show(url: url, origin: .manual)
    }

    @objc private func audioPause() { AudioRecorderController.shared.togglePause() }
    @objc private func audioStop() { AudioRecorderController.shared.stop() }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuToggle() { controller.toggle() }
    @objc private func menuCancelArmed() { controller.cancelArmed() }
    @objc private func menuPause() { controller.togglePause() }
    @objc private func menuCameraPreview() { CameraPiP.shared.togglePreview() }
    @objc private func menuScreenAnnotation() { ScreenAnnotationController.shared.toggle() }

    // 菜单项 / 全局快捷键 共用入口
    func recordFullScreen() {
        // 并行录制开启时无需点选屏幕（点选流程会把开关改回单屏）：直接待开始，录全部显示器
        if AppSettings.shared.allDisplaysParallel {
            AppSettings.shared.captureMode = .display
            controller.arm()
            return
        }
        beginSelection(.displayOnly)
    }
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
    @objc private func qrRegion() { beginSelection(.regionOnly, purpose: .qr) }
    @objc private func translateRegion() { beginSelection(.regionOnly, purpose: .translate) }
    @objc private func openTranslateWindow() { TranslationPresenter.shared.present() }
    @objc private func openAIChat() { AIChatPresenter.shared.open() }
    @objc private func askAIImage() { beginSelection(.regionOnly, purpose: .aiImage) }
    @objc private func askAIOCR() { beginSelection(.regionOnly, purpose: .aiOCR) }
    @objc private func openAIHistory() { AIHistoryPresenter.shared.open() }
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
            SelectionController.shared.begin(intent, purpose: purpose,
                                             autoSelectHoveredDisplay: intent == .displayOnly)
        }
    }

    @objc private func menuSettings() { showSettings() }
    @objc private func annotateImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = L("选择要标注的图片")
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let base = url.deletingPathExtension().lastPathComponent
        AnnotationEditorController.shared.open(image: cg, suggestedName: "\(base) - \(L("标注")).png", source: .existingFile)
    }
    @objc private func menuTrim() {
        if let url = controller.lastSavedFiles.first, FileManager.default.fileExists(atPath: url.path) {
            DispatchQueue.main.async {
                WorkbenchWindowController.shared.show(url: url, origin: .manual)
            }
        } else {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.movie]
            panel.allowsMultipleSelection = false
            panel.message = "选择要裁剪的视频"
            if panel.runModal() == .OK, let url = panel.url {
                // Let the file panel and status menu finish dismissing before ordering the editor.
                DispatchQueue.main.async {
                    WorkbenchWindowController.shared.show(url: url, origin: .manual)
                }
            }
        }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - 设置窗口

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let window = ensureSettingsWindow()
        window.makeKeyAndOrderFront(nil)
    }

    /// 设置窗口的静态引用：TCC 授权弹窗会夺走焦点，系统可能顺势把普通窗口从桌面
    /// 收走（切 Space / 窗口收纳），菜单栏应用又没有 Dock 图标可以找回。
    /// 授权期间临时把窗口提为悬浮 + 跟随所有空间（不受收纳机制影响），
    /// 授权结束立刻恢复普通层级——平时它就是个正常的文档窗口。
    private static weak var activeSettingsWindow: NSWindow?
    private static weak var heldSettingsWindow: NSWindow?

    static func holdSettingsOnDesktop() {
        DispatchQueue.main.async {
            guard let window = activeSettingsWindow, window.isVisible, heldSettingsWindow == nil else { return }
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            heldSettingsWindow = window
        }
    }

    static func releaseSettingsFromDesktop() {
        DispatchQueue.main.async {
            guard let window = heldSettingsWindow else { return }
            heldSettingsWindow = nil
            window.level = .normal
            window.collectionBehavior = []
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func ensureSettingsWindow() -> NSWindow {
        if let window = settingsWindow { return window }
        // 880 宽让「录制」页的成对控件默认并排显示（不够宽时会自动竖排，不裁切）
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 700),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Sakura-Cap"
        window.minSize = NSSize(width: 640, height: 520)
        // 平时按普通文档窗口对待；授权弹窗期间由 holdSettingsOnDesktop 临时提悬浮
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.contentView = NSHostingView(rootView: PanelView(viewModel: viewModel))
        window.center()
        settingsWindow = window
        Self.activeSettingsWindow = window
        return window
    }

    // MARK: - 图标与计时

    private func refreshIcon() {
        guard let button = item.button else { return }
        // 彩色轮换只在录制中生效；任何其它状态先停掉轮换定时器
        if controller.state != .recording || controller.isPaused { stopRainbowIcon() }
        switch controller.state {
        case .idle:
            RegionFrameOverlay.shared.hide()
            button.contentTintColor = nil
            button.image = baseIcon(tint: .systemYellow)
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
            if controller.isPaused {
                button.contentTintColor = nil
                button.image = baseIcon(tint: .systemOrange)
            } else {
                startRainbowIcon()
            }
        }
        item.button?.title = ""
    }

    // MARK: - 录制中的彩色轮换图标

    /// 录制时菜单栏图标在光谱色间轮流变换，作为「正在录制」的醒目提示
    private static let rainbowPalette: [NSColor] = [
        .systemPink, .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemTeal, .systemBlue, .systemIndigo, .systemPurple,
    ]
    private var rainbowIcons: [NSImage] = []
    private var rainbowTimer: Timer?
    private var rainbowIndex = 0

    private func startRainbowIcon() {
        guard rainbowTimer == nil else { return }
        if rainbowIcons.isEmpty {
            rainbowIcons = Self.rainbowPalette.compactMap { baseIcon(tint: $0) }
        }
        guard !rainbowIcons.isEmpty, let button = item.button else { return }
        rainbowIndex = 0
        button.contentTintColor = nil
        button.image = rainbowIcons[0]
        // .common 模式：菜单展开时也继续轮换
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.stepRainbowIcon() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rainbowTimer = timer
    }

    private func stepRainbowIcon() {
        guard !rainbowIcons.isEmpty, item.button != nil else { return }
        rainbowIndex = (rainbowIndex + 1) % rainbowIcons.count
        item.button?.image = rainbowIcons[rainbowIndex]
    }

    private func stopRainbowIcon() {
        rainbowTimer?.invalidate()
        rainbowTimer = nil
        if controller.state == .idle || controller.state == .ready {
            rainbowIndex = 0
        }
    }

    static func mmss(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

