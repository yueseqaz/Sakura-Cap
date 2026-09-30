import AppKit

/// 监听显示器热插拔（连接/断开/分辨率变化）。
final class ScreenChangeMonitor {
    /// 回调保证在主线程（但需在 MainActor 上执行，见 assumeIsolated）
    var onScreensChanged: (@MainActor () -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onScreensChanged?() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
