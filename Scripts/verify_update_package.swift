import AppKit

func L(_ key: String) -> String { key }

@main
enum UpdatePackageChecks {
    private static var checks = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func main() throws {
        let archive = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = URL(fileURLWithPath: CommandLine.arguments[2])
        let version = Bundle(url: app)!.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let background = NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/DMGBackground.tiff"))!
        check(abs(background.size.width - 770) < 1 && abs(background.size.height - 421.4) < 1,
              "Installer art must display at the compact proportional size")
        let pixels = background.representations.first!
        check(pixels.pixelsWide == 1100 && pixels.pixelsHigh == 602,
              "Preserve the complete original image without cropping or resampling")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sakura-update-test-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let assets = ["zip", "dmg"].map { ["name": "Sakura-Cap-\(version).\($0)"] }
        check(UpdatePackage.preferredAsset(in: assets, version: version)?["name"] as? String
              == "Sakura-Cap-\(version).dmg", "Prefer DMG regardless of API order")
        check(UpdatePackage.preferredAsset(in: [assets[0]], version: version)?["name"] as? String
              == "Sakura-Cap-\(version).zip", "Support old ZIP-only releases")
        check(UpdatePackage.preferredAsset(in: assets, version: "999.0.0") == nil,
              "Do not choose assets for another version")

        let hash = String(repeating: "a", count: 64)
        for ext in ["zip", "dmg"] {
            let cask = """
            cask "sakura-cap" do
              version "\(version)"
              sha256 "\(hash)"
              url "https://github.com/yueseqaz/Sakura-Cap/releases/download/v#{version}/Sakura-Cap-#{version}.\(ext)"
            end
            """
            let parsed = UpdatePackage.caskRelease(cask)
            check(parsed?.url.pathExtension == ext, "Cask digest must match the actual package format")
            check(parsed?.digest == "sha256:\(hash)" && parsed?.version == version,
                  "Parse the Cask version and hash")
            check(UpdatePackage.caskRelease(cask.replacingOccurrences(of: hash, with: "invalid")) == nil,
                  "Reject invalid checksums")
            check(UpdatePackage.caskRelease(cask.replacingOccurrences(of: "github.com", with: "example.com")) == nil,
                  "Reject unexpected package hosts")
        }
        let currentCask = try String(contentsOfFile: "Casks/sakura-cap.rb", encoding: .utf8)
        check(UpdatePackage.caskRelease(currentCask) != nil, "Keep published Cask fallback working")

        let zip = work.appendingPathComponent("legacy.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        for (index, package) in [archive, zip].enumerated() {
            let extraction = work.appendingPathComponent("work-\(index)")
            let destination = work.appendingPathComponent("staged-\(index).app")
            try UpdatePackage.stage(archive: package, work: extraction, destination: destination, version: version)
            check(Bundle(url: destination)?.bundleIdentifier == "com.sakura.sakuracap",
                  "Stage the correct application from \(package.pathExtension)")
            try run("/usr/bin/codesign", ["--verify", "--strict", "--deep", destination.path])
            checks += 1
            let nested = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
            check(nested == ["Contents"], "Do not copy DMG guide, background, or Applications shortcut into the app")
            check((try? FileManager.default.contentsOfDirectory(atPath: extraction.appendingPathComponent("extracted").path))?
                .isEmpty == (package.pathExtension == "dmg"), "DMG must be unmounted after staging")
        }
        let rejected = work.appendingPathComponent("rejected.app")
        do {
            try UpdatePackage.stage(archive: archive, work: work.appendingPathComponent("wrong-version"),
                                    destination: rejected, version: "999.0.0")
            preconditionFailure("Version mismatch must fail")
        } catch {
            check(!FileManager.default.fileExists(atPath: rejected.path), "Failed validation must not stage an app")
            let contents = try FileManager.default.contentsOfDirectory(atPath:
                work.appendingPathComponent("wrong-version/extracted").path)
            check(contents.isEmpty,
                  "DMG must be unmounted even after validation failure")
        }
        print("Update package regressions passed: \(checks) assertions")
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "Command failed: \(path)")
    }
}
