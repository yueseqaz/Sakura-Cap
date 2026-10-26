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
              == "Sakura-Cap-\(version).dmg", "Select only DMG regardless of API order")
        check(UpdatePackage.preferredAsset(in: [assets[0]], version: version) == nil,
              "Reject ZIP-only releases")
        check(UpdatePackage.preferredAsset(in: [assets[1]], version: version) != nil,
              "Support DMG-only releases")
        check(UpdatePackage.preferredAsset(in: assets, version: "999.0.0") == nil,
              "Do not choose assets for another version")

        let hash = String(repeating: "a", count: 64)
        let cask = """
        cask "sakura-cap" do
          version "\(version)"
          sha256 "\(hash)"
          url "https://github.com/yueseqaz/Sakura-Cap/releases/download/v#{version}/Sakura-Cap-#{version}.dmg"
        end
        """
        let parsed = UpdatePackage.caskRelease(cask)
        check(parsed?.url.pathExtension == "dmg", "Parse the DMG download URL")
        check(parsed?.digest == "sha256:\(hash)" && parsed?.version == version,
              "Parse the Cask version and hash")
        check(UpdatePackage.caskRelease(cask.replacingOccurrences(of: hash, with: "invalid")) == nil,
              "Reject invalid checksums")
        check(UpdatePackage.caskRelease(cask.replacingOccurrences(of: "github.com", with: "example.com")) == nil,
              "Reject unexpected package hosts")
        check(UpdatePackage.caskRelease(cask.replacingOccurrences(of: ".dmg", with: ".zip")) == nil,
              "Reject ZIP Casks even with a valid checksum")
        let currentCask = try String(contentsOfFile: "Casks/sakura-cap.rb", encoding: .utf8)
        check(UpdatePackage.caskRelease(currentCask) != nil, "Keep published Cask fallback working")

        let extraction = work.appendingPathComponent("work")
        let destination = work.appendingPathComponent("staged.app")
        try UpdatePackage.stage(archive: archive, work: extraction, destination: destination, version: version)
        check(Bundle(url: destination)?.bundleIdentifier == "com.sakura.sakuracap",
              "Stage the correct application from DMG")
        try run("/usr/bin/codesign", ["--verify", "--strict", "--deep", destination.path])
        checks += 1
        let nested = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        check(nested == ["Contents"], "Do not copy DMG guide, background, or Applications shortcut into the app")
        let contents = try FileManager.default.contentsOfDirectory(atPath:
            extraction.appendingPathComponent("extracted").path)
        check(contents.isEmpty, "DMG must be unmounted after staging")

        let unsupported = work.appendingPathComponent("unsupported")
        let zipDestination = work.appendingPathComponent("zip.app")
        do {
            try UpdatePackage.stage(archive: work.appendingPathComponent("update.zip"), work: unsupported,
                                    destination: zipDestination, version: version)
            preconditionFailure("ZIP staging must fail")
        } catch {
            check(!FileManager.default.fileExists(atPath: unsupported.path),
                  "Reject ZIP before creating an extraction directory")
            check(!FileManager.default.fileExists(atPath: zipDestination.path),
                  "Rejected ZIP must not stage an app")
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
