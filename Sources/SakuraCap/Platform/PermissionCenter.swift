import AppKit
import AVFoundation
import CoreGraphics

/// 三类权限的检测与系统设置深链：
/// 屏幕录制（TCC ScreenCapture）、麦克风（TCC Microphone）、输入监控（TCC ListenEvent）。
enum PermissionCenter {
    enum AccessState: Equatable {
        case authorized, notDetermined, denied, restricted

        var isAuthorized: Bool { self == .authorized }
    }

    static func accessState(_ status: AVAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    static var cameraAccess: AccessState {
        accessState(AVCaptureDevice.authorizationStatus(for: .video))
    }

    static var microphoneAccess: AccessState {
        accessState(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    // MARK: - 检测

    static func screenCaptureGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var microphoneDenied: Bool {
        microphoneAccess == .denied || microphoneAccess == .restricted
    }

    static var microphoneUndetermined: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    // MARK: - 系统设置深链

    static func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openScreenCaptureSettings() { openPrivacyPane("Privacy_ScreenCapture") }
    static func openMicrophoneSettings() { openPrivacyPane("Privacy_Microphone") }
    static func openCameraSettings() { openPrivacyPane("Privacy_Camera") }
    static func openInputMonitoringSettings() { openPrivacyPane("Privacy_ListenEvent") }

    // MARK: - 输入监控（ListenEvent，全局键盘/鼠标监听）

    /// 是否已获得「输入监控」权限。注意：CGEvent.tapCreate 在无权限时也可能返回非 nil，
    /// 但 tap 收不到任何事件——必须用 preflight 判定。
    static func inputMonitoringGranted() -> Bool { CGPreflightListenEventAccess() }

    /// 请求「输入监控」权限：首次弹系统授权框；已拒绝则不再弹（需去系统设置手动勾选）
    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }
}
