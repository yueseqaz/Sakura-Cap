import AppKit
import SwiftUI

/// 点击指示引擎：录制期间收到点击 → 在对应屏幕弹出覆盖层窗口。
/// 覆盖层窗口保持 sharingType = .shared（关键：.none 会被 ScreenCaptureKit 排除出录制）。
@MainActor
final class IndicatorEngine: ObservableObject {
    static let shared = IndicatorEngine()

    @Published private(set) var isMonitoring = false
    @Published private(set) var permissionDenied = false

    private let monitor = ClickMonitor()
    private var windows: [IndicatorWindow] = []
    private var capturing = false

    private init() {
        monitor.onLeftClick = { [weak self] point in self?.spawn(at: point, isRight: false) }
        monitor.onRightClick = { [weak self] point in
            guard let self, AppSettings.shared.indicatorIncludeRightClick else { return }
            self.spawn(at: point, isRight: true)
        }
    }

    /// 启动监听（面板打开开关或开始录制时调用）。返回 false = 缺输入监控权限。
    @discardableResult
    func start() -> Bool {
        permissionDenied = false
        // CGEvent.tapCreate 无权限时也可能返回非 nil 但收不到事件，故先用 preflight 判定
        if !PermissionCenter.inputMonitoringGranted() {
            PermissionCenter.requestInputMonitoring()
        }
        let granted = PermissionCenter.inputMonitoringGranted()
        let ok = granted && monitor.start()
        isMonitoring = ok
        permissionDenied = !ok
        if !ok {
            Log.indicator.error("点击监听不可用：缺少「输入监控」权限（kTCCServiceListenEvent）")
        }
        return ok
    }

    func stop() {
        monitor.stop()
        isMonitoring = false
        clearWindows()
    }

    func beginCapture() {
        capturing = true
        start()
    }

    func endCapture() {
        capturing = false
        clearWindows()
    }

    private func clearWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func spawn(at cgPoint: CGPoint, isRight: Bool) {
        guard capturing, isMonitoring else { return }
        guard let screen = ScreenCoordinate.screen(containingCGPoint: cgPoint) else { return }
        let window = IndicatorWindow(atCGPoint: cgPoint, onScreen: screen) { [weak self] finished in
            self?.windows.removeAll { $0 === finished }
        }
        windows.append(window)
        if windows.count > 16 {
            windows.removeFirst().orderOut(nil) // 防御高频连击堆积
        }
        window.play()
        Log.indicator.debug("点击标记 @ \(String(describing: cgPoint.x), privacy: .public),\(String(describing: cgPoint.y), privacy: .public) 右键=\(isRight)")
    }
}
