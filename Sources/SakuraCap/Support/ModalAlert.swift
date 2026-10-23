import AppKit

/// 弹出模态弹窗，并把弹窗窗口层级抬到最上层——否则会被标注覆盖层挡住而点不到。
@MainActor
@discardableResult
func runModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
    alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 10)
    return alert.runModal()
}

/// 文字识别引擎本身出错时给出可操作的提示。
/// 典型场景：macOS 26/27 的 TextRecognition 走 ANE（E5RT），系统运行库异常时
/// 所有 `.accurate` 识别都会失败，日志里是 `TextRecognition.CRImageReaderError`，
/// 重启应用或电脑后恢复。
@MainActor
func showOCRFailureAlert(_ error: Error) {
    let ns = error as NSError
    let alert = NSAlert()
    alert.messageText = L("文字识别暂时不可用")
    alert.informativeText = String(
        format: L("系统文字识别服务异常（%@ %ld）。\n请重启 Sakura-Cap；如果仍失败，重启电脑后通常可以恢复。"),
        ns.domain, ns.code
    )
    alert.addButton(withTitle: L("好"))
    runModalAlert(alert)
}
