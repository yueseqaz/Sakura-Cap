// Website photography uses the real production views, an isolated bundle/defaults domain,
// and native view readback. Never capture the physical display or another process.
import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
final class WebsiteCapture: NSObject, NSApplicationDelegate {
    private static var delegate: WebsiteCapture?
    private var desktop: CGImage!
    private var backdrop: NSWindow!
    private var target: NSWindow?
    private var scene = "inline"
    private var root: URL!
    private var media: URL!
    private var output: URL!
    private var recorder = RecordingController()
    private var hud: RecordingHUDController!
    private var videoWindow: NSWindow?
    private var switching = false

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WebsiteCapture()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        media = root.appendingPathComponent("build/website-capture/media", isDirectory: true)
        output = root.appendingPathComponent("docs/assets/screenshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let screen = NSScreen.main!
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CocoaError(.fileReadUnknown)
            }
            let size = CGSize(width: screen.frame.width * 2, height: screen.frame.height * 2)
            let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
            let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.draw(image, in: CGRect(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2,
                                           width: drawSize.width, height: drawSize.height))
            desktop = context.makeImage()!
            try writePNG(desktop, to: media.appendingPathComponent("桌面.png"))
            try preparePhotos()
            backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            backdrop.isReleasedWhenClosed = false
            backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = NSImageView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.image = NSImage(cgImage: desktop, size: screen.frame.size)
            view.imageScaling = .scaleAxesIndependently
            backdrop.contentView = view
            backdrop.orderFrontRegardless()
            NSApp.appearance = NSAppearance(named: .aqua)
            hud = RecordingHUDController(controller: recorder)
            makeMenu()
            Task { await showScene(1) }
        } catch {
            print("Cannot prepare private-safe website photography: \(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    private func makeMenu() {
        let menu = NSMenu()
        let app = NSMenuItem(title: "Sakura-Cap", action: nil, keyEquivalent: "")
        let actions = NSMenu()
        for (index, title) in ["原地标注", "图片标注", "图片拼接", "视频剪辑", "图片格式转换", "录制准备"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(sceneTapped(_:)), keyEquivalent: "\(index + 1)")
            item.target = self
            item.tag = index + 1
            actions.addItem(item)
        }
        actions.addItem(.separator())
        let save = NSMenuItem(title: "保存官网截图", action: #selector(captureTapped), keyEquivalent: "p")
        save.keyEquivalentModifierMask = [.command, .shift]
        save.target = self
        actions.addItem(save)
        actions.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = actions
        menu.addItem(app)
        NSApp.mainMenu = menu
    }

    @objc private func sceneTapped(_ sender: NSMenuItem) { Task { await showScene(sender.tag) } }

    private func showScene(_ number: Int) async {
        guard !switching else { return }
        switching = true
        defer { switching = false }
        InlineScreenshotController.shared.close()
        recorder.cancelArmed()
        for window in NSApp.windows where window !== backdrop { window.orderOut(nil) }
        target = nil
        let screen = NSScreen.main!
        switch number {
        case 1:
            scene = "inline"
            InlineScreenshotController.shared.present(snapshots: [(screen, desktop)], intent: .regionOnly,
                pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView is InlineScreenshotView }),
               let view = window.contentView as? InlineScreenshotView {
                view.setSelection(CGRect(x: screen.frame.width * 0.15, y: screen.frame.height * 0.15,
                                         width: screen.frame.width * 0.68, height: screen.frame.height * 0.66))
                target = window
            }
        case 2:
            scene = "editor"
            AnnotationEditorController.shared.open(image: desktop, suggestedName: "桌面截图", source: .newCapture)
            target = NSApp.windows.first { $0.isVisible && $0 is AnnotationEditorWindow }
        case 3:
            scene = "stitch"
            ImageStitchToolController.shared.show()
            target = NSApp.windows.first { $0.title == L("图片拼接") && $0.isVisible }
            if let canvas = descendants(target!.contentView!).compactMap({ $0 as? StitchCanvasView }).first {
                let images = ["原生壁纸 01.png", "原生壁纸 02.png"].compactMap { try? StitchRenderer.load(media.appendingPathComponent($0)) }
                var document = StitchDocument(background: .white)
                document.append(images, gap: 24)
                for index in document.images.indices {
                    document.images[index].frame.size = CGSize(width: 720, height: 450)
                }
                document.arrange(vertical: false, gap: 24)
                canvas.document = document
                canvas.selectedID = images.last?.id
                if let field = descendants(target!.contentView!).compactMap({ $0 as? NSTextField })
                    .first(where: { $0.identifier?.rawValue == "stitchGap" }) {
                    field.doubleValue = 24
                    if let action = field.action { field.sendAction(action, to: field.target) }
                }
                target?.contentView?.layoutSubtreeIfNeeded()
                canvas.fit()
            }
        case 4:
            scene = "workbench"
            do {
                let url = media.appendingPathComponent("桌面片段.mov")
                if !FileManager.default.fileExists(atPath: url.path) { try await makeDesktopClip(url) }
                if let videoWindow {
                    target = videoWindow
                    videoWindow.makeKeyAndOrderFront(nil)
                } else {
                    let model = WorkbenchViewModel(url: url)
                    let window = KeyHandlingWindow(contentRect: CGRect(x: 0, y: 0, width: 1260, height: 790),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.title = "剪辑 — 桌面片段.mov"
                    window.level = .floating
                    window.contentView = NSHostingView(rootView: WorkbenchView(model: model))
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                    videoWindow = window
                    target = window
                    for _ in 0..<200 where model.duration == 0 { try? await Task.sleep(nanoseconds: 20_000_000) }
                    model.createFocusRange(timelineStart: 3, timelineEnd: 7)
                    model.finishFocusEdit()
                    model.seek(to: 2)
                }
            } catch { print("Video preparation failed: \(error.localizedDescription)") }
        case 5:
            scene = "convert"
            ImageConvertToolController.shared.show()
            target = NSApp.windows.first { $0.title == L("图片格式转换") && $0.isVisible }
            let drop = descendants(target!.contentView!).compactMap { $0 as? ImageConvertDropView }.first!
            drop.onDrop?([media.appendingPathComponent("原生壁纸 01.png"), media.appendingPathComponent("原生壁纸 02.png")])
        default:
            scene = "recorder"
            recorder.arm()
            hud.sync()
        }
        if let target, number != 1 { target.center() }
        NSApp.activate(ignoringOtherApps: true)
        let requestedScene = scene
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.scene == requestedScene, !self.switching else { return }
            do { try self.capture() }
            catch { print("Capture failed: \(error.localizedDescription)") }
        }
        print("Website scene ready: \(scene)")
        fflush(stdout)
    }

    @objc private func captureTapped() {
        guard !switching else { return }
        // Delay one run-loop turn so menu tracking has ended before taking the image.
        DispatchQueue.main.async { [weak self] in
            do { try self?.capture() }
            catch { print("Capture failed: \(error.localizedDescription)") }
        }
    }

    private func capture() throws {
        let screen = NSScreen.main!
        let windows = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 }.sorted {
            if $0.level != $1.level { return $0.level.rawValue > $1.level.rawValue }
            return $0.windowNumber > $1.windowNumber
        }
        let rect: CGRect
        if let target, scene != "inline" {
            rect = target.frame.insetBy(dx: -12, dy: -12)
        } else if scene == "recorder", let panel = windows.first(where: { $0 !== backdrop }) {
            rect = panel.frame.insetBy(dx: -80, dy: -100).intersection(screen.frame)
        } else {
            rect = screen.frame
        }
        // Read the live AppKit views in their actual window order/positions. This also
        // includes the floating annotation docks without requesting screen permission.
        let composite = NSImage(size: rect.size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: -rect.minX, yBy: -rect.minY)
            transform.concat()
            for window in windows.reversed() {
                guard let content = window.contentView else { continue }
                let view = window.styleMask.contains(.titled) ? (content.superview ?? content) : content
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let image = bitmap.cgImage else { continue }
                NSImage(cgImage: image, size: window.frame.size).draw(in: window.frame)
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        var bounds = CGRect(origin: .zero, size: rect.size)
        guard let image = composite.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else {
            throw CocoaError(.fileReadUnknown)
        }
        let png = media.appendingPathComponent("\(scene).png")
        try writePNG(image, to: png)
        let data = try ImageConversionWorker.encodedData(source: png,
            options: ImageConversionOptions(format: .webp, quality: 0.88, longEdgeLimit: 2200))
        try data.write(to: output.appendingPathComponent("\(scene).webp"), options: .atomic)
        print("Saved private-safe screenshot: \(scene).webp (\(image.width) × \(image.height))")
        fflush(stdout)
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func preparePhotos() throws {
        for (source, name) in [("Sonoma", "原生壁纸 01"), ("Mac Blue", "原生壁纸 02")] {
            let url = URL(fileURLWithPath: "/System/Library/Desktop Pictures/\(source).heic")
            guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CocoaError(.fileReadUnknown)
            }
            let context = CGContext(data: nil, width: 1440, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1440, height: 900))
            try writePNG(context.makeImage()!, to: media.appendingPathComponent("\(name).png"))
        }
    }

    private func makeDesktopClip(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let size = CGSize(width: 1440, height: 936)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<120 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess,
                  let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.draw(desktop, in: CGRect(origin: .zero, size: size))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
