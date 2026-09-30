import Foundation

/// 通过 macOS「快捷指令」切换专注模式（即旧称「勿扰模式」）。
/// 系统没有提供公开 API 直接开关专注模式，因此约定：用户在「快捷指令」App 里
/// 各建一个「设置专注模式 → 打开 / 关闭」的快捷指令，录制开始/结束时由这里调起。
enum FocusMode {
    static func run(shortcut: String) {
        let name = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            Log.app.error("运行快捷指令失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}
