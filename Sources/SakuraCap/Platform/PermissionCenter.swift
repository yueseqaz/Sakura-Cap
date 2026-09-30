import AppKit
import AVFoundation
import CoreGraphics

/// 三类权限的检测与系统设置深链：
/// 屏幕录制（TCC ScreenCapture）、麦克风（TCC Microphone）、输入监控（TCC ListenEvent）。
enum PermissionCenter {
    // MARK: - 检测

    static func screenCaptureGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var microphoneDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied
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
    static func openInputMonitoringSettings() { openPrivacyPane("Privacy_ListenEvent") }
}
