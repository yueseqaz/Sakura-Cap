import Foundation

/// Shared package selection and extraction, independent of the update UI.
enum UpdatePackage {
    static func preferredAsset(in assets: [[String: Any]], version: String) -> [String: Any]? {
        for ext in ["dmg", "zip"] {
            if let asset = assets.first(where: { $0["name"] as? String == "Sakura-Cap-\(version).\(ext)" }) {
                return asset
            }
        }
        return nil
    }

    static func caskRelease(_ text: String) -> (version: String, url: URL, digest: String)? {
        func quoted(_ key: String) -> String? {
            for rawLine in text.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                let prefix = key + " \""
                if line.hasPrefix(prefix), let end = line.dropFirst(prefix.count).firstIndex(of: "\"") {
                    return String(line[line.index(line.startIndex, offsetBy: prefix.count)..<end])
                }
            }
            return nil
        }
        guard let version = quoted("version"),
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              let hash = quoted("sha256"),
              hash.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil,
              let template = quoted("url"),
              let url = URL(string: template.replacingOccurrences(of: "#{version}", with: version)),
              ["dmg", "zip"].contains(url.pathExtension.lowercased()),
              url.absoluteString == "https://github.com/yueseqaz/Sakura-Cap/releases/download/v\(version)/Sakura-Cap-\(version).\(url.pathExtension)" else {
            return nil
        }
        // Read the URL as well as the hash: a DMG hash must never validate a ZIP.
        return (version, url, "sha256:\(hash)")
    }

    static func stage(archive: URL, work: URL, destination: URL, version: String) throws {
        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        var mounted = false
        defer {
            if mounted {
                if (try? run("/usr/bin/hdiutil", ["detach", extracted.path, "-quiet"])) == nil {
                    try? run("/usr/bin/hdiutil", ["detach", extracted.path, "-force", "-quiet"])
                }
            }
        }
        switch archive.pathExtension.lowercased() {
        case "dmg":
            try run("/usr/bin/hdiutil", ["attach", archive.path, "-readonly", "-nobrowse", "-noautoopen",
                                       "-mountpoint", extracted.path, "-quiet"])
            mounted = true
        case "zip":
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        default:
            throw PackageError.invalidPackage
        }
        let unpacked = extracted.appendingPathComponent("Sakura-Cap.app")
        guard (try unpacked.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              let bundle = Bundle(url: unpacked),
              bundle.bundleIdentifier == "com.sakura.sakuracap",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              FileManager.default.fileExists(atPath: unpacked.appendingPathComponent("Contents/MacOS/SakuraCap").path) else {
            throw PackageError.invalidPackage
        }
        try run("/usr/bin/codesign", ["--verify", "--strict", "--deep", unpacked.path])
        do { try FileManager.default.copyItem(at: unpacked, to: destination) }
        catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PackageError.invalidPackage }
    }

    private enum PackageError: LocalizedError {
        case invalidPackage
        var errorDescription: String? { L("更新包下载或校验失败") }
    }
}
