import AppKit
import AVFoundation
import AVKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// 裁剪面板的来源：录屏结束后自动打开，还是用户主动打开/选文件
enum TrimOrigin { case recording, manual }

private final class FocusDragState {
    var point: CGPoint?
    var scale: Double?
    var segment: TrimViewModel.FocusSegment?
}

/// 简单裁剪：上方完整预览，下方一条可拖动的区间时间轴（起点/终点两个把手 + 播放头）。
/// 播放时只在选中区间内循环预览；导出为同目录下的「原名 - 裁剪.mp4」。
@MainActor
final class TrimWindowController: NSObject, NSWindowDelegate {
    static let shared = TrimWindowController()

    private var entries: [(window: NSWindow, model: TrimViewModel)] = []

    func show(url: URL, origin: TrimOrigin) {
        if let existing = entries.first(where: { $0.model.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            NSApp.activate(ignoringOtherApps: true)
            existing.window.makeKeyAndOrderFront(nil)
            existing.window.orderFrontRegardless()
            return
        }
        let model = TrimViewModel(url: url)
        model.origin = origin
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                   width: min(940, screen.width * 0.82),
                                                   height: min(760, screen.height * 0.85)),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = String(format: L("裁剪 — %@"), url.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        // A non-shareable window is invisible to remote desktops as well as screen recordings.
        window.sharingType = .readOnly
        window.contentView = NSHostingView(rootView: TrimView(model: model))
        window.delegate = self
        model.requestClose = { [weak window] in window?.close() }
        window.center()
        entries.append((window, model))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let closed = note.object as? NSWindow else { return }
                self?.entries.removeAll { $0.window === closed }
            }
        }
    }

    /// 用户点左上角关闭 / ⌘W 时先确认（程序内 close() 靠 isProgrammaticClose 跳过）
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let entry = entries.first(where: { $0.window === sender }) else { return true }
        if entry.model.isProgrammaticClose { return true }
        return entry.model.confirmDiscard()
    }
}

@MainActor
final class TrimViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case trim, annotate
        var id: String { rawValue }
        var label: String { self == .trim ? L("裁剪") : L("标注") }
    }
    let sourceURL: URL
    let player: AVPlayer

    /// 面板来源：录屏结束后自动打开 = .recording，可勾选删除原文件
    var origin: TrimOrigin = .manual

    /// 由程序主动关闭（导出成功 / 删除）时为 true，跳过关窗确认
    var isProgrammaticClose = false

    @Published var duration: Double = 0
    @Published var start: Double = 0
    @Published var end: Double = 0
    @Published var currentTime: Double = 0
    @Published var isExporting = false
    @Published var isPlaying = false
    @Published var status: String?
    @Published var mode: Mode = .trim
    struct AudioOption: Identifiable {
        let id: CMPersistentTrackID
        let title: String
    }
    struct AudioSegment: Identifiable {
        let id = UUID()
        let trackID: CMPersistentTrackID
        var start: Double
        var end: Double
        var volume: Double
    }
    struct FocusSegment: Identifiable {
        let id = UUID()
        var start: Double
        var end: Double
        var x: Double = 0.5
        var y: Double = 0.5
        var scale: Double = 2
    }
    struct VideoAnnotationSegment: Identifiable {
        var range: FocusSegment
        var marks: [VideoMark] = []
        var id: UUID { range.id }
        var start: Double { range.start }
        var end: Double { range.end }
    }
    @Published private(set) var audioOptions: [AudioOption] = []
    @Published var trackVolumes: [CMPersistentTrackID: Double] = [:]
    @Published var audioSegments: [AudioSegment] = []
    @Published var thumbnails: [NSImage] = []
    @Published var focusSegments: [FocusSegment] = []
    @Published var editingFocusID: UUID?
    @Published var annotationSegments: [VideoAnnotationSegment] = []
    @Published var editingAnnotationID: UUID?
    @Published var annotationTool: VideoMarkTool = .pen {
        didSet { annotationCanvas.tool = annotationTool }
    }
    @Published var annotationMosaicStyle: MosaicStyle = .pixelate {
        didSet { annotationCanvas.mosaicStyle = annotationMosaicStyle }
    }
    @Published var annotationColor: NSColor = .systemRed {
        didSet { annotationCanvas.color = annotationColor }
    }
    @Published var annotationLineWidth: CGFloat = 4 {
        didSet { annotationCanvas.lineWidth = annotationLineWidth }
    }
    let annotationCanvas = VideoAnnotationCanvas(frame: .zero)
    @Published var videoSize = CGSize(width: 1920, height: 1080)
    fileprivate let focusDrag = FocusDragState()
    @Published var videoAspect: CGFloat = 16 / 9

    /// 由窗口控制器注入：导出确认后关闭裁剪窗口
    var requestClose: (() -> Void)?

    private var timeObserver: Any?

    init(url: URL) {
        sourceURL = url
        player = AVPlayer(url: url)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = CMTimeGetSeconds(time)
                guard t.isFinite else { return }
                self.currentTime = t
                // 循环预览：播放到终点就跳回起点
                if self.isPlaying, self.end > self.start, t >= self.end - 0.03 {
                    self.player.seek(to: CMTime(seconds: self.start, preferredTimescale: 600),
                                     toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }

    var trimmedDuration: Double { max(0, end - start) }

    func load() async {
        let asset = AVURLAsset(url: sourceURL)
        guard let d = try? await asset.load(.duration), d.isNumeric else {
            status = L("无法读取视频时长")
            return
        }
        duration = CMTimeGetSeconds(d)
        start = 0
        end = duration
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let size = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let oriented = size.applying(transform)
            if oriented.width != 0 && oriented.height != 0 {
                videoAspect = abs(oriented.width / oriented.height)
                videoSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
            }
        }
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        var options: [AudioOption] = []
        for (index, track) in tracks.enumerated() {
            let metadata = (try? await track.load(.metadata)) ?? []
            let identifier = metadata.first(where: { $0.identifier == .commonIdentifierTitle })?.stringValue
            let title: String
            switch identifier {
            case "sakuracap.system": title = L("系统声音")
            case "sakuracap.microphone": title = L("麦克风")
            default:
                // Older Sakura-Cap recordings wrote system audio before microphone audio.
                // A lone unlabelled track cannot safely be identified by its position.
                title = tracks.count == 2 ? (index == 0 ? L("系统声音") : L("麦克风"))
                    : String(format: L("音轨 %d"), index + 1)
            }
            options.append(AudioOption(id: track.trackID, title: title))
        }
        audioOptions = options
        await loadThumbnails(asset: asset)
    }

    private func loadThumbnails(asset: AVAsset) async {
        guard duration > 0 else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        let count = 12
        var images: [NSImage] = []
        for index in 0..<count {
            if Task.isCancelled { return }
            let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image {
                images.append(NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height)))
            } else {
                images.append(NSImage(size: NSSize(width: 16, height: 9)))
            }
        }
        thumbnails = images
    }

    func setVolume(_ volume: Double, for id: CMPersistentTrackID) {
        trackVolumes[id] = volume
        refreshAudioPreview()
    }

    func addAudioSegment(for id: CMPersistentTrackID) {
        let s = max(start, min(currentTime, end - 0.05))
        let e = min(end, s + 3)
        audioSegments.append(AudioSegment(trackID: id, start: s, end: e, volume: 0))
        refreshAudioPreview()
    }

    func updateSegment(_ segment: AudioSegment) {
        guard let index = audioSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        audioSegments[index] = segment
        refreshAudioPreview()
    }

    func removeSegment(_ id: UUID) {
        audioSegments.removeAll { $0.id == id }
        refreshAudioPreview()
    }

    func addFocusSegment() {
        let s = max(start, min(currentTime, end - 0.05))
        let segment = FocusSegment(start: s, end: min(end, s + 3))
        focusSegments.append(segment)
        beginFocusSelection(segment.id)
    }

    func updateFocus(_ segment: FocusSegment) {
        guard let index = focusSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        focusSegments[index] = segment
        refreshVideoPreview()
    }

    func beginFocusSelection(_ id: UUID) {
        guard let segment = focusSegments.first(where: { $0.id == id }) else { return }
        if editingAnnotationID != nil { finishAnnotationSelection() }
        beginScrub()
        seek(to: (segment.start + segment.end) / 2)
        editingFocusID = id
        refreshVideoPreview()
    }

    func setFocusPoint(x: Double, y: Double) {
        guard let editingFocusID,
              let index = focusSegments.firstIndex(where: { $0.id == editingFocusID }) else { return }
        let margin = 0.5 / focusSegments[index].scale
        focusSegments[index].x = min(1 - margin, max(margin, x))
        focusSegments[index].y = min(1 - margin, max(margin, y))
    }

    func finishFocusSelection() {
        editingFocusID = nil
        refreshVideoPreview()
        seek(to: currentTime)
    }

    func removeFocus(_ id: UUID) {
        focusSegments.removeAll { $0.id == id }
        if editingFocusID == id { editingFocusID = nil }
        refreshVideoPreview()
    }

    func addAnnotationSegment() {
        let s = max(start, min(currentTime, end - 0.05))
        let segment = VideoAnnotationSegment(range: FocusSegment(start: s, end: min(end, s + 3)))
        annotationSegments.append(segment)
        beginAnnotationSelection(segment.id)
    }

    func switchMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        if editingAnnotationID != nil { finishAnnotationSelection() }
        if editingFocusID != nil { finishFocusSelection() }
        mode = newMode
    }

    func beginAnnotationSelection(_ id: UUID) {
        guard let segment = annotationSegments.first(where: { $0.id == id }) else { return }
        if editingAnnotationID != nil { finishAnnotationSelection() }
        if editingFocusID != nil { finishFocusSelection() }
        beginScrub()
        seek(to: (segment.start + segment.end) / 2)
        annotationCanvas.loadMarks(segment.marks)
        annotationCanvas.previewFrame = nil
        annotationCanvas.tool = annotationTool
        annotationCanvas.mosaicStyle = annotationMosaicStyle
        annotationCanvas.color = annotationColor
        annotationCanvas.lineWidth = annotationLineWidth
        annotationCanvas.onChange = { [weak self] in self?.objectWillChange.send() }
        editingAnnotationID = id
        refreshVideoPreview()
        Task { await loadAnnotationFrame(for: id, at: currentTime) }
    }

    private func loadAnnotationFrame(for id: UUID, at seconds: Double) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = videoComposition(excluding: id)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        guard editingAnnotationID == id else { return }
        annotationCanvas.previewFrame = frame
    }

    func finishAnnotationSelection() {
        annotationCanvas.finishEditing()
        if let id = editingAnnotationID,
           let index = annotationSegments.firstIndex(where: { $0.id == id }) {
            annotationSegments[index].marks = annotationCanvas.marks
        }
        editingAnnotationID = nil
        annotationCanvas.previewFrame = nil
        refreshVideoPreview()
        seek(to: currentTime)
    }

    func updateAnnotationRange(_ range: FocusSegment) {
        guard let index = annotationSegments.firstIndex(where: { $0.id == range.id }) else { return }
        annotationSegments[index].range = range
        refreshVideoPreview()
    }

    func removeAnnotation(_ id: UUID) {
        if editingAnnotationID == id { editingAnnotationID = nil }
        annotationSegments.removeAll { $0.id == id }
        refreshVideoPreview()
    }

    private func refreshVideoPreview() {
        player.currentItem?.videoComposition = editingFocusID == nil ? videoComposition(excluding: editingAnnotationID) : nil
    }

    private func videoComposition(excluding annotationID: UUID? = nil) -> AVVideoComposition? {
        let layers = annotationSegments.filter { $0.id != annotationID && !$0.marks.isEmpty }.map { segment in
            (start: segment.start, end: segment.end,
             overlay: VideoAnnotationCanvas.image(marks: segment.marks, size: videoSize).map { CIImage(cgImage: $0) },
             mosaic: segment.marks.filter { $0.tool == .mosaic })
        }
        guard !focusSegments.isEmpty || !layers.isEmpty else { return nil }
        let segments = focusSegments.sorted { $0.start < $1.start }
        let outputSize = videoSize
        let asset = AVURLAsset(url: sourceURL)
        return AVVideoComposition(asset: asset) { request in
            let seconds = CMTimeGetSeconds(request.compositionTime)
            let image = request.sourceImage
            let bounds = image.extent
            var magnification = 1.0
            var point = CGPoint(x: 0.5, y: 0.5)
            if let segment = segments.last(where: { seconds >= $0.start && seconds < $0.end }) {
                let fade = min(1, max(0, min(seconds - segment.start, segment.end - seconds) / 0.3))
                let smooth = fade * fade * (3 - 2 * fade)
                magnification = 1 + (segment.scale - 1) * smooth
                point = CGPoint(x: segment.x, y: 1 - segment.y)
            }
            let margin = 0.5 / magnification
            let focusX = bounds.minX + bounds.width * min(1 - margin, max(margin, point.x))
            let focusY = bounds.minY + bounds.height * min(1 - margin, max(margin, point.y))
            let transform = CGAffineTransform(translationX: bounds.midX - focusX * magnification,
                                               y: bounds.midY - focusY * magnification)
                .scaledBy(x: magnification, y: magnification)
            var output = image.transformed(by: transform).cropped(to: bounds)
            for layer in layers where seconds >= layer.start && seconds < layer.end {
                for mark in layer.mosaic {
                    let p = VideoAnnotationCanvas.rect(for: mark, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    let region = CGRect(x: bounds.minX + p.minX * bounds.width,
                                        y: bounds.minY + (1 - p.maxY) * bounds.height,
                                        width: p.width * bounds.width, height: p.height * bounds.height).integral
                        .intersection(bounds)
                    guard region.width >= 2, region.height >= 2 else { continue }
                    if let pixels = VideoAnnotationCanvas.mosaic(image: output, style: mark.mosaicStyle,
                                                                  region: region, scale: max(10, bounds.width / 110)) {
                        output = pixels.composited(over: output).cropped(to: bounds)
                    }
                }
                if let overlay = layer.overlay {
                    let scaled = overlay.transformed(by: CGAffineTransform(scaleX: bounds.width / outputSize.width,
                                                                            y: bounds.height / outputSize.height))
                        .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
                    output = scaled.composited(over: output).cropped(to: bounds)
                }
            }
            request.finish(with: output, context: nil)
        }
    }

    private func refreshAudioPreview() {
        player.currentItem?.audioMix = audioMix()
    }

    private func audioMix() -> AVAudioMix? {
        guard !trackVolumes.isEmpty || !audioSegments.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioOptions.map { option in
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = option.id
            let base = Float(trackVolumes[option.id] ?? 1)
            parameters.setVolume(base, at: .zero)
            let segments = audioSegments.filter { $0.trackID == option.id }
            let boundaries = Set(segments.flatMap { [$0.start, $0.end] }).sorted()
            for time in boundaries {
                let active = segments.last { $0.start <= time && $0.end > time }
                parameters.setVolume(Float(active?.volume ?? Double(base)),
                                     at: CMTime(seconds: time, preferredTimescale: 600))
            }
            return parameters
        }
        return mix
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if editingAnnotationID != nil { finishAnnotationSelection() }
            if currentTime < start || currentTime >= end {
                seek(to: start)
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let t = max(0, min(duration, seconds))
        if let id = editingAnnotationID,
           let segment = annotationSegments.first(where: { $0.id == id }),
           (t < segment.start || t >= segment.end) {
            finishAnnotationSelection()
        }
        currentTime = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 开始拖动时间轴：先暂停播放，以便逐帧预览拖动到的位置
    func beginScrub() {
        if isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    /// 时间轴拖动回调：更新区间（预览由 onScrub 负责）
    func updateRange(start s: Double, end e: Double) {
        start = max(0, min(s, e))
        end = max(start + 0.05, e)
    }

    /// 点「导出」：先弹确认框（含「删除原文件」勾选），确认后再导出
    func exportTapped() {
        guard trimmedDuration > 0.05 else { status = L("裁剪区间太短"); return }
        if editingAnnotationID != nil { finishAnnotationSelection() }
        let outURL = Self.availableURL(for: Self.outputURL(for: sourceURL))
        let alert = NSAlert()
        alert.messageText = L("导出裁剪后的视频")
        alert.informativeText = String(format: L("将导出为「%@」。"), outURL.lastPathComponent)
        let checkbox = NSButton(checkboxWithTitle: L("导出后删除原文件"), target: nil, action: nil)
        checkbox.state = .off
        checkbox.sizeToFit()
        alert.accessoryView = checkbox
        alert.addButton(withTitle: L("导出"))
        alert.addButton(withTitle: L("取消"))
        guard runModalAlert(alert) == .alertFirstButtonReturn else { return }
        let deleteOriginal = checkbox.state == .on
        Task { await self.export(deleteOriginal: deleteOriginal, to: outURL) }
    }

    /// 关闭窗口前的确认（点左上角关闭 / ⌘W 时由 TrimWindow 调用）；返回 true 表示允许关闭
    func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("确定放弃裁剪吗？")
        var deleteCheckbox: NSButton?
        if origin == .recording {
            let box = NSButton(checkboxWithTitle: L("删除录屏原文件"), target: nil, action: nil)
            box.state = .off
            box.sizeToFit()
            alert.accessoryView = box
            deleteCheckbox = box
        }
        alert.addButton(withTitle: L("确定"))
        alert.addButton(withTitle: L("取消"))
        guard runModalAlert(alert) == .alertFirstButtonReturn else { return false }

        if deleteCheckbox?.state == .on {
            player.pause()
            isPlaying = false
            player.replaceCurrentItem(with: nil) // 释放文件占用，确保能删除
            try? FileManager.default.removeItem(at: sourceURL)
        }
        return true
    }

    /// 截帧：把播放头所在帧存为 PNG，并打开标注编辑器
    func captureFrameTapped() {
        guard !isExporting, let dir = OutputDirectoryPicker.ensureDirectory(current: AppSettings.shared.outputDirectory) else { return }
        if editingAnnotationID != nil { finishAnnotationSelection() }
        player.pause()
        isPlaying = false
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = videoComposition()
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        Task { @MainActor in
            do {
                let cg = try await generator.image(at: time).image
                let url = dir.appendingPathComponent(FileName.make(ext: "png"))
                guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
                try data.write(to: url)
                status = String(format: L("已截帧 %@"), url.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                AnnotationEditorController.shared.open(image: cg, suggestedName: url.lastPathComponent, source: .existingFile)
            } catch {
                status = String(format: L("截帧失败：%@"), error.localizedDescription)
            }
        }
    }

    /// 点「删除」：二次确认后删除原始录像文件，并关闭裁剪窗口
    func deleteTapped() {
        let alert = NSAlert()
        alert.messageText = L("删除录像文件")
        alert.informativeText = String(format: L("确定要删除「%@」吗？此操作不可撤销。"), sourceURL.lastPathComponent)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("取消"))
        alert.addButton(withTitle: L("删除"))
        guard runModalAlert(alert) == .alertSecondButtonReturn else { return }

        // 先停止播放并释放文件占用，确保能删除
        player.pause()
        isPlaying = false
        player.replaceCurrentItem(with: nil)
        do {
            try FileManager.default.removeItem(at: sourceURL)
            isProgrammaticClose = true
            requestClose?()
        } catch {
            status = String(format: L("删除失败：%@"), error.localizedDescription)
            let fail = NSAlert()
            fail.messageText = L("删除失败")
            fail.informativeText = error.localizedDescription
            fail.addButton(withTitle: L("好"))
            runModalAlert(fail)
        }
    }

    func export(deleteOriginal: Bool, to outURL: URL) async {
        guard trimmedDuration > 0.05 else { status = L("裁剪区间太短"); return }
        isExporting = true
        status = nil
        player.pause()
        isPlaying = false
        defer { isExporting = false }

        let asset: AVAsset
        do {
            asset = try await exportAsset()
        } catch {
            status = String(format: L("导出失败：%@"), error.localizedDescription)
            return
        }
        let hasEdits = !trackVolumes.isEmpty || !audioSegments.isEmpty || !focusSegments.isEmpty ||
            annotationSegments.contains { !$0.marks.isEmpty }
        let preset = hasEdits ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            status = L("无法创建导出任务")
            return
        }
        exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                         end: CMTime(seconds: end, preferredTimescale: 600))
        exporter.audioMix = audioMix()
        exporter.videoComposition = videoComposition()
        exporter.shouldOptimizeForNetworkUse = true
        do {
            if #available(macOS 15.0, *) {
                try await exporter.export(to: outURL, as: .mp4)
            } else {
                exporter.outputURL = outURL
                exporter.outputFileType = .mp4
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    exporter.exportAsynchronously {
                        if let error = exporter.error { cont.resume(throwing: error) }
                        else { cont.resume() }
                    }
                }
            }
            if deleteOriginal {
                try? FileManager.default.removeItem(at: sourceURL)
                status = String(format: L("已导出并删除原文件：%@"), outURL.lastPathComponent)
            } else {
                status = String(format: L("已导出 %@"), outURL.lastPathComponent)
            }
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
            isProgrammaticClose = true
            requestClose?() // 导出成功后才关闭裁剪窗口
        } catch {
            status = String(format: L("导出失败：%@"), error.localizedDescription)
            // 窗口可能已关闭，失败时用弹窗告知
            let alert = NSAlert()
            alert.messageText = L("导出失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L("好"))
            runModalAlert(alert)
        }
    }

    private func exportAsset() async throws -> AVAsset {
        AVURLAsset(url: sourceURL)
    }

    /// 点「导出 GIF」：先弹确认框（含尺寸选择）
    func exportGIFTapped() {
        guard trimmedDuration > 0.05 else { status = L("裁剪区间太短"); return }
        if editingAnnotationID != nil { finishAnnotationSelection() }
        let outURL = Self.availableURL(for: Self.gifOutputURL(for: sourceURL))
        let alert = NSAlert()
        alert.messageText = L("导出 GIF")
        alert.informativeText = String(format: L("将导出为「%@」。"), outURL.lastPathComponent)
            + "\n" + L("GIF 适合短片段，较长视频会较慢、文件较大。")
        let label = NSTextField(labelWithString: L("尺寸"))
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: GIFSize.allCases.map { $0.label })
        popup.selectItem(at: 0)
        let accessory = NSStackView(views: [label, popup])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        accessory.frame = NSRect(x: 0, y: 0, width: 220, height: 28)
        alert.accessoryView = accessory
        alert.addButton(withTitle: L("导出"))
        alert.addButton(withTitle: L("取消"))
        guard runModalAlert(alert) == .alertFirstButtonReturn else { return }
        let index = max(0, min(popup.indexOfSelectedItem, GIFSize.allCases.count - 1))
        let size = GIFSize.allCases[index]
        Task { await self.exportGIF(size: size, to: outURL) }
    }

    func exportGIF(size: GIFSize, to outURL: URL) async {
        guard trimmedDuration > 0.05 else { status = L("裁剪区间太短"); return }
        isExporting = true
        status = nil
        player.pause()
        isPlaying = false
        defer { isExporting = false }

        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                end: CMTime(seconds: end, preferredTimescale: 600))
        do {
            try await GIFExporter.export(source: sourceURL, timeRange: range, size: size,
                                         videoComposition: videoComposition(), to: outURL)
            status = String(format: L("已导出 %@"), outURL.lastPathComponent)
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
            Toast.show(title: L("GIF 导出完成"), detail: outURL.lastPathComponent)
        } catch {
            Log.app.error("GIF 导出失败: \(error.localizedDescription, privacy: .public)")
            status = String(format: L("导出失败：%@"), error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = L("导出失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L("好"))
            runModalAlert(alert)
        }
    }

    private static func outputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(base) - \(L("裁剪")).mp4")
    }

    private static func availableURL(for preferred: URL) -> URL {
        guard FileManager.default.fileExists(atPath: preferred.path) else { return preferred }
        let base = preferred.deletingPathExtension()
        for index in 2...9999 {
            let candidate = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent) \(index)")
                .appendingPathExtension(preferred.pathExtension)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return base.deletingLastPathComponent()
            .appendingPathComponent("\(base.lastPathComponent) \(UUID().uuidString)")
            .appendingPathExtension(preferred.pathExtension)
    }

    private static func gifOutputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(base) - \(L("裁剪")).gif")
    }
}

struct TrimView: View {
    @ObservedObject var model: TrimViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("编辑模式"), selection: Binding(get: { model.mode }, set: { model.switchMode($0) })) {
                ForEach(TrimViewModel.Mode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .tint(SettingsAppearance.color(SettingsAppearance.accent))

            PlayerView(player: model.player)
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if let id = model.editingFocusID,
                       let segment = model.focusSegments.first(where: { $0.id == id }) {
                        FocusCanvas(segment: segment, aspect: model.videoAspect, dragState: model.focusDrag,
                                    onPoint: { model.setFocusPoint(x: $0, y: $1) },
                                    onScale: { value in
                                        var updated = segment
                                        updated.scale = value
                                        model.updateFocus(updated)
                                    },
                                    onDone: { model.finishFocusSelection() })
                    }
                }
                .overlay {
                    if model.editingAnnotationID != nil {
                        GeometryReader { geometry in
                            let width = min(geometry.size.width, geometry.size.height * model.videoAspect)
                            let height = width / model.videoAspect
                            VideoAnnotationView(canvas: model.annotationCanvas)
                                .frame(width: width, height: height)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        }
                    }
                }

            TimelineSlider(
                duration: model.duration,
                start: model.start,
                end: model.end,
                playhead: model.currentTime,
                thumbnails: model.thumbnails,
                onRangeChange: { s, e in model.updateRange(start: s, end: e) },
                onBeginEdit: { model.beginScrub() },
                onScrub: { t in model.seek(to: t) }
            )
            .frame(height: 66)

            HStack(spacing: 8) {
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 22)
                }
                .buttonStyle(.bordered)

                Text(CompletionNotifier.format(model.currentTime)).monospacedDigit()
                Text("/").foregroundStyle(.secondary)
                Text(CompletionNotifier.format(model.duration)).monospacedDigit().foregroundStyle(.secondary)

                Spacer()

                Text(String(format: L("截取 %@ – %@　共 %@"), CompletionNotifier.format(model.start), CompletionNotifier.format(model.end), CompletionNotifier.format(model.trimmedDuration)))
                    .font(SettingsAppearance.detailFont).foregroundStyle(.secondary).monospacedDigit()
            }

            if model.mode == .trim {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.audioOptions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.audioOptions) { option in
                                    let volume = model.trackVolumes[option.id] ?? 1
                                    HStack(spacing: 8) {
                                        Text(option.title).frame(width: 72, alignment: .leading)
                                        Button {
                                            model.setVolume(volume == 0 ? 1 : 0, for: option.id)
                                        } label: {
                                            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        }.buttonStyle(.plain).help(L("整轨静音或恢复声音"))
                                        Slider(value: Binding(get: { model.trackVolumes[option.id] ?? 1 },
                                                              set: { model.setVolume($0, for: option.id) }), in: 0...1)
                                            .frame(width: 100)
                                        Text("\(Int(volume * 100))%")
                                            .monospacedDigit().frame(width: 42, alignment: .trailing)
                                        Button(L("添加静音段")) { model.addAudioSegment(for: option.id) }
                                            .buttonStyle(.bordered)
                                            .help(L("从播放头开始添加 3 秒静音段，可编辑起止时间与音量"))
                                        Spacer()
                                    }
                                    .font(SettingsAppearance.detailFont)
                                    AudioLane(duration: model.duration, playhead: model.currentTime,
                                              segments: model.audioSegments.filter { $0.trackID == option.id },
                                              onSelect: { model.seek(to: $0) })
                                        .frame(height: 16)
                                    ForEach(model.audioSegments.filter { $0.trackID == option.id }) { segment in
                                        AudioSegmentRow(segment: segment, duration: model.duration,
                                                        onChange: { model.updateSegment($0) },
                                                        onDelete: { model.removeSegment(segment.id) })
                                    }
                                }
                            }
                        }

                        HStack {
                            Text(L("画面聚焦")).font(SettingsAppearance.detailFont).foregroundStyle(.secondary)
                            Button(L("添加聚焦")) { model.addFocusSegment() }
                                .buttonStyle(.bordered)
                                .help(L("在播放头创建聚焦段，然后在画面中拖动框调整位置和范围"))
                            Spacer()
                        }
                        FocusLane(duration: model.duration, trimStart: model.start, trimEnd: model.end,
                                  playhead: model.currentTime, segments: model.focusSegments,
                                  selectedID: model.editingFocusID, dragState: model.focusDrag,
                                  symbol: "plus.magnifyingglass",
                                  onChange: { model.updateFocus($0) },
                                  onSelect: { model.beginFocusSelection($0) },
                                  onSeek: { model.seek(to: $0) })
                            .frame(height: 32)
                        if let id = model.editingFocusID,
                           let segment = model.focusSegments.first(where: { $0.id == id }) {
                            HStack {
                                Text(String(format: L("聚焦 %@–%@，%.1f 倍"),
                                            CompletionNotifier.format(segment.start), CompletionNotifier.format(segment.end), segment.scale))
                                    .font(SettingsAppearance.detailFont).foregroundStyle(.secondary)
                                Spacer()
                                Button(L("删除聚焦")) { model.removeFocus(id) }.buttonStyle(.plain)
                                Button(L("完成")) { model.finishFocusSelection() }.buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 5)
                }
                .frame(height: 170)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(L("添加标注段")) { model.addAnnotationSegment() }
                            .buttonStyle(.bordered)
                            .help(L("在播放头创建标注段，然后直接在预览画面绘制"))
                        Spacer()
                    }
                    FocusLane(duration: model.duration, trimStart: model.start, trimEnd: model.end,
                              playhead: model.currentTime, segments: model.annotationSegments.map(\.range),
                              selectedID: model.editingAnnotationID, dragState: model.focusDrag,
                              symbol: "pencil.tip",
                              onChange: { model.updateAnnotationRange($0) },
                              onSelect: { model.beginAnnotationSelection($0) },
                              onSeek: { model.seek(to: $0) })
                        .frame(height: 32)
                    HStack(spacing: 6) {
                        ForEach(VideoMarkTool.allCases) { tool in
                            Button { model.annotationTool = tool } label: {
                                Image(systemName: tool.symbol).frame(width: 20)
                            }
                            .buttonStyle(.bordered)
                            .tint(model.annotationTool == tool ? SettingsAppearance.color(SettingsAppearance.accent) : nil)
                            .help(tool.label)
                            .disabled(model.editingAnnotationID == nil)
                        }
                        Divider().frame(height: 24)
                        Button(L("撤回")) { model.annotationCanvas.undo() }
                            .disabled(model.editingAnnotationID == nil || model.annotationCanvas.undoStack.isEmpty)
                        Button(L("删除选中")) { model.annotationCanvas.deleteSelected() }
                            .disabled(model.editingAnnotationID == nil || model.annotationCanvas.selectedIndex == nil)
                        Button(L("清空")) { model.annotationCanvas.clear() }
                            .disabled(model.editingAnnotationID == nil || model.annotationCanvas.marks.isEmpty)
                        Spacer()
                        if let id = model.editingAnnotationID {
                            Button(L("删除标注段")) { model.removeAnnotation(id) }.buttonStyle(.plain)
                            Button(L("完成标注")) { model.finishAnnotationSelection() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .font(SettingsAppearance.detailFont)
                    HStack(spacing: 10) {
                        if model.annotationTool == .mosaic {
                            Text(L("马赛克"))
                            Picker(L("马赛克样式"), selection: $model.annotationMosaicStyle) {
                                ForEach(MosaicStyle.allCases) { style in Text(style.label).tag(style) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                        } else {
                            Text(L("颜色"))
                            ForEach([NSColor.systemRed, .systemYellow, .systemBlue, .systemGreen, .white], id: \.self) { color in
                                Button { model.annotationColor = color } label: {
                                    Circle().fill(Color(nsColor: color))
                                        .frame(width: 16, height: 16)
                                        .padding(3)
                                        .overlay(Circle().stroke(model.annotationColor == color ? Color.accentColor : .clear, lineWidth: 2))
                                }.buttonStyle(.plain)
                            }
                            Text(L("粗细"))
                            Slider(value: Binding(get: { Double(model.annotationLineWidth) },
                                                  set: { model.annotationLineWidth = CGFloat($0) }), in: 1...12)
                                .frame(width: 105)
                        }
                        Spacer()
                    }
                    .font(SettingsAppearance.detailFont)
                    .disabled(model.editingAnnotationID == nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if let status = model.status {
                    Text(status).font(SettingsAppearance.detailFont).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if model.isExporting { ProgressView().controlSize(.small) }
                Button { model.captureFrameTapped() } label: { Text(L("截帧")) }
                    .buttonStyle(.bordered)
                    .disabled(model.isExporting)
                Button { model.exportGIFTapped() } label: { Text(L("导出 GIF")) }
                    .buttonStyle(.bordered)
                    .disabled(model.isExporting || model.duration <= 0)
                Button("删除", role: .destructive) { model.deleteTapped() }
                    .buttonStyle(.bordered)
                    .disabled(model.isExporting)
                Button("导出") { model.exportTapped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isExporting || model.duration <= 0)
            }
        }
        .padding(16)
        .background(SettingsAppearance.color(SettingsAppearance.canvas))
        .tint(SettingsAppearance.color(SettingsAppearance.accent))
        .frame(minWidth: 700, minHeight: 540)
        .task { await model.load() }
        .onDisappear { model.player.pause() }
    }
}

/// 剪辑式区间时间轴：一条轨道 + 起点/终点两个可拖动手柄 + 播放头。
/// 用 AppKit 实现，避免 CLT 工具链下 SwiftUI 宏（@State）不可用的问题。
final class TimelineView: NSView {
    var duration: Double = 0 { didSet { needsDisplay = true } }
    var start: Double = 0 { didSet { needsDisplay = true } }
    var end: Double = 0 { didSet { needsDisplay = true } }
    var playhead: Double = 0 { didSet { needsDisplay = true } }
    var thumbnails: [NSImage] = [] { didSet { needsDisplay = true } }

    var onRangeChange: ((Double, Double) -> Void)?
    var onBeginEdit: (() -> Void)?
    var onScrub: ((Double) -> Void)?

    private enum Drag { case none, start, end, playhead }
    private var drag: Drag = .none

    private let inset: CGFloat = 10
    private let trackHeight: CGFloat = 6
    private let handleWidth: CGFloat = 11
    private let handleHeight: CGFloat = 30
    private let hit: CGFloat = 11

    private var trackWidth: CGFloat { max(1, bounds.width - inset * 2) }

    private func x(for t: Double) -> CGFloat {
        guard duration > 0 else { return inset }
        return inset + CGFloat(max(0, min(t, duration)) / duration) * trackWidth
    }

    private func time(atX px: CGFloat) -> Double {
        guard duration > 0 else { return 0 }
        let ratio = Double((px - inset) / trackWidth)
        return max(0, min(duration, ratio * duration))
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let sx = x(for: start)
        let ex = x(for: end)

        if !thumbnails.isEmpty {
            let width = trackWidth / CGFloat(thumbnails.count)
            for (index, image) in thumbnails.enumerated() {
                image.draw(in: NSRect(x: inset + CGFloat(index) * width, y: midY - 22,
                                      width: width, height: 44),
                           from: .zero, operation: .sourceOver, fraction: 0.75)
            }
        }

        // 轨道
        let track = NSBezierPath(roundedRect: NSRect(x: inset, y: midY - trackHeight / 2,
                                                     width: trackWidth, height: trackHeight),
                                 xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        SettingsAppearance.separator.setFill()
        track.fill()

        // 选中区间
        let selected = NSBezierPath(roundedRect: NSRect(x: sx, y: midY - trackHeight / 2,
                                                        width: max(trackHeight, ex - sx), height: trackHeight),
                                    xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        SettingsAppearance.focus.withAlphaComponent(0.35).setFill()
        selected.fill()

        // 播放头
        if duration > 0 {
            let px = x(for: playhead)
            let head = NSBezierPath()
            head.move(to: NSPoint(x: px, y: midY - handleHeight / 2 - 4))
            head.line(to: NSPoint(x: px, y: midY + handleHeight / 2 + 4))
            head.lineWidth = 1.5
            NSColor.labelColor.withAlphaComponent(0.85).setStroke()
            head.stroke()
        }

        drawHandle(at: sx, midY: midY)
        drawHandle(at: ex, midY: midY)
    }

    private func drawHandle(at cx: CGFloat, midY: CGFloat) {
        let rect = NSRect(x: cx - handleWidth / 2, y: midY - handleHeight / 2,
                          width: handleWidth, height: handleHeight)
        let path = NSBezierPath(roundedRect: rect, xRadius: handleWidth / 2, yRadius: handleWidth / 2)
        SettingsAppearance.accent.setFill()
        path.fill()
        SettingsAppearance.canvas.setStroke()
        path.lineWidth = SettingsAppearance.borderWidth
        path.stroke()
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onBeginEdit?() // 拖动即暂停，边拖边预览
        if abs(p.x - x(for: start)) <= hit {
            drag = .start
            onScrub?(start)
        } else if abs(p.x - x(for: end)) <= hit {
            drag = .end
            onScrub?(end)
        } else {
            drag = .playhead
            onScrub?(time(atX: p.x))
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .start:
            let t = min(time(atX: p.x), end - 0.05)
            start = max(0, t)
            onRangeChange?(start, end)
            onScrub?(start)
        case .end:
            let t = max(time(atX: p.x), start + 0.05)
            end = min(duration, t)
            onRangeChange?(start, end)
            onScrub?(end)
        case .playhead:
            onScrub?(time(atX: p.x))
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        drag = .none
    }
}

struct TimelineSlider: NSViewRepresentable {
    let duration: Double
    let start: Double
    let end: Double
    let playhead: Double
    let thumbnails: [NSImage]
    let onRangeChange: (Double, Double) -> Void
    let onBeginEdit: () -> Void
    let onScrub: (Double) -> Void

    func makeNSView(context: Context) -> TimelineView {
        let view = TimelineView()
        view.duration = duration
        view.start = start
        view.end = end
        view.playhead = playhead
        view.thumbnails = thumbnails
        view.onRangeChange = onRangeChange
        view.onBeginEdit = onBeginEdit
        view.onScrub = onScrub
        return view
    }

    func updateNSView(_ view: TimelineView, context: Context) {
        view.onRangeChange = onRangeChange
        view.onBeginEdit = onBeginEdit
        view.onScrub = onScrub
        view.duration = duration
        view.start = start
        view.end = end
        view.playhead = playhead
        if view.thumbnails.count != thumbnails.count { view.thumbnails = thumbnails }
    }
}

private struct AudioLane: View {
    let duration: Double
    let playhead: Double
    let segments: [TrimViewModel.AudioSegment]
    let onSelect: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.volume == 0 ? Color.orange.opacity(0.7) : Color.accentColor.opacity(0.7))
                        .frame(width: max(2, geometry.size.width * CGFloat((segment.end - segment.start) / max(duration, 0.01))), height: 16)
                        .offset(x: geometry.size.width * CGFloat(segment.start / max(duration, 0.01)))
                }
                Rectangle().fill(Color.primary.opacity(0.8)).frame(width: 1)
                    .offset(x: geometry.size.width * CGFloat(playhead / max(duration, 0.01)))
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                onSelect(Double(location.x / max(geometry.size.width, 1)) * duration)
            }
        }
    }
}

private struct AudioSegmentRow: View {
    let segment: TrimViewModel.AudioSegment
    let duration: Double
    let onChange: (TrimViewModel.AudioSegment) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundStyle(.secondary)
            Text(L("起点"))
            TextField("", value: Binding(get: { segment.start }, set: { value in
                var updated = segment
                updated.start = max(0, min(value, segment.end - 0.05))
                onChange(updated)
            }), format: .number.precision(.fractionLength(2)))
                .frame(width: 54)
            Text(L("终点"))
            TextField("", value: Binding(get: { segment.end }, set: { value in
                var updated = segment
                updated.end = max(segment.start + 0.05, min(value, duration))
                onChange(updated)
            }), format: .number.precision(.fractionLength(2)))
                .frame(width: 54)
            Slider(value: Binding(get: { segment.volume }, set: { value in
                var updated = segment
                updated.volume = value
                onChange(updated)
            }), in: 0...1)
            Text("\(Int(segment.volume * 100))%")
                .monospacedDigit().frame(width: 40, alignment: .trailing)
            Button(action: onDelete) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).help(L("移除音量段"))
        }
        .font(SettingsAppearance.detailFont)
    }
}

private struct FocusCanvas: View {
    let segment: TrimViewModel.FocusSegment
    let aspect: CGFloat
    let dragState: FocusDragState
    let onPoint: (Double, Double) -> Void
    let onScale: (Double) -> Void
    let onDone: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * max(aspect, 0.1))
            let height = width / max(aspect, 0.1)
            let imageRect = CGRect(x: (geometry.size.width - width) / 2,
                                   y: (geometry.size.height - height) / 2,
                                   width: width, height: height)
            let frameWidth = width / segment.scale
            let frameHeight = height / segment.scale
            let center = CGPoint(x: imageRect.minX + width * segment.x,
                                 y: imageRect.minY + height * segment.y)

            ZStack(alignment: .topTrailing) {
                SettingsAppearance.color(SettingsAppearance.canvas).opacity(0.08).contentShape(Rectangle())
                    .onTapGesture { point in
                        guard imageRect.contains(point) else { return }
                        onPoint(Double((point.x - imageRect.minX) / width),
                                Double((point.y - imageRect.minY) / height))
                    }
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.65), radius: 3)
                    .overlay {
                        Image(systemName: "plus").font(SettingsAppearance.detailFont).foregroundStyle(.white)
                    }
                    .frame(width: frameWidth, height: frameHeight)
                    .contentShape(Rectangle())
                    .position(center)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragState.point == nil { dragState.point = CGPoint(x: segment.x, y: segment.y) }
                            guard let origin = dragState.point else { return }
                            let margin = 0.5 / segment.scale
                            onPoint(min(1 - margin, max(margin, origin.x + value.translation.width / width)),
                                    min(1 - margin, max(margin, origin.y + value.translation.height / height)))
                        }.onEnded { _ in dragState.point = nil })
                Circle().fill(.white)
                    .overlay { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9)).foregroundStyle(.black) }
                    .frame(width: 24, height: 24)
                    .position(x: center.x + frameWidth / 2, y: center.y + frameHeight / 2)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragState.scale == nil { dragState.scale = segment.scale }
                            guard let origin = dragState.scale else { return }
                            onScale(min(3, max(1, origin / max(0.3, 1 + Double(value.translation.width / width) * origin * 2))))
                        }.onEnded { _ in dragState.scale = nil })
                Button(L("完成聚焦"), action: onDone)
                    .buttonStyle(.borderedProminent).padding(10)
            }
        }
    }
}

private struct FocusLane: View {
    let duration: Double
    let trimStart: Double
    let trimEnd: Double
    let playhead: Double
    let segments: [TrimViewModel.FocusSegment]
    let selectedID: UUID?
    let dragState: FocusDragState
    let symbol: String
    let onChange: (TrimViewModel.FocusSegment) -> Void
    let onSelect: (UUID) -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(SettingsAppearance.color(SettingsAppearance.control))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(SettingsAppearance.color(SettingsAppearance.separator), lineWidth: SettingsAppearance.borderWidth))
                    .onTapGesture { point in onSeek(Double(point.x / max(width, 1)) * duration) }
                ForEach(segments) { segment in
                    FocusBlock(segment: segment, selected: selectedID == segment.id,
                               width: width, duration: duration, trimStart: trimStart, trimEnd: trimEnd,
                               dragState: dragState, symbol: symbol,
                               onChange: onChange, onSelect: { onSelect(segment.id) })
                        .frame(width: max(5, width * CGFloat((segment.end - segment.start) / max(duration, 0.01))))
                        .offset(x: width * CGFloat(segment.start / max(duration, 0.01)))
                }
                Rectangle().fill(Color.primary.opacity(0.8)).frame(width: 1)
                    .offset(x: width * CGFloat(playhead / max(duration, 0.01)))
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct FocusBlock: View {
    enum Edge { case left, middle, right }
    let segment: TrimViewModel.FocusSegment
    let selected: Bool
    let width: CGFloat
    let duration: Double
    let trimStart: Double
    let trimEnd: Double
    let dragState: FocusDragState
    let symbol: String
    let onChange: (TrimViewModel.FocusSegment) -> Void
    let onSelect: () -> Void

    private func drag(_ edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragState.segment == nil { dragState.segment = segment; onSelect() }
                guard let origin = dragState.segment else { return }
                let delta = Double(value.translation.width / max(width, 1)) * duration
                var updated = origin
                switch edge {
                case .left: updated.start = min(origin.end - 0.05, max(trimStart, origin.start + delta))
                case .right: updated.end = max(origin.start + 0.05, min(trimEnd, origin.end + delta))
                case .middle:
                    let start = min(trimEnd - (origin.end - origin.start), max(trimStart, origin.start + delta))
                    updated.start = start
                    updated.end = start + origin.end - origin.start
                }
                onChange(updated)
            }.onEnded { _ in dragState.segment = nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.85)).frame(width: 7).padding(.horizontal, 3)
                .contentShape(Rectangle()).gesture(drag(.left))
            Spacer(minLength: 0)
            Image(systemName: symbol).font(SettingsAppearance.detailFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect).gesture(drag(.middle))
            Spacer(minLength: 0)
            Capsule().fill(.white.opacity(0.85)).frame(width: 7).padding(.horizontal, 3)
                .contentShape(Rectangle()).gesture(drag(.right))
        }
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(SettingsAppearance.color(selected ? SettingsAppearance.accent : SettingsAppearance.focus)))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(SettingsAppearance.color(SettingsAppearance.accentText), lineWidth: SettingsAppearance.borderWidth))
    }
}

/// AppKit 的 AVPlayerView（SwiftUI 的 VideoPlayer 在 CLT 构建下会崩）
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
