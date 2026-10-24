import AppKit
import SwiftUI


// MARK: - 布局常量

enum TimelineMetrics {
    static let headerWidth: CGFloat = 132
    static let rulerHeight: CGFloat = 24
    static let videoTrackHeight: CGFloat = 64
    static let audioLaneHeight: CGFloat = 44
    static let effectLaneHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 1
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 8
    static let edgeHit: CGFloat = 6
    static let snapPixels: CGFloat = 8
    static let minPPS: Double = 4
    static let maxPPS: Double = 480
}

// MARK: - SwiftUI 桥接

/// 注意：本工具链的 SwiftUI 会按 representable 的【字段值】决定是否调用 updateNSView，
/// class 引用恒等不变会被跳过——因此把所有会变的状态以值类型字段传入。
struct WorkbenchTimeline: NSViewRepresentable {
    let model: WorkbenchViewModel
    let document: WorkbenchDocument
    let currentTime: Double
    let isPlaying: Bool
    let selection: WorkbenchViewModel.Selection?
    let pixelsPerSecond: Double
    let mediaStamp: Int
    let editingAnnotation: UUID?
    let isFullscreen: Bool

    init(model: WorkbenchViewModel) {
        self.model = model
        self.document = model.document
        self.currentTime = model.currentTime
        self.isPlaying = model.isPlaying
        self.selection = model.selection
        self.pixelsPerSecond = model.pixelsPerSecond
        self.mediaStamp = model.mediaStamp
        self.editingAnnotation = model.editingAnnotationID
        self.isFullscreen = model.isFullscreen
    }

    func makeNSView(context: Context) -> WorkbenchTimelineContainer {
        WorkbenchTimelineContainer(model: model)
    }

    func updateNSView(_ view: WorkbenchTimelineContainer, context: Context) {
        view.sync(with: model)
    }
}

// MARK: - 容器：左轨头 + 右滚动区 + 缩放控件

final class WorkbenchTimelineContainer: NSView {
    private let headerColumn = WorkbenchHeaderColumn(frame: .zero)
    private let scrollView = NSScrollView()
    private let canvas = WorkbenchTimelineCanvas(frame: .zero)
    private let playhead = PlayheadOverlayView(frame: .zero)
    private let zoomOut = NSButton(title: "", target: nil, action: nil)
    private let zoomIn = NSButton(title: "", target: nil, action: nil)
    private let zoomSlider = NSSlider(value: 0.4, minValue: 0, maxValue: 1, target: nil, action: nil)

    private var model: WorkbenchViewModel?
    private var didFitZoom = false
    private var lastSignature: Signature?
    private var lastPlayhead: Double = -1

    private struct Signature: Equatable {
        var document: WorkbenchDocument
        var pps: Double
        var thumbs: Int
        var lanesWithWave: Int
        var selection: WorkbenchViewModel.Selection?
        var editingAnnotation: UUID?
        var canvasWidth: CGFloat
    }

    init(model: WorkbenchViewModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        headerColumn.model = model
        addSubview(headerColumn)

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .clear
        scrollView.documentView = canvas
        addSubview(scrollView)

        // 播放头浮层与画布共用滚动坐标：叠在 scrollView 之上，横向偏移由 sync 计算
        addSubview(playhead)

        configureZoomButton(zoomOut, symbol: "minus.magnifyingglass") { [weak self] in self?.zoom(by: 1 / 1.4) }
        configureZoomButton(zoomIn, symbol: "plus.magnifyingglass") { [weak self] in self?.zoom(by: 1.4) }
        zoomSlider.isContinuous = true
        zoomSlider.controlSize = .small
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomSliderChanged)
        zoomSlider.minValue = 0
        zoomSlider.maxValue = 1
        let zoomStack = NSStackView(views: [zoomOut, zoomSlider, zoomIn])
        zoomStack.orientation = .horizontal
        zoomStack.spacing = 4
        zoomStack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        zoomStack.wantsLayer = true
        zoomStack.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        zoomStack.layer?.cornerRadius = 6
        addSubview(zoomStack)
        self.zoomStack = zoomStack

        // 滚动偏移变化时重绘播放头浮层（它按视口坐标画线）
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.playhead.needsDisplay = true
            }
        }
    }

    private var zoomStack: NSStackView?

    required init?(coder: NSCoder) { fatalError("unsupported") }

    private func configureZoomButton(_ button: NSButton, symbol: String, action: @escaping () -> Void) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(zoomButtonAction(_:))
        button.identifier = NSUserInterfaceItemIdentifier(symbol)
        self.zoomAction[symbol] = action
    }

    private var zoomAction: [String: () -> Void] = [:]

    @objc private func zoomButtonAction(_ sender: NSButton) {
        zoomAction[sender.identifier?.rawValue ?? ""]?()
    }

    private func zoom(by factor: Double) {
        guard let model else { return }
        setZoom(model.pixelsPerSecond * factor, anchorTime: visibleCenterTime())
    }

    @objc private func zoomSliderChanged() {
        guard let model else { return }
        let value = zoomSlider.doubleValue
        let pps = TimelineMetrics.minPPS * pow(TimelineMetrics.maxPPS / TimelineMetrics.minPPS, value)
        setZoom(pps, anchorTime: visibleCenterTime())
    }

    private func visibleCenterTime() -> Double {
        let visible = scrollView.contentView.bounds
        return Double(visible.minX + visible.width / 2) / max(model?.pixelsPerSecond ?? 1, 0.001)
    }

    private func setZoom(_ pps: Double, anchorTime anchor: Double) {
        guard let model else { return }
        let clamped = max(TimelineMetrics.minPPS, min(TimelineMetrics.maxPPS, pps))
        guard abs(clamped - model.pixelsPerSecond) > 0.001 else { return }
        let visibleWidth = scrollView.contentView.bounds.width
        model.pixelsPerSecond = clamped
        relayoutContent()
        // 保持锚点时间在视口中的位置不变
        let anchorX = CGFloat(anchor) * CGFloat(clamped)
        let targetOffset = max(0, anchorX - visibleWidth / 2)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: targetOffset, y: 0))
        zoomSlider.doubleValue = log(clamped / TimelineMetrics.minPPS) / log(TimelineMetrics.maxPPS / TimelineMetrics.minPPS)
    }

    // MARK: 布局

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let headerW = TimelineMetrics.headerWidth
        headerColumn.frame = NSRect(x: 0, y: 0, width: headerW, height: bounds.height)
        scrollView.frame = NSRect(x: headerW, y: 0,
                                  width: bounds.width - headerW, height: bounds.height)
        playhead.frame = scrollView.frame
        zoomStack?.frame = NSRect(x: bounds.width - (zoomStack?.fittingSize.width ?? 120) - 8,
                                  y: bounds.height - (zoomStack?.fittingSize.height ?? 26) - 6,
                                  width: zoomStack?.fittingSize.width ?? 120,
                                  height: zoomStack?.fittingSize.height ?? 26)
        if !didFitZoom, let model, model.duration > 0 {
            let visible = scrollView.contentView.bounds.width
            if visible > 10 {
                didFitZoom = true
                let pps = max(TimelineMetrics.minPPS,
                              min(TimelineMetrics.maxPPS, Double(visible - 60) / model.duration))
                if abs(pps - model.pixelsPerSecond) > 0.001 {
                    model.pixelsPerSecond = pps
                }
            }
        }
        relayoutContent()
    }

    private func relayoutContent() {
        guard let model else { return }
        let pps = CGFloat(model.pixelsPerSecond)
        let width = max(scrollView.contentView.bounds.width, CGFloat(model.duration) * pps + 60)
        let height = WorkbenchTimelineCanvas.contentHeight(laneCount: model.document.lanes.count)
        canvas.model = model
        canvas.pps = model.pixelsPerSecond
        let newFrame = NSRect(x: 0, y: 0, width: width, height: height)
        if canvas.frame.size != newFrame.size {
            canvas.frame = newFrame
        }
        playhead.canvas = canvas
        headerColumn.needsDisplay = true
    }

    // MARK: 与 SwiftUI 的同步（每次 @Published 变化都会进来）

    func sync(with model: WorkbenchViewModel) {
        self.model = model
        headerColumn.model = model
        // 时长异步加载完成后做一次自适应缩放（首帧 layout 时 duration 还是 0）
        if !didFitZoom, model.duration > 0 {
            let visible = scrollView.contentView.bounds.width
            if visible > 10 {
                didFitZoom = true
                let pps = max(TimelineMetrics.minPPS,
                              min(TimelineMetrics.maxPPS, Double(visible - 60) / model.duration))
                if abs(pps - model.pixelsPerSecond) > 0.001 {
                    model.pixelsPerSecond = pps
                }
            }
        }
        relayoutContentIfNeeded(model)
        // 播放头：30Hz 高频路径，只刷浮层
        if abs(model.currentTime - lastPlayhead) > 0.0001 {
            lastPlayhead = model.currentTime
            playhead.needsDisplay = true
            if model.isPlaying { autoScrollToPlayhead(model) }
        }
        zoomSlider.doubleValue = log(max(model.pixelsPerSecond, TimelineMetrics.minPPS) / TimelineMetrics.minPPS)
            / log(TimelineMetrics.maxPPS / TimelineMetrics.minPPS)
    }

    private func relayoutContentIfNeeded(_ model: WorkbenchViewModel) {
        var lanesWithWave = 0
        if let media = model.media {
            lanesWithWave = media.waveforms.count
        }
        let signature = Signature(document: model.document,
                                  pps: model.pixelsPerSecond,
                                  thumbs: model.media?.thumbnails.count ?? 0,
                                  lanesWithWave: lanesWithWave,
                                  selection: model.selection,
                                  editingAnnotation: model.editingAnnotationID,
                                  canvasWidth: scrollView.contentView.bounds.width)
        if signature != lastSignature {
            lastSignature = signature
            relayoutContent()
            canvas.needsDisplay = true
            canvas.displayIfNeeded()
            playhead.needsDisplay = true
            headerColumn.refreshButtons()
        }
    }

    private func autoScrollToPlayhead(_ model: WorkbenchViewModel) {
        let pps = CGFloat(model.pixelsPerSecond)
        let playheadX = CGFloat(model.currentTime) * pps
        let visible = scrollView.contentView.bounds
        let margin: CGFloat = 60
        if playheadX < visible.minX + margin || playheadX > visible.maxX - margin {
            let target = max(0, playheadX - visible.width * 0.35)
            scrollView.contentView.setBoundsOrigin(NSPoint(x: target, y: 0))
        }
    }

    // MARK: 手势：捏合缩放

    private var pinchAnchorTime: Double?
    private var pinchBeginPPS: Double?

    override func magnify(with event: NSEvent) {
        switch event.phase {
        case .began:
            pinchAnchorTime = timeUnderPointer(event)
            pinchBeginPPS = model?.pixelsPerSecond
        case .changed:
            guard let model, let begin = pinchBeginPPS, let anchor = pinchAnchorTime else { return }
            let pointerX = scrollView.convert(event.locationInWindow, to: canvas).x
            setZoomAtPointer(begin * Double(event.magnification), anchorTime: anchor, pointerX: pointerX)
        default:
            pinchAnchorTime = nil
            pinchBeginPPS = nil
        }
    }

    private func timeUnderPointer(_ event: NSEvent) -> Double {
        let x = scrollView.convert(event.locationInWindow, to: canvas).x
        return Double(x) / max(model?.pixelsPerSecond ?? 1, 0.001)
    }

    private func setZoomAtPointer(_ pps: Double, anchorTime anchor: Double, pointerX: CGFloat) {
        guard let model else { return }
        let clamped = max(TimelineMetrics.minPPS, min(TimelineMetrics.maxPPS, pps))
        guard abs(clamped - model.pixelsPerSecond) > 0.001 else { return }
        model.pixelsPerSecond = clamped
        relayoutContent()
        let targetOffset = max(0, CGFloat(anchor) * CGFloat(clamped) - pointerX)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: targetOffset, y: 0))
        zoomSlider.doubleValue = log(clamped / TimelineMetrics.minPPS) / log(TimelineMetrics.maxPPS / TimelineMetrics.minPPS)
    }
}

// MARK: - 轨头列

final class WorkbenchHeaderColumn: NSView {
    var model: WorkbenchViewModel?
    private var muteButtons: [NSButton] = []

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = SettingsAppearance.sidebar.cgColor
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    /// 文档/媒体变化后重建静音按钮（位置与右侧波形行对齐）
    func refreshButtons() {
        muteButtons.forEach { $0.removeFromSuperview() }
        muteButtons = []
        guard let model, let superview = superview else { return }
        _ = superview
        for (index, _) in (model.media?.audioTracks ?? []).enumerated() {
            let y = WorkbenchTimelineCanvas.rowY(for: .audio(index), laneCount: model.document.lanes.count)
            let height = TimelineMetrics.audioLaneHeight
            let button = NSButton(title: "", target: self, action: #selector(toggleMute(_:)))
            button.isBordered = false
            button.tag = index
            button.frame = NSRect(x: frame.width - 30, y: y + (height - 18) / 2, width: 22, height: 18)
            styleMuteButton(button, muted: muted(index))
            addSubview(button)
            muteButtons.append(button)
        }
        needsDisplay = true
    }

    private func muted(_ index: Int) -> Bool {
        guard let model, model.document.lanes.indices.contains(index) else { return false }
        return model.document.lanes[index].muted
    }

    private func styleMuteButton(_ button: NSButton, muted: Bool) {
        button.contentTintColor = muted ? SettingsAppearance.error : .secondaryLabelColor
        button.image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                               accessibilityDescription: nil)
    }

    @objc private func toggleMute(_ sender: NSButton) {
        model?.toggleLaneMute(sender.tag)
        styleMuteButton(sender, muted: muted(sender.tag))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let laneCount = model.document.lanes.count
        // 行底色与右侧对应
        for row in WorkbenchTimelineCanvas.allRows(laneCount: laneCount) {
            let rect = NSRect(x: 0, y: row.y, width: frame.width, height: row.height)
            switch row.kind {
            case .ruler:
                continue
            case .video:
                NSColor.labelColor.withAlphaComponent(0.04).setFill()
                rect.fill()
            case .audio:
                NSColor.labelColor.withAlphaComponent(0.02).setFill()
                rect.fill()
            case .focusLane, .annotationLane:
                NSColor.clear.setFill()
                rect.fill()
            }
        }
        // 文案
        let font = NSFont.systemFont(ofSize: 11)
        let color = NSColor.secondaryLabelColor
        func drawLabel(_ text: String, row: WorkbenchTimelineCanvas.Row, inset: CGFloat = 10) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let y = row.y + (row.height - font.capHeight * 1.4) / 2
            (text as NSString).draw(at: NSPoint(x: inset, y: y), withAttributes: attrs)
        }
        drawLabel(L("屏幕视频"), row: WorkbenchTimelineCanvas.rowYRow(for: .video, laneCount: laneCount))
        for (index, track) in (model.media?.audioTracks ?? []).enumerated() {
            drawLabel(track.title, row: WorkbenchTimelineCanvas.rowYRow(for: .audio(index), laneCount: laneCount), inset: 10)
        }
        drawLabel(L("画面聚焦"), row: WorkbenchTimelineCanvas.rowYRow(for: .focusLane, laneCount: laneCount))
        drawLabel(L("标注"), row: WorkbenchTimelineCanvas.rowYRow(for: .annotationLane, laneCount: laneCount))
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        let laneCount = model.document.lanes.count
        for row in WorkbenchTimelineCanvas.allRows(laneCount: laneCount) {
            guard NSRect(x: 0, y: row.y, width: frame.width, height: row.height).contains(p) else { continue }
            switch row.kind {
            case .audio(let index): model.selection = .lane(index)
            default: break
            }
        }
    }
}

// MARK: - 画布（时间轴内容：标尺 + 各轨 + 片段）

final class WorkbenchTimelineCanvas: NSView {
    enum RowKind: Equatable {
        case ruler
        case video
        case audio(Int)
        case focusLane
        case annotationLane
    }

    struct Row {
        let kind: RowKind
        let y: CGFloat
        let height: CGFloat
    }

    var model: WorkbenchViewModel?
    var pps: Double = 60 {
        didSet { waveCacheSignature = nil; needsDisplay = true }
    }

    // 拖拽状态
    private enum DragMode {
        case none, scrub
        case trimLeft(UUID), trimRight(UUID)
        case moveClip(UUID)
        case effectMove(UUID, isFocus: Bool)
        case effectEdge(UUID, isFocus: Bool, left: Bool)
    }

    private var drag: DragMode = .none
    private var dragLastX: CGFloat = 0
    private var dragInsertIndex: Int?
    private var hoverClipID: UUID?
    private var hoverEdge: Bool = false
    private var waveCacheSignature: String?
    private var waveCacheImages: [Int: NSImage] = [:]
    private var trackingArea2: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 几何

    static func contentHeight(laneCount: Int) -> CGFloat {
        var rows = allRows(laneCount: laneCount)
        guard let last = rows.popLast() else { return 100 }
        return last.y + last.height + TimelineMetrics.bottomPadding
    }

    static func allRows(laneCount: Int) -> [Row] {
        var rows: [Row] = []
        var y = TimelineMetrics.topPadding
        func push(_ kind: RowKind, _ height: CGFloat) {
            rows.append(Row(kind: kind, y: y, height: height))
            y += height + TimelineMetrics.rowSpacing
        }
        push(.ruler, TimelineMetrics.rulerHeight)
        push(.video, TimelineMetrics.videoTrackHeight)
        for index in 0..<max(0, laneCount) { push(.audio(index), TimelineMetrics.audioLaneHeight) }
        push(.focusLane, TimelineMetrics.effectLaneHeight)
        push(.annotationLane, TimelineMetrics.effectLaneHeight)
        return rows
    }

    static func rowY(for kind: RowKind, laneCount: Int) -> CGFloat {
        allRows(laneCount: laneCount).first(where: { $0.kind == kind })?.y ?? 0
    }

    static func rowYRow(for kind: RowKind, laneCount: Int) -> Row {
        allRows(laneCount: laneCount).first(where: { $0.kind == kind })
            ?? Row(kind: kind, y: 0, height: 20)
    }

    private func row(atY y: CGFloat) -> Row? {
        guard let model else { return nil }
        return Self.allRows(laneCount: model.document.lanes.count)
            .first(where: { y >= $0.y && y < $0.y + $0.height })
    }

    private func x(for time: Double) -> CGFloat { CGFloat(time) * CGFloat(pps) }
    private func time(forX x: CGFloat) -> Double { Double(x / CGFloat(pps)) }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let document = model.document
        let laneCount = document.lanes.count

        // 行背景
        for row in Self.allRows(laneCount: laneCount) where row.kind != .ruler {
            let rect = NSRect(x: 0, y: row.y, width: frame.width, height: row.height)
            switch row.kind {
            case .video:
                NSColor.labelColor.withAlphaComponent(0.04).setFill()
            case .audio:
                NSColor.labelColor.withAlphaComponent(0.02).setFill()
            default:
                NSColor.clear.setFill()
            }
            rect.fill()
        }

        drawRuler(dirtyRect, model: model)

        // 视频片段
        for (index, clip) in document.clips.enumerated() {
            let start = document.timelineStart(ofClip: clip.id)
            drawClip(clip, timelineStart: start, index: index, model: model)
        }

        // 音轨波形
        for (laneIndex, track) in (model.media?.audioTracks ?? []).enumerated() {
            drawAudioLane(laneIndex: laneIndex, track: track, model: model)
        }

        // 特效轨
        drawEffectLane(kind: .focusLane, items: document.focuses.map { ($0.id, $0.sourceIn, $0.sourceOut) },
                       symbol: "plus.magnifyingglass", model: model)
        drawEffectLane(kind: .annotationLane, items: document.annotations.map { ($0.id, $0.sourceIn, $0.sourceOut) },
                       symbol: "pencil.tip", model: model)
        // 拖动排序的插入线
        if case .moveClip = drag, let index = dragInsertIndex {
            let x = insertionLineX(index: index, model: model)
            drawVerticalLine(at: x, y: 0, height: frame.height,
                             color: SettingsAppearance.accent, dashed: false, width: 2)
        }
    }

    private func drawRuler(_ dirtyRect: NSRect, model: WorkbenchViewModel) {
        guard let row = Self.allRows(laneCount: model.document.lanes.count).first(where: { $0.kind == .ruler }) else { return }
        let rect = NSRect(x: 0, y: row.y, width: frame.width, height: row.height)
        SettingsAppearance.sidebar.setFill()
        rect.fill()

        let steps: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let step = steps.first(where: { CGFloat($0) * CGFloat(pps) >= 70 }) ?? 900
        let minor = step / 5
        let visibleEnd = time(forX: frame.width)

        let minorColor = NSColor.tertiaryLabelColor
        let majorColor = NSColor.secondaryLabelColor
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: majorColor]

        var t = 0.0
        var index = 0
        while t <= visibleEnd + step {
            let x = x(for: t)
            let isMajor = index % 5 == 0
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: rect.maxY - (isMajor ? 7 : 4)))
            line.line(to: NSPoint(x: x, y: rect.maxY))
            (isMajor ? majorColor : minorColor).setStroke()
            line.lineWidth = 1
            line.stroke()
            if isMajor {
                let label = Self.rulerLabel(t)
                let size = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: NSPoint(x: x + 3, y: rect.minY + (rect.height - size.height) / 2),
                                         withAttributes: attrs)
            }
            index += 1
            t = Double(index) * minor
        }
    }

    static func rulerLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func drawClip(_ clip: WorkbenchClip, timelineStart start: Double, index: Int, model: WorkbenchViewModel) {
        let row = Self.rowYRow(for: .video, laneCount: model.document.lanes.count)
        let x0 = x(for: start)
        let width = max(3, CGFloat(clip.duration) * CGFloat(pps))
        let rect = NSRect(x: x0, y: row.y + 2, width: width, height: row.height - 4)
        guard rect.maxX >= 0, rect.minX <= frame.width else { return }

        let isSelected = model.selection == .clip(clip.id)
        let isHovered = hoverClipID == clip.id

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).setClip()

        // 底色（浅色模式下与画布拉开层次，缩略图未就绪时也能看清块范围）
        SettingsAppearance.accent.withAlphaComponent(0.10).setFill()
        rect.fill()

        // 缩略图条
        if let media = model.media, !media.thumbnails.isEmpty, media.thumbnailInterval > 0 {
            let slotWidth = CGFloat(media.thumbnailInterval) * CGFloat(pps)
            let aspect = max(0.1, media.videoAspect)
            let first = max(0, Int(floor(clip.sourceIn / media.thumbnailInterval)) - 1)
            let last = min(media.thumbnails.count - 1, Int(ceil(clip.sourceOut / media.thumbnailInterval)) + 1)
            for k in first...max(first, last) {
                let slotSourceStart = Double(k) * media.thumbnailInterval
                let slotX = x(for: start + (slotSourceStart - clip.sourceIn))
                guard slotX + slotWidth >= rect.minX, slotX <= rect.maxX else { continue }
                let image = media.thumbnails[k]
                // aspect-fill：按轨高铺满、水平居中于槽位
                let drawHeight = rect.height
                let drawWidth = drawHeight * CGFloat(aspect)
                let drawX = slotX + (slotWidth - drawWidth) / 2
                NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    .draw(in: NSRect(x: drawX, y: rect.minY, width: drawWidth, height: drawHeight),
                          from: .zero, operation: .sourceOver, fraction: 0.9)
            }
        }

        if clip.muted {
            NSColor.black.withAlphaComponent(0.35).setFill()
            rect.fill()
            drawTintedSymbol("speaker.slash.fill", at: NSPoint(x: rect.minX + 6, y: rect.midY - 6), size: 12,
                             color: NSColor.white.withAlphaComponent(0.9))
        }

        // 边框
        let borderPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if isSelected {
            SettingsAppearance.accent.setStroke()
            borderPath.lineWidth = 2
        } else if isHovered {
            NSColor.separatorColor.setStroke()
            borderPath.lineWidth = 1
        } else {
            NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
            borderPath.lineWidth = 0.5
        }
        borderPath.stroke()

        // 选中时显示裁剪手柄
        if isSelected {
            for handleX in [rect.minX, rect.maxX] {
                let handleRect = NSRect(x: handleX - 2, y: rect.midY - 10, width: 4, height: 20)
                let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
                SettingsAppearance.accent.setFill()
                path.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // 片段序号
        if width > 34 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            var attrs2 = attrs
            attrs2[.shadow] = shadow
            ("\(index + 1)" as NSString).draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 3), withAttributes: attrs2)
        }
    }

    private func drawAudioLane(laneIndex: Int, track: WorkbenchAudioTrack, model: WorkbenchViewModel) {
        let row = Self.rowYRow(for: .audio(laneIndex), laneCount: model.document.lanes.count)
        let muted = model.document.lanes.indices.contains(laneIndex) && model.document.lanes[laneIndex].muted
        let volume = model.document.lanes.indices.contains(laneIndex) ? model.document.lanes[laneIndex].volume : 1

        let image = waveformImage(laneIndex: laneIndex, track: track, row: row, model: model)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: row.y, width: frame.width, height: row.height)).setClip()
        image.draw(in: NSRect(x: 0, y: row.y, width: image.size.width, height: row.height),
                   from: .zero, operation: .sourceOver, fraction: muted ? 0.25 : 1)
        NSGraphicsContext.restoreGraphicsState()

        if muted {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor,
            ]
            ("已静音" as NSString).draw(at: NSPoint(x: 8, y: row.y + row.height - 14), withAttributes: attrs)
        } else if volume < 0.99 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            ("\(Int(volume * 100))%" as NSString).draw(at: NSPoint(x: 8, y: row.y + row.height - 14), withAttributes: attrs)
        }
    }

    /// 整条音轨的波形图（按当前缩放缓存为位图）
    private func waveformImage(laneIndex: Int, track: WorkbenchAudioTrack, row: WorkbenchTimelineCanvas.Row, model: WorkbenchViewModel) -> NSImage {
        let signature = "\(track.id)-\(pps)-\(frame.width)-\(model.document)-\(model.media?.waveforms[track.id]?.count ?? 0)"
        if signature == waveCacheSignature, let image = waveCacheImages[laneIndex] {
            return image
        }
        waveCacheSignature = signature
        let width = max(1, frame.width)
        let height = row.height
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let midY = height / 2
        if let peaks = model.media?.waveforms[track.id], !peaks.isEmpty,
           let media = model.media, media.duration > 0 {
            let bucket = WorkbenchMedia.waveformBucket
            SettingsAppearance.accent.withAlphaComponent(0.55).setFill()
            let barWidth = CGFloat(bucket) * CGFloat(pps)
            for clip in model.document.clips {
                let start = model.document.timelineStart(ofClip: clip.id)
                let first = max(0, Int(clip.sourceIn / bucket))
                let last = min(peaks.count - 1, Int(ceil(clip.sourceOut / bucket)))
                for i in first...max(first, last) {
                    let peakSourceTime = Double(i) * bucket
                    guard peakSourceTime >= clip.sourceIn - bucket, peakSourceTime <= clip.sourceOut else { continue }
                    let x = CGFloat(start + (peakSourceTime - clip.sourceIn)) * CGFloat(pps)
                    let amp = CGFloat(peaks[i]) * (height - 8) / 2
                    let rect = NSRect(x: x, y: midY - amp, width: max(1, barWidth - 0.5), height: amp * 2)
                    rect.fill()
                }
            }
        } else {
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: midY - 0.5, width: width, height: 1).fill()
        }
        image.unlockFocus()
        waveCacheImages[laneIndex] = image
        return image
    }

    private func drawEffectLane(kind: RowKind, items: [(id: UUID, startIn: Double, startOut: Double)],
                                symbol: String, model: WorkbenchViewModel) {
        guard !items.isEmpty else { return }
        let row = Self.rowYRow(for: kind, laneCount: model.document.lanes.count)
        let editingID: UUID? = {
            switch kind {
            case .focusLane: return model.editingFocusID
            case .annotationLane: return model.editingAnnotationID
            default: return nil
            }
        }()
        guard !items.isEmpty else { return }
        for item in items {
            let x0 = x(for: model.document.timelineTime(forSource: item.startIn))
            let x1 = x(for: model.document.timelineTime(forSource: item.startOut))
            let rect = NSRect(x: x0, y: row.y + 2, width: max(4, x1 - x0), height: row.height - 4)
            guard rect.maxX >= 0, rect.minX <= frame.width else { continue }
            let isSelected = editingID == item.id
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            if isSelected {
                SettingsAppearance.accent.setFill()
            } else {
                SettingsAppearance.accent.withAlphaComponent(0.35).setFill()
            }
            path.fill()
            drawTintedSymbol(symbol, at: NSPoint(x: rect.minX + 4, y: rect.midY - 6), size: 12, color: .white)
        }
    }

    /// 模板符号按指定颜色绘制（NSTextAttachment 会用前景色给模板图标着色）
    private func drawTintedSymbol(_ name: String, at point: NSPoint, size: CGFloat, color: NSColor) {
        guard let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        icon.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = icon
        attachment.bounds = NSRect(x: 0, y: 0, width: size, height: size)
        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: 1))
        text.draw(at: point)
    }

    private func drawVerticalLine(at x: CGFloat, y: CGFloat, height: CGFloat, color: NSColor, dashed: Bool, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: y))
        path.line(to: NSPoint(x: x, y: y + height))
        color.setStroke()
        path.lineWidth = width
        if dashed {
            path.setLineDash([4, 3], count: 2, phase: 0)
        }
        path.stroke()
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        dragLastX = p.x
        guard let row = row(atY: p.y) else { return }

        switch row.kind {
        case .ruler:
            drag = .scrub
            model.beginScrub()
            model.seek(to: time(forX: p.x))
        case .video:
            handleVideoMouseDown(p, model: model)
        case .audio(let index):
            model.selection = .lane(index)
        case .focusLane:
            handleEffectMouseDown(p, model: model, isFocus: true)
        case .annotationLane:
            handleEffectMouseDown(p, model: model, isFocus: false)
        }
    }

    private func handleVideoMouseDown(_ p: NSPoint, model: WorkbenchViewModel) {
        let document = model.document
        // 找命中片段
        for clip in document.clips {
            let start = document.timelineStart(ofClip: clip.id)
            let x0 = x(for: start)
            let x1 = x(for: start + clip.duration)
            guard p.x >= x0 - TimelineMetrics.edgeHit, p.x <= x1 + TimelineMetrics.edgeHit else { continue }
            model.selection = .clip(clip.id)
            let t = time(forX: p.x)
            // 边缘 → 裁剪；内部 → 排序拖动
            if abs(p.x - x0) <= TimelineMetrics.edgeHit {
                drag = .trimLeft(clip.id)
                model.beginUndoableDrag()
                model.beginScrub()
                model.seek(to: start)
                needsDisplay = true
                return
            }
            if abs(p.x - x1) <= TimelineMetrics.edgeHit {
                drag = .trimRight(clip.id)
                model.beginUndoableDrag()
                model.beginScrub()
                model.seek(to: start + clip.duration)
                needsDisplay = true
                return
            }
            if t >= start, t <= start + clip.duration {
                drag = .moveClip(clip.id)
                dragInsertIndex = nil
                needsDisplay = true
                return
            }
        }
        // 空白：取消选择并定位
        model.selection = nil
        model.beginScrub()
        model.seek(to: time(forX: p.x))
    }

    private func handleEffectMouseDown(_ p: NSPoint, model: WorkbenchViewModel, isFocus: Bool) {
        let document = model.document
        let items: [(id: UUID, startIn: Double, startOut: Double)] = isFocus
            ? document.focuses.map { ($0.id, $0.sourceIn, $0.sourceOut) }
            : document.annotations.map { ($0.id, $0.sourceIn, $0.sourceOut) }
        for item in items {
            let x0 = x(for: document.timelineTime(forSource: item.startIn))
            let x1 = x(for: document.timelineTime(forSource: item.startOut))
            guard p.x >= x0 - TimelineMetrics.edgeHit, p.x <= x1 + TimelineMetrics.edgeHit else { continue }
            if abs(p.x - x0) <= TimelineMetrics.edgeHit {
                drag = .effectEdge(item.id, isFocus: isFocus, left: true)
                model.beginUndoableDrag()
                model.beginScrub()
                return
            }
            if abs(p.x - x1) <= TimelineMetrics.edgeHit {
                drag = .effectEdge(item.id, isFocus: isFocus, left: false)
                model.beginUndoableDrag()
                model.beginScrub()
                return
            }
            if p.x > x0, p.x < x1 {
                drag = .effectMove(item.id, isFocus: isFocus)
                model.beginUndoableDrag()
                model.beginScrub()
                if isFocus { model.beginFocusEdit(item.id) } else { model.beginAnnotationSelection(item.id) }
                return
            }
        }
        model.selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dt = time(forX: p.x - dragLastX)
        dragLastX = p.x
        let document = model.document

        switch drag {
        case .scrub:
            model.seek(to: time(forX: p.x))

        case .trimLeft(let id):
            guard let clip = document.clips.first(where: { $0.id == id }) else { return }
            let start = document.timelineStart(ofClip: id)
            let raw = time(forX: p.x)
            let snapped = snap(raw, excluding: id, model: model)
            let newIn = max(0, min(clip.sourceOut - 0.05, snapped - start))
            model.updateClipRange(id: id, sourceIn: newIn, sourceOut: clip.sourceOut)
            model.seek(to: max(start, snapped))
            needsDisplay = true

        case .trimRight(let id):
            guard let clip = document.clips.first(where: { $0.id == id }) else { return }
            let start = document.timelineStart(ofClip: id)
            let raw = time(forX: p.x)
            let snapped = snap(raw, excluding: id, model: model)
            let newOut = min(model.duration, max(clip.sourceIn + 0.05, snapped - start + clip.sourceIn))
            model.updateClipRange(id: id, sourceIn: clip.sourceIn, sourceOut: newOut)
            model.seek(to: max(start, min(document.duration, snapped)))
            needsDisplay = true

        case .moveClip(let id):
            let t = time(forX: p.x)
            let index = insertionIndex(forDraggedID: id, atTime: t, model: model)
            if index != dragInsertIndex {
                dragInsertIndex = index
                needsDisplay = true
            }

        case .effectMove(let id, let isFocus):
            shiftEffect(id: id, isFocus: isFocus, delta: dt, model: model)

        case .effectEdge(let id, let isFocus, let left):
            stretchEffect(id: id, isFocus: isFocus, left: left, atTimeline: time(forX: p.x), model: model)
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
            if let index = dragInsertIndex {
                model.moveClip(id: id, toIndex: index)
            }
            dragInsertIndex = nil
        case .effectMove, .effectEdge:
            model.refreshOverlays()
            needsDisplay = true
        default:
            break
        }
        drag = .none
    }

    // MARK: 特效拖拽（源时间 ↔ 时间轴投影）

    private func shiftEffect(id: UUID, isFocus: Bool, delta: Double, model: WorkbenchViewModel) {
        let duration = model.duration
        guard duration > 0 else { return }
        if isFocus, let index = model.document.focuses.firstIndex(where: { $0.id == id }) {
            var effect = model.document.focuses[index]
            let length = effect.sourceOut - effect.sourceIn
            var newIn = max(0, min(duration - length, effect.sourceIn + delta))
            newIn = max(0, min(duration - length, newIn))
            effect.sourceIn = newIn
            effect.sourceOut = newIn + length
            model.updateFocus(effect)
        } else if let index = model.document.annotations.firstIndex(where: { $0.id == id }) {
            var segment = model.document.annotations[index]
            let length = segment.sourceOut - segment.sourceIn
            let newIn = max(0, min(duration - length, segment.sourceIn + delta))
            segment.sourceIn = newIn
            segment.sourceOut = newIn + length
            model.updateAnnotationRange(segment)
        }
        needsDisplay = true
    }

    private func stretchEffect(id: UUID, isFocus: Bool, left: Bool, atTimeline t: Double, model: WorkbenchViewModel) {
        guard let source = model.document.sourceTime(atTimeline: max(0, t)) else { return }
        if isFocus, let index = model.document.focuses.firstIndex(where: { $0.id == id }) {
            var effect = model.document.focuses[index]
            if left {
                effect.sourceIn = max(0, min(effect.sourceOut - 0.1, source))
            } else {
                effect.sourceOut = max(effect.sourceIn + 0.1, min(model.media?.duration ?? effect.sourceOut, source))
            }
            model.updateFocus(effect)
        } else if let index = model.document.annotations.firstIndex(where: { $0.id == id }) {
            var segment = model.document.annotations[index]
            if left {
                segment.sourceIn = max(0, min(segment.sourceOut - 0.1, source))
            } else {
                segment.sourceOut = max(segment.sourceIn + 0.1, min(model.media?.duration ?? segment.sourceOut, source))
            }
            model.updateAnnotationRange(segment)
        }
    }

    // MARK: 吸附与排序

    /// 吸附到播放头 / 其他片段边缘 / 文档首尾；返回吸附后的时间
    private func snap(_ raw: Double, excluding id: UUID, model: WorkbenchViewModel) -> Double {
        let threshold = Double(TimelineMetrics.snapPixels / CGFloat(pps))
        var candidates: [Double] = [0, model.duration, model.currentTime]
        for clip in model.document.clips where clip.id != id {
            candidates.append(model.document.timelineStart(ofClip: clip.id))
            candidates.append(model.document.timelineStart(ofClip: clip.id) + clip.duration)
        }
        guard let nearest = candidates.min(by: { abs($0 - raw) < abs($1 - raw) }),
              abs(nearest - raw) <= threshold else { return raw }
        return nearest
    }

    private func insertionIndex(forDraggedID id: UUID, atTime t: Double, model: WorkbenchViewModel) -> Int {
        var index = 0
        var acc = 0.0
        for clip in model.document.clips where clip.id != id {
            if t > acc + clip.duration / 2 { index += 1 }
            acc += clip.duration
        }
        return index
    }

    private func insertionLineX(index: Int, model: WorkbenchViewModel) -> CGFloat {
        var acc = 0.0
        var seen = 0
        for clip in model.document.clips where clip.id != dragCurrentID() {
            if seen == index { break }
            acc += clip.duration
            seen += 1
        }
        return x(for: acc)
    }

    private func dragCurrentID() -> UUID? {
        if case .moveClip(let id) = drag { return id }
        return nil
    }

    // MARK: 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea2 { removeTrackingArea(trackingArea2) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea2 = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        var newHover: UUID?
        var edge = false
        if let row = row(atY: p.y), row.kind == .video {
            for clip in model.document.clips {
                let start = model.document.timelineStart(ofClip: clip.id)
                let x0 = x(for: start)
                let x1 = x(for: start + clip.duration)
                if p.x >= x0, p.x <= x1 {
                    newHover = clip.id
                    edge = abs(p.x - x0) <= TimelineMetrics.edgeHit || abs(p.x - x1) <= TimelineMetrics.edgeHit
                    break
                }
            }
        }
        if newHover != hoverClipID || edge != hoverEdge {
            hoverClipID = newHover
            hoverEdge = edge
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverClipID != nil {
            hoverClipID = nil
            hoverEdge = false
            needsDisplay = true
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if hoverEdge {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        guard let row = row(atY: p.y) else { return nil }
        let menu = NSMenu()
        switch row.kind {
        case .video:
            let t = time(forX: p.x)
            if let (clip, _, _) = model.document.clip(atTimeline: t) {
                model.selection = .clip(clip.id)
                let split = NSMenuItem(title: L("在播放头处分割"), action: #selector(menuSplit), keyEquivalent: "")
                split.target = self
                menu.addItem(split)
                let muteTitle = clip.muted ? L("取消片段静音") : L("片段静音")
                let mute = NSMenuItem(title: muteTitle, action: #selector(menuToggleMute), keyEquivalent: "")
                mute.target = self
                menu.addItem(mute)
                if model.document.clips.count > 1 {
                    let delete = NSMenuItem(title: L("删除片段"), action: #selector(menuDeleteClip), keyEquivalent: "")
                    delete.target = self
                    menu.addItem(delete)
                }
            }
        case .audio(let index):
            model.selection = .lane(index)
            let lane = model.document.lanes.indices.contains(index) ? model.document.lanes[index] : nil
            let title = (lane?.muted ?? false) ? L("取消静音") : L("整轨静音")
            let item = NSMenuItem(title: title, action: #selector(menuToggleLaneMute(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            menu.addItem(item)
        case .focusLane:
            if let focus = hitEffect(p, isFocus: true, model: model) {
                model.selection = .focus(focus)
                let item = NSMenuItem(title: L("删除聚焦"), action: #selector(menuDeleteFocus), keyEquivalent: "")
                item.representedObject = focus
                item.target = self
                menu.addItem(item)
            }
        case .annotationLane:
            if let annotation = hitEffect(p, isFocus: false, model: model) {
                model.selection = .annotation(annotation)
                let item = NSMenuItem(title: L("删除标注段"), action: #selector(menuDeleteAnnotation), keyEquivalent: "")
                item.representedObject = annotation
                item.target = self
                menu.addItem(item)
            }
        default:
            return nil
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func hitEffect(_ p: NSPoint, isFocus: Bool, model: WorkbenchViewModel) -> UUID? {
        let document = model.document
        let items: [(id: UUID, startIn: Double, startOut: Double)] = isFocus
            ? document.focuses.map { ($0.id, $0.sourceIn, $0.sourceOut) }
            : document.annotations.map { ($0.id, $0.sourceIn, $0.sourceOut) }
        for item in items {
            let x0 = x(for: document.timelineTime(forSource: item.startIn))
            let x1 = x(for: document.timelineTime(forSource: item.startOut))
            if p.x >= x0, p.x <= x1 { return item.id }
        }
        return nil
    }

    @objc private func menuSplit() { model?.splitAtPlayhead() }
    @objc private func menuToggleMute() {
        guard let model, case .clip(let id)? = model.selection else { return }
        model.toggleClipMute(id)
    }
    @objc private func menuDeleteClip() {
        guard let model, case .clip(let id)? = model.selection else { return }
        model.deleteClip(id)
    }
    @objc private func menuToggleLaneMute(_ sender: NSMenuItem) {
        model?.toggleLaneMute(sender.tag)
    }
    @objc private func menuDeleteFocus(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model?.removeFocus(id)
    }
    @objc private func menuDeleteAnnotation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model?.removeAnnotation(id)
    }
}

// MARK: - 播放头浮层（30Hz 只重绘自己）

final class PlayheadOverlayView: NSView {
    weak var canvas: WorkbenchTimelineCanvas?
    var currentTime: Double = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, let model = canvas.model, model.duration > 0 else { return }
        // 画布坐标 → 滚动视口坐标（横向要减去滚动偏移）
        let scrollOffset = canvas.superview.map { scrollViewOffset($0) } ?? 0
        let x = CGFloat(model.currentTime) * CGFloat(canvas.pps) - scrollOffset
        guard x >= -6, x <= bounds.width + 6 else { return }
        // 顶部三角
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: x - 5, y: 1))
        triangle.line(to: NSPoint(x: x + 5, y: 1))
        triangle.line(to: NSPoint(x: x, y: 9))
        triangle.close()
        SettingsAppearance.accent.setFill()
        triangle.fill()
        // 竖线
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: 0))
        line.line(to: NSPoint(x: x, y: bounds.height))
        SettingsAppearance.accent.setStroke()
        line.lineWidth = 1
        line.stroke()
    }

    private func scrollViewOffset(_ container: NSView) -> CGFloat {
        // canvas 是 scrollView 的 documentView，浮层与 scrollView 同级；
        // 滚动偏移从 scrollView 的 contentView 取
        for case let scrollView as NSScrollView in container.subviews {
            return scrollView.contentView.bounds.minX
        }
        return 0
    }
}
