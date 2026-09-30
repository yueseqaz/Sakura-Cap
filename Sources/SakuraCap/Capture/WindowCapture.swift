import AppKit
import ScreenCaptureKit

/// 待录制的窗口过滤器：由系统共享选择器（SCContentSharingPicker）选中后暂存，
/// 下一次开始录制时由 StreamPlanner 消费。
@MainActor
final class WindowCaptureStore {
    static let shared = WindowCaptureStore()
    private var pending: SCContentFilter?
    private var pendingName: String = ""

    func set(_ filter: SCContentFilter, name: String) {
        pending = filter
        pendingName = name
    }

    func consume() -> (filter: SCContentFilter, name: String)? {
        defer { pending = nil; pendingName = "" }
        guard let pending else { return nil }
        return (pending, pendingName)
    }

    var hasPending: Bool { pending != nil }
}

/// 系统共享选择器：让用户选一个窗口来录制（macOS 14+）。
@available(macOS 14.0, *)
@MainActor
final class WindowPicker: NSObject, @preconcurrency SCContentSharingPickerObserver {
    static let shared = WindowPicker()
    var onPicked: (() -> Void)?

    func present() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        picker.configuration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
                              for stream: SCStream?) {
        picker.isActive = false
        picker.remove(self)
        WindowCaptureStore.shared.set(filter, name: L("窗口"))
        onPicked?()
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        picker.isActive = false
        picker.remove(self)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        SCContentSharingPicker.shared.isActive = false
        Log.app.error("共享选择器启动失败: \(error.localizedDescription, privacy: .public)")
    }
}
