import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// 简单裁剪：上方完整预览，下方一条可拖动的区间时间轴（起点/终点两个把手 + 播放头）。
/// 播放时只在选中区间内循环预览；导出为同目录下的「原名 - 裁剪.mp4」。
@MainActor
final class TrimWindowController {
    static let shared = TrimWindowController()

    private var entries: [(window: NSWindow, model: TrimViewModel)] = []

    func show(url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let model = TrimViewModel(url: url)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "裁剪 — \(url.lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.sharingType = .none // 永不进入录制
        window.contentView = NSHostingView(rootView: TrimView(model: model))
        model.requestClose = { [weak window] in window?.close() }
        window.center()
        window.makeKeyAndOrderFront(nil)
        entries.append((window, model))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let closed = note.object as? NSWindow else { return }
                self?.entries.removeAll { $0.window === closed }
            }
        }
    }
}

@MainActor
final class TrimViewModel: ObservableObject {
    let sourceURL: URL
    let player: AVPlayer

    @Published var duration: Double = 0
    @Published var start: Double = 0
    @Published var end: Double = 0
    @Published var currentTime: Double = 0
    @Published var isExporting = false
    @Published var isPlaying = false
    @Published var status: String?

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
            status = "无法读取视频时长"
            return
        }
        duration = CMTimeGetSeconds(d)
        start = 0
        end = duration
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime < start || currentTime >= end {
                seek(to: start)
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let t = max(0, min(duration, seconds))
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
        guard trimmedDuration > 0.05 else { status = "裁剪区间太短"; return }
        let outURL = Self.outputURL(for: sourceURL)
        let alert = NSAlert()
        alert.messageText = "导出裁剪后的视频"
        alert.informativeText = "将导出为「\(outURL.lastPathComponent)」。"
        let checkbox = NSButton(checkboxWithTitle: "导出后删除原文件", target: nil, action: nil)
        checkbox.state = .off
        checkbox.sizeToFit()
        alert.accessoryView = checkbox
        alert.addButton(withTitle: "导出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let deleteOriginal = checkbox.state == .on
        Task { await self.export(deleteOriginal: deleteOriginal) }
    }

    func export(deleteOriginal: Bool) async {
        guard trimmedDuration > 0.05 else { status = "裁剪区间太短"; return }
        isExporting = true
        status = nil
        player.pause()
        isPlaying = false
        defer { isExporting = false }

        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            status = "无法创建导出任务"
            return
        }
        let outURL = Self.outputURL(for: sourceURL)
        try? FileManager.default.removeItem(at: outURL)
        exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                         end: CMTime(seconds: end, preferredTimescale: 600))
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
                status = "已导出并删除原文件：\(outURL.lastPathComponent)"
            } else {
                status = "已导出 \(outURL.lastPathComponent)"
            }
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
            requestClose?() // 导出成功后才关闭裁剪窗口
        } catch {
            status = "导出失败：\(error.localizedDescription)"
            // 窗口可能已关闭，失败时用弹窗告知
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    private static func outputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(base) - 裁剪.mp4")
    }
}

struct TrimView: View {
    @ObservedObject var model: TrimViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlayerView(player: model.player)
                .frame(maxWidth: .infinity, minHeight: 250)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TimelineSlider(
                duration: model.duration,
                start: model.start,
                end: model.end,
                playhead: model.currentTime,
                onRangeChange: { s, e in model.updateRange(start: s, end: e) },
                onBeginEdit: { model.beginScrub() },
                onScrub: { t in model.seek(to: t) }
            )
            .frame(height: 56)

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

                Text("截取 \(CompletionNotifier.format(model.start)) – \(CompletionNotifier.format(model.end))　共 \(CompletionNotifier.format(model.trimmedDuration))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            HStack {
                if let status = model.status {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if model.isExporting { ProgressView().controlSize(.small) }
                Button("导出") { model.exportTapped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isExporting || model.duration <= 0)
            }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 430)
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

        // 轨道
        let track = NSBezierPath(roundedRect: NSRect(x: inset, y: midY - trackHeight / 2,
                                                     width: trackWidth, height: trackHeight),
                                 xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()

        // 选中区间
        let selected = NSBezierPath(roundedRect: NSRect(x: sx, y: midY - trackHeight / 2,
                                                        width: max(trackHeight, ex - sx), height: trackHeight),
                                    xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.controlAccentColor.setFill()
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
        NSColor.controlAccentColor.setFill()
        path.fill()
        NSColor.white.setStroke()
        path.lineWidth = 1.5
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
    let onRangeChange: (Double, Double) -> Void
    let onBeginEdit: () -> Void
    let onScrub: (Double) -> Void

    func makeNSView(context: Context) -> TimelineView {
        let view = TimelineView()
        view.duration = duration
        view.start = start
        view.end = end
        view.playhead = playhead
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
