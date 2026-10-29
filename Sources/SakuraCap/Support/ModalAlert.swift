import AppKit

/// Prefer a sheet on the owning document. Only capture-overlay alerts need a
/// special level; ordinary confirmations must not float above unrelated apps.
@MainActor
@discardableResult
func runModalAlert(_ alert: NSAlert, for owner: NSWindow? = nil) -> NSApplication.ModalResponse {
    let parent = owner ?? NSApp.keyWindow
    if let parent, parent.isVisible, parent.styleMask.contains(.titled),
       parent.level < .screenSaver, parent.attachedSheet == nil, NSApp.modalWindow == nil {
        alert.beginSheetModal(for: parent) { response in
            NSApp.stopModal(withCode: response)
        }
        return NSApp.runModal(for: alert.window)
    }
    let originalLevel = alert.window.level
    var levelObserver: NSObjectProtocol?
    defer {
        if let levelObserver { NotificationCenter.default.removeObserver(levelObserver) }
        alert.window.level = originalLevel
    }
    if let parent, parent.isVisible, parent.level >= .screenSaver {
        let level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
        alert.window.level = level
        // NSAlert resets the level to modalPanel when runModal starts. Elevate
        // after it becomes key, and only for the lifetime of this overlay alert.
        levelObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                               object: alert.window, queue: .main) { _ in
            MainActor.assumeIsolated { alert.window.level = level }
        }
    } else {
        alert.window.level = .modalPanel
    }
    return alert.runModal()
}

/// 文字识别引擎本身出错时给出可操作的提示。
/// 典型场景：macOS 26/27 的 TextRecognition 走 ANE（E5RT），系统运行库异常时
/// 所有 `.accurate` 识别都会失败，日志里是 `TextRecognition.CRImageReaderError`，
/// 重启应用或电脑后恢复。
@MainActor
func showOCRFailureAlert(_ error: Error, for owner: NSWindow? = nil) {
    let ns = error as NSError
    let alert = NSAlert()
    alert.messageText = L("文字识别暂时不可用")
    alert.informativeText = String(
        format: L("系统文字识别服务异常（%@ %ld）。\n请重启 Sakura-Cap；如果仍失败，重启电脑后通常可以恢复。"),
        ns.domain, ns.code
    )
    alert.addButton(withTitle: L("好"))
    runModalAlert(alert, for: owner)
}
