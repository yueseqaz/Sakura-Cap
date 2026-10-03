import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: RecordingController?
    private var statusItem: StatusItemController?
    private var hud: RecordingHUDController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {        // 单实例：已有实例则激活它并退出
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sakura.sakuracap"
        let current = NSRunningApplication.current
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { $0 != current }
        if !existing.isEmpty {
            existing.forEach { $0.activate(options: []) }
            NSApp.terminate(nil)
            return
        }

        CompletionNotifier.shared.setup()

        let controller = RecordingController()
        self.controller = controller
        let statusItem = StatusItemController(controller: controller)
        self.statusItem = statusItem
        // 录制悬浮控制条（自己订阅 controller 状态，此处仅保留引用）
        self.hud = RecordingHUDController(controller: controller)
        // 摄像头画中画：绑定录制状态
        CameraPiP.shared.attach(controller: controller)

        applyHotKeys()

        // 首次启动：弹出欢迎 / 引导页；之后启动静默检查更新
        if AppSettings.shared.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { UpdateChecker.check(manual: false) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { OnboardingWindowController.shared.show() }
        }

        // 可视化选择（菜单「开始录制」/ 设置面板「框选区域」）的统一出口：
        // 把选择结果写进设置并立即开始录制
        SelectionController.shared.onPicked = { [weak self] result in
            guard let self, let controller = self.controller else { return }
            // 截图用途：不进入录制流程
            if SelectionController.shared.currentPurpose == .screenshot {
                switch result {
                case .display(let id): ScreenshotController.shared.captureDisplay(id)
                case .region(let region): ScreenshotController.shared.captureRegion(region)
                }
                return
            }
            // OCR 用途：识别文字并复制到剪贴板
            if SelectionController.shared.currentPurpose == .ocr {
                switch result {
                case .display(let id): ScreenshotController.shared.ocrDisplay(id)
                case .region(let region): ScreenshotController.shared.ocrRegion(region)
                }
                return
            }
            // 二维码：框选后识别内容并复制
            if SelectionController.shared.currentPurpose == .qr {
                if case .region(let region) = result { ScreenshotController.shared.qrRegion(region) }
                return
            }
            // 截图对比：框选第二张图
            if SelectionController.shared.currentPurpose == .compare {
                if case .region(let region) = result { ScreenshotController.shared.compareRegion(region) }
                return
            }
            // 滚动截屏：框选后进入长截图
            if SelectionController.shared.currentPurpose == .scrolling {
                if case .region(let region) = result { ScrollingCapture.shared.start(region: region) }
                return
            }
            let settings = AppSettings.shared
            switch result {
            case .display(let id):
                settings.captureMode = .display
                settings.allDisplaysParallel = false
                settings.selectedDisplayID = id
            case .region(let region):
                settings.captureMode = .region
                settings.updateRegion(region)
                RegionFrameOverlay.shared.show(region: region)
            }
            // 选择完成后不立即开录：进入待开始状态，由 HUD 上的「开始录制」确认
            controller.arm()
        }
        // 仅「录制」的框选被取消时回到设置窗口；截图 / OCR / 二维码 / 对比取消则什么都不做
        SelectionController.shared.onCancelled = { [weak self] _ in
            let purpose = SelectionController.shared.currentPurpose
            if purpose == .record {
                self?.statusItem?.showSettings()
            } else if purpose == .compare {
                CompareController.shared.cancelPendingCapture()
            }
        }
        // 若开启了需要「输入监控」的功能，启动时即请求授权（首次会弹系统框）
        if AppSettings.shared.clickIndicatorEnabled { IndicatorEngine.shared.start() }
        if AppSettings.shared.keyDisplayEnabled { KeyDisplay.shared.start() }
        AppSettings.shared.$hotKeys
            .dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyHotKeys() }.store(in: &cancellables)

        // 退出前尽力收尾（写入 moov，避免文件不可播放）
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.emergencyFinalize() }
        }

        // 启动时不主动弹出设置窗口：仅当用户从菜单栏点击「设置…」时才打开。
        // 未选输出目录等前置条件由录制启动流程自行兜底（OutputDirectoryPicker）。
    }

    /// 菜单栏应用：关掉所有窗口（比如关掉「定住」的图）不应退出应用
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func applyHotKeys() {
        let combos = HotKeyAction.allCases.compactMap { action -> (HotKeyAction, HotKeyCombo)? in
            guard let combo = AppSettings.shared.hotKeys[action] else { return nil }
            return (action, combo)
        }
        HotKeyManager.shared.register(combos) { [weak self] action in
            self?.performHotKey(action)
        }
    }

    private func performHotKey(_ action: HotKeyAction) {
        guard let statusItem else { return }
        switch action {
        case .recordFull: statusItem.recordFullScreen()
        case .recordWindow: statusItem.startWindowRecording()
        case .recordRegion: statusItem.recordRegionSelection()
        case .shotFull: statusItem.screenshotFullScreen()
        case .shotRegion: statusItem.screenshotRegionSelection()
        case .ocr: statusItem.recognizeText()
        case .scrolling: statusItem.scrollingScreenshot()
        }
    }
}
