import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class PanelViewModel: ObservableObject {
    let controller: RecordingController

    @Published var settingsSection = "general"
    @Published private(set) var permissionRefreshToken = UUID()

    init(controller: RecordingController) {
        self.controller = controller
    }

    func appear() {
        refreshPermissions()
        if PermissionCenter.screenCaptureGranted() {
            refreshContent()
        }
        // 麦克风权限不在打开面板/启动时申请：
        // 1) 开录且勾选麦克风时由 RecordingController 在 startMicrophoneAndGetFormat 里申请；
        // 2) 用户在面板/HUD 主动打开麦克风开关时由对应开关申请。
        // 这里只读状态做展示，避免每次启动弹 TCC 窗、点完还会把菜单顶掉。
    }

    func refreshPermissions() {
        CameraPiP.shared.refreshPermissionStatus()
        permissionRefreshToken = UUID()
    }

    func refreshContent() {
        guard PermissionCenter.screenCaptureGranted() else { return }
        Task { _ = try? await DisplayCatalog.shared.refresh() }
    }

    func chooseOutputDirectory() {
        if let url = OutputDirectoryPicker.pick() {
            AppSettings.shared.outputDirectory = url
        }
    }

    func ensureMicrophonePermission() {
        guard PermissionCenter.microphoneUndetermined else { return }
        StatusItemController.holdSettingsOnDesktop()
        PermissionCenter.requestMicrophone { [weak self] granted in
            Task { @MainActor in
                if !granted {
                    AppSettings.shared.recordMicrophone = false
                }
                self?.objectWillChange.send()
                StatusItemController.releaseSettingsFromDesktop()
            }
        }
    }
}
