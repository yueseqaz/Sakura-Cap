import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: RecordingController?
    private var statusItem: StatusItemController?
    private var hud: RecordingHUDController?
    private var fpsOverlay: FPSOverlay?
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
        self.fpsOverlay = FPSOverlay(controller: controller)
        // 摄像头画中画：绑定录制状态
        CameraPiP.shared.attach(controller: controller)

        applyHotKeys()

        // 调试入口：`-audiotest` 录 5 秒系统声音后自动停止并退出（结果写 /tmp/audiotest.log）
        if CommandLine.arguments.contains("-audiotest") {
            AudioRecorderController.shared.start(.system)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                AudioRecorderController.shared.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let path = AudioRecorderController.shared.lastSavedURL?.path ?? "nil"
                    try? path.write(toFile: "/tmp/audiotest.log", atomically: true, encoding: .utf8)
                    exit(0)
                }
            }
        }

        // 调试入口：`-aichat` 打开 AI 聊天窗口（带样例 Markdown 消息）
        if CommandLine.arguments.contains("-aichat") {
            var demo = AIChatSession()
            let md = "# 效果展示\n支持 **加粗**、*斜体*、`代码`、[链接](https://github.com)。\n\n- 列表一\n- 列表二\n\n```swift\nlet answer = 42\n```\n\n> 流式输出时内容会逐段出现。"
            demo.messages = [
                AIChatMessage(role: .user, text: "给我看看 Markdown 效果"),
                AIChatMessage(role: .assistant, text: md),
                AIChatMessage(role: .user, text: "再来一段长一点的，测试滚动"),
                AIChatMessage(role: .assistant, text: md + "\n\n" + md),
            ]
            AIChatPresenter.shared.open(session: demo)
        }

        // 调试入口：`SakuraCap -workbench <视频路径>` 直接打开后期工作台
        if let index = CommandLine.arguments.firstIndex(of: "-workbench"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            if FileManager.default.fileExists(atPath: path) {
                WorkbenchWindowController.shared.show(url: URL(fileURLWithPath: path), origin: .manual)
            }
        }


        // Vision 首次识别会加载模型；后台预热，不延迟菜单栏和窗口启动。
        Task.detached(priority: .utility) { OCR.prewarm() }

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
            // 翻译：框选区域后 OCR + AI 翻译
            if SelectionController.shared.currentPurpose == .translate {
                if case .region(let region) = result { ScreenshotController.shared.translateRegion(region) }
                return
            }
            // 滚动截屏：框选后进入长截图
            if SelectionController.shared.currentPurpose == .scrolling {
                if case .region(let region) = result { ScrollingCapture.shared.start(region: region) }
                return
            }
            // 截屏问 AI：直接给图（视觉模型）
            if SelectionController.shared.currentPurpose == .aiImage {
                Task { @MainActor in
                    guard #available(macOS 14.0, *) else { return }
                    let image: CGImage?
                    switch result {
                    case .display(let id): image = try? await ScreenshotController.shared.captureImage(displayID: id, region: nil)
                    case .region(let region): image = try? await ScreenshotController.shared.captureImage(displayID: region.displayID, region: region)
                    }
                    if let image {
                        AIChatPresenter.shared.openWithImage(image)
                    } else {
                        Toast.show(title: L("截屏失败"), detail: nil)
                    }
                }
                return
            }
            // 截屏问 AI：先 OCR 再带文字（不支持图片的模型）
            if SelectionController.shared.currentPurpose == .aiOCR {
                Task { @MainActor in
                    guard #available(macOS 14.0, *) else { return }
                    var image: CGImage?
                    switch result {
                    case .display(let id): image = try? await ScreenshotController.shared.captureImage(displayID: id, region: nil)
                    case .region(let region): image = try? await ScreenshotController.shared.captureImage(displayID: region.displayID, region: region)
                    }
                    guard let image else {
                        Toast.show(title: L("截屏失败"), detail: nil)
                        return
                    }
                    switch await OCR.recognize(image) {
                    case .text(let text): AIChatPresenter.shared.openWithText(text)
                    case .empty: Toast.show(title: L("未识别到文字"), detail: nil)
                    case .failed(let error): Toast.show(title: L("识别失败"), detail: error.localizedDescription)
                    }
                }
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
        // 取消选择不应自行弹出设置窗口；只有用户点「设置…」才打开它。
        SelectionController.shared.onCancelled = { _ in
            let purpose = SelectionController.shared.currentPurpose
            if purpose == .compare {
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
