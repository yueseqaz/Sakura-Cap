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

        // 调试入口：`SakuraCap -workbench <媒体路径>` 按类型打开视频工作台 / 音频编辑器
        if let index = CommandLine.arguments.firstIndex(of: "-workbench"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            if FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                let audioExts = ["m4a", "mp3", "wav", "aac", "flac"]
                if audioExts.contains(url.pathExtension.lowercased()) {
                    AudioEditorPresenter.shared.show(url: url, origin: .manual)
                } else {
                    WorkbenchWindowController.shared.show(url: url, origin: .manual)
                }
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

        // 选区结果的路由（截图/OCR/二维码/对比/翻译/滚动/问AI/录制选区）统一在
        // CaptureIntentCoordinator；此处只接线
        CaptureIntentCoordinator.shared.attach(controller: controller)
        CaptureIntentCoordinator.shared.beginObservingSelection()
        // 引擎自订阅设置开关（订阅时即按当前值启停）；开启需要「输入监控」的功能时，
        // 订阅即触发 start() → 首次会弹系统授权框
        IndicatorEngine.shared.startObservingSettings()
        KeyDisplay.shared.startObservingSettings()
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
