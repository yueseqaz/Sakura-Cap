import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// 音频提取：选一个视频文件，把音轨导出为 m4a，存到输出目录并在 Finder 显示。
@MainActor
enum AudioExtractTool {
    static func pickAndExtract() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audiovisualContent]
        panel.allowsMultipleSelection = false
        panel.message = L("选择要提取音频的视频")
        panel.prompt = L("提取")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await extract(from: url) }
    }

    static func extract(from url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio), !audioTracks.isEmpty else {
            Toast.show(title: L("未找到音轨"), detail: url.lastPathComponent)
            return
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            Toast.show(title: L("无法开始提取"), detail: nil)
            return
        }
        guard let dir = OutputDirectoryPicker.ensureDirectory(current: AppSettings.shared.outputDirectory) else { return }

        // 输出文件名：源文件名 - 音频.m4a，重名自动追加序号，绝不覆盖
        let baseName = url.deletingPathExtension().lastPathComponent
        let suffix = L("音频")
        var output = dir.appendingPathComponent("\(baseName) - \(suffix).m4a")
        var counter = 2
        while FileManager.default.fileExists(atPath: output.path) {
            output = dir.appendingPathComponent("\(baseName) - \(suffix) \(counter).m4a")
            counter += 1
        }

        Toast.show(title: L("正在提取音频…"), detail: url.lastPathComponent)
        session.outputURL = output
        session.outputFileType = .m4a
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        switch session.status {
        case .completed:
            NSWorkspace.shared.activateFileViewerSelecting([output])
            Toast.show(title: L("音频已导出"), detail: output.lastPathComponent)
        default:
            let message = session.error?.localizedDescription ?? L("未知错误")
            Log.app.error("音频提取失败: \(message, privacy: .public)")
            Toast.show(title: L("提取失败"), detail: message)
        }
    }
}
