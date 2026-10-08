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
        if AppSettings.shared.recordMicrophone {
            ensureMicrophonePermission()
        }
        if AppSettings.shared.clickIndicatorEnabled {
            IndicatorEngine.shared.start()
        }
        if AppSettings.shared.keyDisplayEnabled {
            KeyDisplay.shared.start()
        }
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
        PermissionCenter.requestMicrophone { [weak self] granted in
            Task { @MainActor in
                if !granted {
                    AppSettings.shared.recordMicrophone = false
                }
                self?.objectWillChange.send()
            }
        }
    }
}
