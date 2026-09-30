import AppKit

// Sakura-Cap 入口：无 Dock 图标（LSUIElement + accessory policy），全部 UI 挂在状态栏。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
