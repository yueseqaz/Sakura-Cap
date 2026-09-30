import AppKit

/// 弹出模态弹窗，并把弹窗窗口层级抬到最上层——否则会被标注覆盖层挡住而点不到。
@MainActor
@discardableResult
func runModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
    alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 10)
    return alert.runModal()
}
