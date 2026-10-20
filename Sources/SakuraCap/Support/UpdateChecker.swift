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
        let assetURL: URL?
        let digest: String?
    }

    static func check(manual: Bool) {
        Task {
            do {
                var release = try await fetchLatest()
                let newer = compare(release.version, AppInfo.version) > 0
                if (newer || manual), release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    release = Release(version: release.version, pageURL: release.pageURL,
                                      notes: (try? await fetchNotes(version: release.version)) ?? "",
                                      assetURL: release.assetURL, digest: release.digest)
                }
                if newer {
                    presentAvailable(release)
                } else if manual {
                    presentUpToDate(release)
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
        let asset = (json["assets"] as? [[String: Any]])?.first {
            ($0["name"] as? String) == "Sakura-Cap-\(version).zip"
        }
        return Release(version: version, pageURL: pageURL, notes: json["body"] as? String ?? "",
                       assetURL: (asset?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                       digest: asset?["digest"] as? String)
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
        let version = String(tag.dropFirst())
        let asset = URL(string: "https://github.com/yueseqaz/Sakura-Cap/releases/download/v\(version)/Sakura-Cap-\(version).zip")
        return Release(version: version, pageURL: finalURL, notes: "", assetURL: asset, digest: nil)
    }

    private static func fetchNotes(version: String) async throws -> String {
        guard version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://raw.githubusercontent.com/yueseqaz/Sakura-Cap/v\(version)/ReleaseNotes/\(version).md") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000,
              let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotParseResponse) }
        return text
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

    // MARK: - 更新页面

    private static func presentAvailable(_ release: Release) {
        UpdateReleaseWindow.show(version: release.version, notes: release.notes, isNewer: true,
                                 pageURL: release.pageURL) {
            guard let assetURL = release.assetURL else { return }
            UpdateInstaller.install(from: assetURL, version: release.version, digest: release.digest,
                                    pageURL: release.pageURL)
        }
    }

    private static func presentUpToDate(_ release: Release) {
        UpdateReleaseWindow.show(version: release.version, notes: release.notes, isNewer: false,
                                 pageURL: release.pageURL, onInstall: {})
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("检查更新失败")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L("好"))
        runModalAlert(alert)
    }
}
