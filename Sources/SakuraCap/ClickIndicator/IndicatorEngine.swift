import AppKit
import Combine
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
    private var settingsCancellable: AnyCancellable?

    /// 录制期间的原始点击回调（无论点击标记是否显示），自动聚焦用它记录点击位置。
    /// 仅在 beginCapture() 之后、endCapture() 之前触发。
    var onAnyClick: ((CGPoint) -> Void)?

    private init() {
        monitor.onLeftClick = { [weak self] point in
            self?.noteRawClick(point)
            self?.spawn(at: point, isRight: false)
        }
        monitor.onRightClick = { [weak self] point in
            self?.noteRawClick(point)
            guard let self, AppSettings.shared.indicatorIncludeRightClick else { return }
            self.spawn(at: point, isRight: true)
        }
    }

    private func noteRawClick(_ point: CGPoint) {
        guard capturing else { return }
        onAnyClick?(point)
    }

    /// 订阅设置：开关打开即监听、关闭即停止（订阅时先按当前值执行一次）。
    /// 启动时调用一次；之后 UI 只改设置，引擎自己跟进——不再依赖调用方记得「改设置 + 启停引擎」两步。
    func startObservingSettings() {
        guard settingsCancellable == nil else { return }
        settingsCancellable = AppSettings.shared.$clickIndicatorEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.start() } else { self.stop() }
            }
    }

    /// 启动监听（面板打开开关或开始录制时调用）。返回 false = 缺输入监控权限。
    @discardableResult
    func start(requestIfNeeded: Bool = true) -> Bool {
        permissionDenied = false
        // CGEvent.tapCreate 无权限时也可能返回非 nil 但收不到事件，故先用 preflight 判定
        if !PermissionCenter.inputMonitoringGranted(), requestIfNeeded {
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

    /// requestIfNeeded=false 时不主动申请权限（无权限则监听静默不可用），
    /// 供点击记录在「点击标记关闭」时也能复用已有权限工作。
    func beginCapture(requestIfNeeded: Bool = true) {
        capturing = true
        start(requestIfNeeded: requestIfNeeded)
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
        // 点击记录（自动聚焦）始终工作；箭头标记只在用户开启「点击标记」时出现
        guard capturing, isMonitoring, AppSettings.shared.clickIndicatorEnabled else { return }
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
