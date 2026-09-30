import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class PanelViewModel: ObservableObject {
    let controller: RecordingController

    var requestClosePanel: (() -> Void)?
    var requestOpenPanel: (() -> Void)?

    @Published var regionSummary = "尚未框选"
    @Published var settingsSection = "general"

    init(controller: RecordingController) {
        self.controller = controller
    }

    func appear() {
        refreshRegionSummary()
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

    func refreshContent() {
        guard PermissionCenter.screenCaptureGranted() else { return }
        Task { _ = try? await DisplayCatalog.shared.refresh() }
    }

    func toggleRecord() {
        if controller.isBusy {
            controller.stop()
        } else {
            requestClosePanel?()
            controller.start()
        }
    }

    /// 设置面板入口：只框选区域，选完直接开录（回调由 AppDelegate 统一接线）
    func pickRegion() {
        requestClosePanel?()
        SelectionController.shared.begin(.regionOnly)
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

    func refreshRegionSummary() {
        guard let region = AppSettings.shared.lastRegion else {
            regionSummary = "尚未框选"
            return
        }
        let name = NSScreen.screens.first { $0.displayID == region.displayID }?.localizedName
            ?? "显示器 \(region.displayID)"
        regionSummary = "\(Int(region.sckRect.width)) × \(Int(region.sckRect.height)) · \(name)"
    }
}
