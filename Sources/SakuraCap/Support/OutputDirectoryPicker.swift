import AppKit

/// 输出目录：必须由用户选择（产品要求，无内置默认目录）。
enum OutputDirectoryPicker {
    /// 已选且可写 → 直接用；否则弹出目录选择器。取消返回 nil。
    @MainActor
    static func ensureDirectory(current: URL?) -> URL? {
        if let current,
           FileManager.default.fileExists(atPath: current.path, isDirectory: nil),
           FileManager.default.isWritableFile(atPath: current.path) {
            return current
        }
        return pick()
    }

    @MainActor
    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择 Sakura-Cap 录制文件的保存目录"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
