import AppKit
import Foundation

/// 检查更新：读取 GitHub Releases 里最新版本，和当前版本做语义化比较。
/// 手动检查时无论结果都会提示；后台静默检查只在发现新版本时提示。
@MainActor
enum UpdateChecker {
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/yueseqaz/Sakura-Cap/releases/latest")!

    private struct Release {
        let version: String
        let pageURL: URL?
        let notes: String
    }

    static func check(manual: Bool) {
        Task {
            do {
                let release = try await fetchLatest()
                if compare(release.version, AppInfo.version) > 0 {
                    presentAvailable(release)
                } else if manual {
                    presentUpToDate()
                }
            } catch {
                Log.app.error("检查更新失败: \(error.localizedDescription, privacy: .public)")
                if manual { presentError(error) }
            }
        }
    }

    // MARK: - 网络

    /// 优先用 GitHub API（能拿到更新说明）；被限流/失败时退回 releases/latest 重定向（无速率限制）。
    private static func fetchLatest() async throws -> Release {
        if let release = try? await fetchFromAPI() { return release }
        return try await fetchFromRedirect()
    }

    private static func fetchFromAPI() async throws -> Release {
        var request = URLRequest(url: latestReleaseAPI)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sakura-Cap/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let pageURL = (json["html_url"] as? String).flatMap { URL(string: $0) }
        return Release(version: version, pageURL: pageURL, notes: json["body"] as? String ?? "")
    }

    /// 读取 `github.com/owner/repo/releases/latest` 跳转后的地址，取出 `vX.Y.Z`。
    private static func fetchFromRedirect() async throws -> Release {
        let url = URL(string: "https://github.com/yueseqaz/Sakura-Cap/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Sakura-Cap/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let finalURL = response.url, let tag = finalURL.pathComponents.last, tag.hasPrefix("v") else {
            throw URLError(.cannotParseResponse)
        }
        return Release(version: String(tag.dropFirst()), pageURL: finalURL, notes: "")
    }

    /// 语义化比较：a > b 返回正数，相等返回 0，否则负数。忽略非数字后缀。
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    // MARK: - 弹窗

    private static func presentAvailable(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = String(format: L("发现新版本 v%@"), release.version)
        var text = String(format: L("当前版本 v%@，已发布新版本。"), AppInfo.version)
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            text += "\n\n" + String(notes.prefix(400))
        }
        alert.informativeText = text
        alert.addButton(withTitle: L("前往下载"))
        alert.addButton(withTitle: L("稍后"))
        if runModalAlert(alert) == .alertFirstButtonReturn, let url = release.pageURL {
            NSWorkspace.shared.open(url)
        }
    }

    private static func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = L("已是最新版本")
        alert.informativeText = String(format: L("当前版本 v%@。"), AppInfo.version)
        alert.addButton(withTitle: L("好"))
        runModalAlert(alert)
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("检查更新失败")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L("好"))
        runModalAlert(alert)
    }
}
