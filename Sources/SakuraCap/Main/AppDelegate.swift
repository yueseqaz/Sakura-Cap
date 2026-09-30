import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: RecordingController?
    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例：已有实例则激活它并退出
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

        HotKeyManager.shared.onToggle = { [weak controller] in
            Task { @MainActor in controller?.toggle() }
        }
        HotKeyManager.shared.register(AppSettings.shared.hotKeyCombo)

        // 可视化选择（菜单「开始录制」/ 设置面板「框选区域」）的统一出口：
        // 把选择结果写进设置并立即开始录制
        SelectionController.shared.onPicked = { [weak self] result in
            guard let self, let controller = self.controller else { return }
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
            controller.start()
        }
        // 仅区域框选被取消时回到设置窗口；可视化选择取消则不做任何事
        SelectionController.shared.onCancelled = { [weak self] intent in
            if intent == .regionOnly {
                self?.statusItem?.showSettings()
            }
        }
        let reRegisterHotKey = { HotKeyManager.shared.register(AppSettings.shared.hotKeyCombo) }
        AppSettings.shared.$hotKeyCode
            .dropFirst().receive(on: DispatchQueue.main)
            .sink { _ in reRegisterHotKey() }.store(in: &cancellables)
        AppSettings.shared.$hotKeyModifiers
            .dropFirst().receive(on: DispatchQueue.main)
            .sink { _ in reRegisterHotKey() }.store(in: &cancellables)

        // 退出前尽力收尾（写入 moov，避免文件不可播放）
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.emergencyFinalize() }
        }

        // 首启打开设置窗口：引导选输出目录与权限
        statusItem.showSettings()
    }
}
