import Foundation

/// macOS 没有公开的专注模式开关 API；通过用户创建的快捷指令切换。
enum FocusMode {
    enum Failure: LocalizedError {
        case missing(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name):
                return String(format: L("找不到快捷指令「%@」。请在「快捷指令」App 中创建并核对名称。"), name)
            case .failed(let reason):
                return String(format: L("切换勿扰模式失败：%@"), reason)
            }
        }
    }

    static func run(shortcut: String) async throws {
        let name = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.missing(shortcut) }
        try await Task.detached(priority: .userInitiated) {
            let list = try execute(["list"])
            guard list.split(whereSeparator: \Character.isNewline).contains(where: { $0 == name }) else {
                throw Failure.missing(name)
            }
            _ = try execute(["run", name])
        }.value
    }

    private static func execute(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw Failure.failed(text.isEmpty ? "shortcuts exit \(process.terminationStatus)" : text)
        }
        return text
    }
}
