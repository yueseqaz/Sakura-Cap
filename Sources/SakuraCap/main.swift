import AppKit

// Sakura-Cap 入口：无 Dock 图标（LSUIElement + accessory policy），全部 UI 挂在状态栏。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // accessory 应用没有主菜单时，文本框收不到 ⌘C/⌘V/⌘X/⌘A（按键等价经主菜单派发到
    // 第一响应者）。装一个仅含标准编辑命令的极简主菜单；nil target 自动路由。
    // 刻意不含撤销/重做：⌘Z 被工作台窗口用于剪辑撤销，不能在这里被菜单截走。
    app.mainMenu = {
        let edit = NSMenu()
        edit.addItem(withTitle: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("全选"), action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.title = L("编辑")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        return main
    }()
    app.run()
}
