import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

// MARK: - 上：波形展示（可点按拖动定位）

/// 大波形视图：按音轨分行展示，裁剪掉的区域压暗、音量段覆盖显示、
/// 播放头可拖动定位。值字段驱动刷新（同 WorkbenchTimeline 的约定）。
struct AudioWaveform: NSViewRepresentable {
    let model: WorkbenchViewModel
    let currentTime: Double
    let duration: Double
    let document: WorkbenchDocument
    let waveStamp: Int

    init(model: WorkbenchViewModel) {
        self.model = model
        self.currentTime = model.currentTime
        self.duration = model.duration
        self.document = model.document
        self.waveStamp = model.mediaStamp
    }

    func makeNSView(context: Context) -> AudioWaveformView {
        let view = AudioWaveformView()
        view.onScrub = { [weak model] in model?.beginScrub() }
        view.onSeek = { [weak model] time in model?.seek(to: time) }
        return view
    }

    func updateNSView(_ view: AudioWaveformView, context: Context) {
        view.configure(document: document,
                       duration: duration,
                       currentTime: currentTime,
                       waveforms: model.media?.waveforms ?? [:],
                       trackOrder: model.media?.audioTracks.map(\.id) ?? [],
                       gains: document.audioGains,
                       laneCount: document.lanes.count)
    }
}

final class AudioWaveformView: NSView {
    var onScrub: (() -> Void)?
    var onSeek: ((Double) -> Void)?

    private var document = WorkbenchDocument()
    private var duration: Double = 0
    private var currentTime: Double = 0
    private var waveforms: [CMPersistentTrackID: [Float]] = [:]
    private var trackOrder: [CMPersistentTrackID] = []
    private var dragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(document: WorkbenchDocument, duration: Double, currentTime: Double,
                   waveforms: [CMPersistentTrackID: [Float]], trackOrder: [CMPersistentTrackID],
                   gains: [WorkbenchAudioGain], laneCount: Int) {
        self.document = document
        self.duration = duration
        self.currentTime = currentTime
        self.waveforms = waveforms
        self.trackOrder = trackOrder
        self.gainSegments = gains
        needsDisplay = true
    }

    private var gainSegments: [WorkbenchAudioGain] = []

    private func x(for time: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        return bounds.minX + CGFloat(time / duration) * bounds.width
    }

    private func time(atX px: CGFloat) -> Double {
        guard duration > 0, bounds.width > 0 else { return 0 }
        return max(0, min(duration, Double((px - bounds.minX) / bounds.width) * duration))
    }

    override func draw(_ dirtyRect: NSRect) {
        let stripCount = max(1, trackOrder.count)
        let stripHeight = bounds.height / CGFloat(stripCount)
        let bucket = WorkbenchMedia.waveformBucket

        for (strip, trackID) in trackOrder.enumerated() {
            let stripRect = CGRect(x: 0, y: CGFloat(strip) * stripHeight,
                                   width: bounds.width, height: stripHeight)
            let midY = stripRect.midY
            guard let peaks = waveforms[trackID], !peaks.isEmpty else {
                NSColor.separatorColor.setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 0, y: midY))
                line.line(to: NSPoint(x: bounds.width, y: midY))
                line.lineWidth = 1
                line.stroke()
                continue
            }
            // 整段淡底 → 活跃区间实色
            SettingsAppearance.accent.withAlphaComponent(0.18).setFill()
            for clip in document.clips {
                let start = document.timelineStart(ofClip: clip.id)
                let x0 = x(for: start)
                let x1 = x(for: start + clip.duration)
                let first = max(0, Int(clip.sourceIn / bucket))
                let last = min(peaks.count - 1, Int(ceil(clip.sourceOut / bucket)))
                let clipWidth = max(1, x1 - x0)
                let buckets = max(1, last - first + 1)
                let barWidth = clipWidth / CGFloat(buckets)
                for i in first...max(first, last) {
                    let peakTime = Double(i) * bucket
                    guard peakTime >= clip.sourceIn - bucket, peakTime <= clip.sourceOut else { continue }
                    let barX = x0 + CGFloat(i - first) * barWidth
                    let amp = CGFloat(peaks[i]) * (stripHeight - 12) / 2
                    NSRect(x: barX, y: midY - amp, width: max(0.5, barWidth - 0.5), height: amp * 2).fill()
                }
            }
            // 音量段：横线高度 = 音量，覆盖显示
            for gain in gainSegments where trackOrder.indices.contains(gain.laneIndex)
                && trackOrder[gain.laneIndex] == trackID {
                let x0 = x(for: document.timelineTime(forSource: gain.sourceIn))
                let x1 = x(for: document.timelineTime(forSource: gain.sourceOut))
                let top = stripRect.minY + 4
                let levelY = stripRect.maxY - 4 - (stripHeight - 8) * CGFloat(gain.volume)
                let rect = NSRect(x: x0, y: top, width: max(2, x1 - x0), height: stripHeight - 8)
                (gain.volume == 0 ? SettingsAppearance.warning : SettingsAppearance.accent)
                    .withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                let level = NSBezierPath()
                level.move(to: NSPoint(x: x0, y: levelY))
                level.line(to: NSPoint(x: x1, y: levelY))
                (gain.volume == 0 ? SettingsAppearance.warning : SettingsAppearance.accent).setStroke()
                level.lineWidth = 1.5
                level.stroke()
            }
        }

        // 播放头
        if duration > 0 {
            let px = x(for: currentTime)
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: px - 5, y: 1))
            triangle.line(to: NSPoint(x: px + 5, y: 1))
            triangle.line(to: NSPoint(x: px, y: 8))
            triangle.close()
            SettingsAppearance.accent.setFill()
            triangle.fill()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: px, y: 0))
            line.line(to: NSPoint(x: px, y: bounds.height))
            SettingsAppearance.accent.setStroke()
            line.lineWidth = 1.5
            line.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        onScrub?()
        onSeek?(time(atX: convert(event.locationInWindow, from: nil).x))
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onSeek?(time(atX: convert(event.locationInWindow, from: nil).x))
    }

    override func mouseUp(with event: NSEvent) { dragging = false }
}

// MARK: - 下：时间轴（标尺 + 片段行 + 各音轨音量行）

struct AudioTimeline: NSViewRepresentable {
    let model: WorkbenchViewModel
    let document: WorkbenchDocument
    let currentTime: Double
    let duration: Double
    let selection: WorkbenchViewModel.Selection?
    let mediaStamp: Int

    init(model: WorkbenchViewModel) {
        self.model = model
        self.document = model.document
        self.currentTime = model.currentTime
        self.duration = model.duration
        self.selection = model.selection
        self.mediaStamp = model.mediaStamp
    }

    func makeNSView(context: Context) -> AudioTimelineView {
        let view = AudioTimelineView()
        view.model = model
        return view
    }

    func updateNSView(_ view: AudioTimelineView, context: Context) {
        view.model = model
        view.needsDisplay = true
    }
}

final class AudioTimelineView: NSView {
    var model: WorkbenchViewModel? {
        didSet { needsDisplay = true }
    }

    private let headerWidth: CGFloat = 76
    private let rulerHeight: CGFloat = 20
    private let clipLaneHeight: CGFloat = 40
    private let gainLaneHeight: CGFloat = 30
    private let edgeHit: CGFloat = 6

    private enum Drag {
        case none, scrub
        case trimLeft(UUID), trimRight(UUID), moveClip(UUID)
        case gainMove(UUID), gainEdge(UUID, left: Bool)
        case createGain(Int)
    }

    private var drag: Drag = .none
    private var dragLastX: CGFloat = 0
    private var createAnchor: Double = 0
    private var createCurrent: Double = 0
    private var insertIndex: Int?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 几何

    private var timelineFrame: CGRect {
        NSRect(x: headerWidth, y: 0, width: max(1, bounds.width - headerWidth), height: bounds.height)
    }

    private var pps: CGFloat {
        guard let model, model.duration > 0 else { return 1 }
        return timelineFrame.width / CGFloat(model.duration)
    }

    private func x(for time: Double) -> CGFloat { timelineFrame.minX + CGFloat(time) * pps }
    private func time(atX px: CGFloat) -> Double {
        guard let model else { return 0 }
        return max(0, min(model.duration, Double((px - timelineFrame.minX) / max(pps, 0.001))))
    }

    private func clipLaneRect() -> CGRect {
        NSRect(x: 0, y: rulerHeight, width: bounds.width, height: clipLaneHeight)
    }

    private func gainLaneRect(_ index: Int) -> CGRect {
        NSRect(x: 0, y: rulerHeight + clipLaneHeight + CGFloat(index) * (gainLaneHeight + 1),
               width: bounds.width, height: gainLaneHeight)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let document = model.document

        // 标尺
        SettingsAppearance.sidebar.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: rulerHeight).fill()
        drawRuler()

        // 片段行
        NSColor.labelColor.withAlphaComponent(0.03).setFill()
        clipLaneRect().fill()
        for (index, clip) in document.clips.enumerated() {
            drawClip(clip, index: index, selected: model.selection == .clip(clip.id))
        }

        // 音量行
        for laneIndex in 0..<document.lanes.count {
            let rect = gainLaneRect(laneIndex)
            NSColor.labelColor.withAlphaComponent(0.02).setFill()
            rect.fill()
            drawGains(laneIndex: laneIndex, rect: rect)
        }

        // 轨头文字
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (L("片段") as NSString).draw(at: NSPoint(x: 8, y: clipLaneRect().midY - 6), withAttributes: attrs)
        for (laneIndex, track) in (model.media?.audioTracks ?? []).enumerated() where laneIndex < document.lanes.count {
            (L("音量 · ") + track.title as NSString).draw(at: NSPoint(x: 8, y: gainLaneRect(laneIndex).midY - 5),
                                                          withAttributes: attrs)
        }

        // 拖拽创建预览
        if case .createGain = drag {
            let row = gainLaneRect(createLane)
            let x0 = x(for: min(createAnchor, createCurrent))
            let x1 = x(for: max(createAnchor, createCurrent))
            let rect = NSRect(x: x0, y: row.minY + 2, width: max(2, x1 - x0), height: row.height - 4)
            SettingsAppearance.accent.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }

        // 播放头
        let px = x(for: model.currentTime)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: px, y: 0))
        line.line(to: NSPoint(x: px, y: bounds.height))
        SettingsAppearance.accent.setStroke()
        line.lineWidth = 1.5
        line.stroke()
    }

    private var createLane = 0

    private func drawRuler() {
        guard let model else { return }
        let steps: [Double] = [0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        let step = steps.first { CGFloat($0) * pps >= 64 } ?? 600
        let minor = step / 4
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        var t = 0.0
        var index = 0
        while t <= model.duration + minor {
            let x = self.x(for: t)
            let isMajor = index % 4 == 0
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: rulerHeight - (isMajor ? 6 : 3)))
            line.line(to: NSPoint(x: x, y: rulerHeight))
            (isMajor ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
            line.lineWidth = 1
            line.stroke()
            if isMajor {
                let label = String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
                (label as NSString).draw(at: NSPoint(x: x + 3, y: 3), withAttributes: attrs)
            }
            index += 1
            t = Double(index) * minor
        }
    }

    private func drawClip(_ clip: WorkbenchClip, index: Int, selected: Bool) {
        guard let model else { return }
        let document = model.document
        let start = document.timelineStart(ofClip: clip.id)
        let row = clipLaneRect().insetBy(dx: 0, dy: 3)
        let x0 = x(for: start)
        let x1 = x(for: start + clip.duration)
        let rect = NSRect(x: x0, y: row.minY, width: max(4, x1 - x0), height: row.height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        SettingsAppearance.accent.withAlphaComponent(selected ? 0.32 : 0.16).setFill()
        path.fill()
        selected ? SettingsAppearance.accent.setStroke() : SettingsAppearance.separator.setStroke()
        path.lineWidth = selected ? 1.5 : 0.5
        path.stroke()
        // 序号
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        if rect.width > 26 {
            ("\(index + 1)" as NSString).draw(at: NSPoint(x: rect.minX + 7, y: rect.midY - 6), withAttributes: attrs)
        }
        // 淡入淡出斜线
        if clip.fadeIn > 0 {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX, y: rect.minY + 3))
            line.line(to: NSPoint(x: x(for: start + clip.fadeIn), y: rect.maxY - 3))
            NSColor.secondaryLabelColor.setStroke()
            line.lineWidth = 1
            line.stroke()
        }
        if clip.fadeOut > 0 {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.maxX, y: rect.minY + 3))
            line.line(to: NSPoint(x: x(for: start + clip.duration - clip.fadeOut), y: rect.maxY - 3))
            NSColor.secondaryLabelColor.setStroke()
            line.lineWidth = 1
            line.stroke()
        }
        if clip.muted {
            let attrs2: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor,
            ]
            (L("已静音") as NSString).draw(at: NSPoint(x: rect.minX + 20, y: rect.midY - 5), withAttributes: attrs2)
        }
    }

    private func drawGains(laneIndex: Int, rect: CGRect) {
        guard let model else { return }
        for gain in model.document.audioGains where gain.laneIndex == laneIndex {
            let x0 = x(for: model.document.timelineTime(forSource: gain.sourceIn))
            let x1 = x(for: model.document.timelineTime(forSource: gain.sourceOut))
            let block = NSRect(x: x0, y: rect.minY + 2, width: max(4, x1 - x0), height: rect.height - 4)
            let path = NSBezierPath(roundedRect: block, xRadius: 5, yRadius: 5)
            (gain.volume == 0 ? SettingsAppearance.warning : SettingsAppearance.accent)
                .withAlphaComponent(model.selection == .audioGain(gain.id) ? 0.6 : 0.35).setFill()
            path.fill()
            if block.width > 30 {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                ]
                let label = gain.volume == 0 ? L("已静音") : "\(Int(gain.volume * 100))%"
                (label as NSString).draw(at: NSPoint(x: block.midX - 16, y: block.midY - 5), withAttributes: attrs)
            }
        }
    }

    // MARK: 交互

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        dragLastX = p.x
        createLane = 0

        // 标尺 → 定位
        if p.y < rulerHeight {
            drag = .scrub
            model.beginScrub()
            model.seek(to: time(atX: p.x))
            return
        }
        // 片段行
        if clipLaneRect().contains(p) {
            for clip in model.document.clips {
                let start = model.document.timelineStart(ofClip: clip.id)
                let x0 = x(for: start)
                let x1 = x(for: start + clip.duration)
                guard p.x >= x0 - edgeHit, p.x <= x1 + edgeHit else { continue }
                model.selection = .clip(clip.id)
                if abs(p.x - x0) <= edgeHit {
                    drag = .trimLeft(clip.id)
                    model.beginUndoableDrag()
                    model.beginScrub()
                    return
                }
                if abs(p.x - x1) <= edgeHit {
                    drag = .trimRight(clip.id)
                    model.beginUndoableDrag()
                    model.beginScrub()
                    return
                }
                if p.x > x0, p.x < x1 {
                    drag = .moveClip(clip.id)
                    insertIndex = nil
                    return
                }
            }
            model.selection = nil
            return
        }
        // 音量行：段命中 / 空白拖拽创建
        for laneIndex in 0..<model.document.lanes.count where gainLaneRect(laneIndex).contains(p) {
            createLane = laneIndex
            model.selection = .lane(laneIndex)
            for gain in model.document.audioGains where gain.laneIndex == laneIndex {
                let x0 = x(for: model.document.timelineTime(forSource: gain.sourceIn))
                let x1 = x(for: model.document.timelineTime(forSource: gain.sourceOut))
                guard p.x >= x0 - edgeHit, p.x <= x1 + edgeHit else { continue }
                model.selection = .audioGain(gain.id)
                if abs(p.x - x0) <= edgeHit {
                    drag = .gainEdge(gain.id, left: true)
                    model.beginUndoableDrag()
                    return
                }
                if abs(p.x - x1) <= edgeHit {
                    drag = .gainEdge(gain.id, left: false)
                    model.beginUndoableDrag()
                    return
                }
                if p.x > x0, p.x < x1 {
                    drag = .gainMove(gain.id)
                    model.beginUndoableDrag()
                    return
                }
            }
            drag = .createGain(laneIndex)
            createAnchor = time(atX: p.x)
            createCurrent = createAnchor
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dt = Double((p.x - dragLastX) / max(pps, 0.001))
        dragLastX = p.x
        switch drag {
        case .scrub:
            model.seek(to: time(atX: p.x))
        case .trimLeft(let id):
            guard let clip = model.document.clips.first(where: { $0.id == id }) else { return }
            let start = model.document.timelineStart(ofClip: id)
            let newIn = max(0, min(clip.sourceOut - 0.05, time(atX: p.x) - start))
            model.updateClipRange(id: id, sourceIn: newIn, sourceOut: clip.sourceOut)
            needsDisplay = true
        case .trimRight(let id):
            guard let clip = model.document.clips.first(where: { $0.id == id }) else { return }
            let start = model.document.timelineStart(ofClip: id)
            let newOut = min(model.duration, max(clip.sourceIn + 0.05, time(atX: p.x) - start + clip.sourceIn))
            model.updateClipRange(id: id, sourceIn: clip.sourceIn, sourceOut: newOut)
            needsDisplay = true
        case .moveClip(let id):
            let t = time(atX: p.x)
            var index = 0
            var acc = 0.0
            for clip in model.document.clips where clip.id != id {
                if t > acc + clip.duration / 2 { index += 1 }
                acc += clip.duration
            }
            if index != insertIndex {
                insertIndex = index
                needsDisplay = true
            }
        case .gainMove(let id):
            guard let gain = model.document.audioGains.first(where: { $0.id == id }) else { return }
            var updated = gain
            let length = updated.sourceOut - updated.sourceIn
            let newIn = max(0, min(model.duration - length, updated.sourceIn + dt))
            updated.sourceIn = newIn
            updated.sourceOut = newIn + length
            model.updateGain(updated)
            needsDisplay = true
        case .gainEdge(let id, let left):
            guard let gain = model.document.audioGains.first(where: { $0.id == id }),
                  let source = model.document.sourceTime(atTimeline: max(0, time(atX: p.x))) else { return }
            var updated = gain
            if left {
                updated.sourceIn = max(0, min(updated.sourceOut - 0.2, source))
            } else {
                updated.sourceOut = max(updated.sourceIn + 0.2, min(model.media?.duration ?? updated.sourceOut, source))
            }
            model.updateGain(updated)
            needsDisplay = true
        case .createGain:
            createCurrent = max(0, min(model.duration, time(atX: p.x)))
            needsDisplay = true
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        switch drag {
        case .trimLeft, .trimRight:
            model.endTrim()
        case .moveClip(let id):
            if let index = insertIndex {
                model.moveClip(id: id, toIndex: index)
            }
            insertIndex = nil
        case .gainMove, .gainEdge:
            break
        case .createGain(let lane):
            let a = min(createAnchor, createCurrent)
            let b = max(createAnchor, createCurrent)
            if b - a >= 0.2 {
                model.createGainRange(laneIndex: lane, timelineStart: a, timelineEnd: b)
            }
        default:
            break
        }
        drag = .none
        needsDisplay = true
    }
}
