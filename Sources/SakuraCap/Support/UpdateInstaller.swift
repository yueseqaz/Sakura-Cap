import AppKit
import CryptoKit
import Foundation

@MainActor
enum UpdateInstaller {
    private static var progressWindow: NSWindow?

    static func install(from assetURL: URL, version: String, digest: String?, pageURL: URL?) {
        guard progressWindow == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 110),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = L("正在更新 Sakura-Cap")
        WindowPresentation.configure(window, allowsPinning: false)
        let label = NSTextField(labelWithString: L("正在下载并验证更新，请稍候…"))
        label.frame = NSRect(x: 22, y: 65, width: 306, height: 22)
        let indicator = NSProgressIndicator(frame: NSRect(x: 22, y: 32, width: 306, height: 16))
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(indicator)
        window.center()
        window.orderFront(nil)
        progressWindow = window

        Task {
            do {
                let staged = try await prepare(assetURL: assetURL, version: version, digest: digest)
                let alert = NSAlert()
                alert.messageText = L("更新已准备好")
                alert.informativeText = L("退出并重启 Sakura-Cap 以完成安装？")
                alert.addButton(withTitle: L("重启并安装"))
                alert.addButton(withTitle: L("取消"))
                progressWindow?.close()
                progressWindow = nil
                if runModalAlert(alert) == .alertFirstButtonReturn {
                    do { try launchHelper(staged: staged) }
                    catch {
                        try? FileManager.default.removeItem(at: staged)
                        throw error
                    }
                    NSApp.terminate(nil)
                } else {
                    try? FileManager.default.removeItem(at: staged)
                }
            } catch {
                progressWindow?.close()
                progressWindow = nil
                let alert = NSAlert()
                alert.messageText = L("自动更新失败")
                alert.informativeText = error.localizedDescription + "\n" + L("可以从发布页手动下载。")
                alert.addButton(withTitle: L("查看发布页"))
                alert.addButton(withTitle: L("好"))
                if runModalAlert(alert) == .alertFirstButtonReturn, let pageURL {
                    NSWorkspace.shared.open(pageURL)
                }
            }
        }
    }

    private static func prepare(assetURL: URL, version: String, digest: String?) async throws -> URL {
        guard assetURL.scheme == "https", version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#,
                                                       options: .regularExpression) != nil,
              assetURL.pathExtension.lowercased() == "dmg" else {
            throw UpdateError.invalidPackage
        }
        // 应用为 ad-hoc 签名，codesign 只能证明包完整、无法 pin 开发者身份，
        // sha256 摘要是唯一强校验：缺失即拒绝自动安装（GitHub API 限流回退路径拿不到 digest）。
        guard let digest, digest.hasPrefix("sha256:") else {
            throw UpdateError.missingDigest
        }
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard app.pathExtension == "app", app.lastPathComponent == "Sakura-Cap.app" else {
            throw UpdateError.invalidLocation
        }
        let parent = app.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".Sakura-Cap-update-\(UUID().uuidString).app")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("Sakura-Cap-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 120
        let (download, response) = try await URLSession.shared.download(for: request)
        let size = (try FileManager.default.attributesOfItem(atPath: download.path)[.size] as? NSNumber)?.intValue ?? 0
        guard (response as? HTTPURLResponse)?.statusCode == 200, size > 0, size < 500_000_000 else {
            throw UpdateError.invalidPackage
        }
        let archive = work.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: download, to: archive)
        try await Task.detached(priority: .utility) {
            guard SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe))
                .map { String(format: "%02x", $0) }.joined() == String(digest.dropFirst(7)).lowercased() else {
                throw UpdateError.invalidPackage
            }
            try UpdatePackage.stage(archive: archive, work: work, destination: staging, version: version)
        }.value
        return staging
    }

    private static func launchHelper(staged: URL) throws {
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let backup = app.deletingLastPathComponent()
            .appendingPathComponent(".Sakura-Cap-backup-\(UUID().uuidString).app")
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        /bin/mv "$2" "$4" || exit 1
        if /bin/mv "$3" "$2" && /usr/bin/open "$2"; then
            /bin/rm -rf "$4"
        else
            if test -e "$2"; then /bin/mv "$2" "$3"; fi
            /bin/mv "$4" "$2"
            /usr/bin/open "$2"
            exit 1
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sakura-updater", String(ProcessInfo.processInfo.processIdentifier),
                             app.path, staged.path, backup.path]
        try process.run()
    }

    private enum UpdateError: LocalizedError {
        case invalidPackage, invalidLocation, missingDigest
        var errorDescription: String? {
            switch self {
            case .invalidPackage: return L("更新包下载或校验失败")
            case .invalidLocation: return L("无法在当前安装位置自动更新")
            case .missingDigest: return L("更新包缺少 sha256 校验值，为安全起见已取消自动安装")
            }
        }
    }
}
