import AVFoundation
import AppKit
import SwiftUI

/// 录屏后期工作台的视图模型：磁性时间轴文档 + 播放 + 撤销/重做 + 导出。
/// 结构性变更（分割/删除/裁剪/重排）重建 AVMutableComposition；
/// 参数性变更（音量/静音/淡入淡出/特效）只更新 videoComposition/audioMix。
@MainActor
final class WorkbenchViewModel: ObservableObject {
    enum Selection: Equatable {
        case clip(UUID)
        case lane(Int)
        case focus(UUID)
        case annotation(UUID)
        case audioGain(UUID)
    }

    let sourceURL: URL
    var origin: TrimOrigin = .manual

    /// 程序主动关闭（导出成功/删除）时跳过关窗确认
    var isProgrammaticClose = false
    var requestClose: (() -> Void)?

    let player: AVPlayer
    /// 加载成功才有值（load 失败时为 nil，调用方须判空——IUO 曾是崩溃隐患）
    private(set) var media: WorkbenchMedia?
    private var videoTrack: AVAssetTrack?
    private var audioSourceTracks: [AVAssetTrack] = []
    private var appliedTimeline: WorkbenchEngine.BuiltTimeline?

    @Published private(set) var document = WorkbenchDocument()
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var selection: Selection?
    @Published var isExporting = false
    @Published var status: String?
    @Published var isFullscreen = false
    /// 上次播放已到结尾（再次播放从头开始）
    private(set) var playbackEnded = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var pixelsPerSecond: Double = 60
    /// 媒体素材（缩略图/波形）生成进度计数，驱动时间轴刷新
    @Published private(set) var mediaStamp = 0

    // 标注编辑（画布与工具状态沿用 VideoAnnotationCanvas）
    @Published var editingAnnotationID: UUID?
    @Published var editingFocusID: UUID?
    let annotationCanvas = VideoAnnotationCanvas(frame: .zero)
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

    private var undoStack: [WorkbenchDocument] = []
    private var redoStack: [WorkbenchDocument] = []
    private var timeObserver: Any?
    private var rebuildTask: Task<Void, Never>?
    private var rebuildToken = 0

    var videoAspect: CGFloat { media?.videoAspect ?? 16 / 9 }
    var videoSize: CGSize { media?.videoSize ?? CGSize(width: 1920, height: 1080) }
    /// 纯音频模式（m4a 录音编辑）：无画面轨
    private(set) var isAudioOnly = false

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
                if self.isPlaying, self.duration > 0, t >= self.duration - 0.05 {
                    self.player.pause()
                    self.isPlaying = false
                    self.playbackEnded = true
                }
            }
        }
    }

    // MARK: - 加载

    func load() async {
        let asset = AVURLAsset(url: sourceURL)
        guard let d = try? await asset.load(.duration), d.isNumeric else {
            status = L("无法读取视频时长")
            return
        }
        duration = CMTimeGetSeconds(d)

        var size = CGSize(width: 1920, height: 1080)
        var aspect: CGFloat = 16 / 9
        isAudioOnly = true
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            videoTrack = track
            isAudioOnly = false
            let natural = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let oriented = natural.applying(transform)
            if oriented.width != 0, oriented.height != 0 {
                aspect = abs(oriented.width / oriented.height)
                size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
            }
        }

        var tracks: [WorkbenchAudioTrack] = []
        var sourceTracks: [AVAssetTrack] = []
        let loaded = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        for (index, track) in loaded.enumerated() {
            let metadata = (try? await track.load(.metadata)) ?? []
            let identifier = metadata.first(where: { $0.identifier == .commonIdentifierTitle })?.stringValue
            let title: String
            switch identifier {
            case "sakuracap.system": title = L("系统声音")
            case "sakuracap.microphone": title = L("麦克风")
            default:
                title = loaded.count == 2 ? (index == 0 ? L("系统声音") : L("麦克风"))
                    : String(format: L("音轨 %d"), index + 1)
            }
            tracks.append(WorkbenchAudioTrack(id: track.trackID, title: title))
            sourceTracks.append(track)
        }
        audioSourceTracks = sourceTracks

        let media = WorkbenchMedia(asset: asset, duration: duration, videoSize: size,
                                   videoAspect: aspect, audioTracks: tracks)
        media.onChange = { [weak self] in self?.mediaStamp += 1 }
        self.media = media

        document = WorkbenchDocument(
            clips: [WorkbenchClip(sourceIn: 0, sourceOut: duration)],
            lanes: tracks.map { _ in WorkbenchLane() })
        selection = document.clips.first.map { .clip($0.id) }

        // 首次布局把整条时间轴装进可视宽度
        if pixelsPerSecond <= 0 { pixelsPerSecond = 60 }

        await withTaskGroup(of: Void.self) { group in
            if !isAudioOnly {
                group.addTask { await media.generateThumbnails() }
            }
            group.addTask { await media.generateWaveforms() }
            await group.waitForAll()
        }
        rebuildTimeline()
    }

    // MARK: - 撤销 / 重做

    private func pushUndo() {
        undoStack.append(document)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        syncUndoFlags()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        finishAnnotationSelection(commit: false)
        editingFocusID = nil
        validateSelection()
        syncUndoFlags()
        rebuildTimeline()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        finishAnnotationSelection(commit: false)
        editingFocusID = nil
        validateSelection()
        syncUndoFlags()
        rebuildTimeline()
    }

    private func syncUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func validateSelection() {
        guard let selection else { return }
        switch selection {
        case .clip(let id):
            if !document.clips.contains(where: { $0.id == id }) { self.selection = document.clips.first.map { .clip($0.id) } }
        case .focus(let id):
            if !document.focuses.contains(where: { $0.id == id }) { self.selection = nil }
        case .annotation(let id):
            if !document.annotations.contains(where: { $0.id == id }) { self.selection = nil }
        case .audioGain(let id):
            if !document.audioGains.contains(where: { $0.id == id }) { self.selection = nil }
        case .lane(let index):
            if index >= document.lanes.count { self.selection = nil }
        }
    }

    // MARK: - 时间线重建（结构性变更）

    func rebuildTimeline() {
        rebuildTask?.cancel()
        rebuildToken += 1
        let token = rebuildToken
        let doc = document
        let keepTime = currentTime
        let wasPlaying = isPlaying
        guard let media, let videoTrack else { return }
        let asset = media.asset
        let audio = audioSourceTracks
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            do {
                let built = try await WorkbenchEngine.build(asset: asset, document: doc,
                                                            videoSource: videoTrack, audioSources: audio)
                guard !Task.isCancelled, token == self.rebuildToken else { return }
                self.appliedTimeline = built
                let item = AVPlayerItem(asset: built.composition)
                if let comp = WorkbenchEngine.videoComposition(document: doc, base: built.composition,
                                                               renderSize: self.videoSize,
                                                               excluding: self.editingAnnotationID) {
                    item.videoComposition = comp
                }
                if let mix = WorkbenchEngine.audioMix(document: doc, audioTrackIDs: built.audioTrackIDs) {
                    item.audioMix = mix
                }
                if self.isPlaying { self.player.pause() }
                self.player.replaceCurrentItem(with: item)
                self.seek(to: min(keepTime, built.duration), updateTimeline: false)
                if wasPlaying { self.player.play() }
            } catch {
                self.status = error.localizedDescription
            }
        }
    }

    /// 参数性变更：不重建 composition，只刷新特效与混音
    func refreshOverlays() {
        guard let built = appliedTimeline, let item = player.currentItem else { return }
        if editingFocusID == nil,
           let comp = WorkbenchEngine.videoComposition(document: document, base: built.composition,
                                                       renderSize: videoSize, excluding: editingAnnotationID) {
            item.videoComposition = comp
        } else {
            item.videoComposition = nil
        }
        item.audioMix = WorkbenchEngine.audioMix(document: document, audioTrackIDs: built.audioTrackIDs)
    }

    // MARK: - 片段操作

    var canSplit: Bool {
        guard let (clip, _, start) = document.clip(atTimeline: currentTime) else { return false }
        let local = currentTime - start
        return local > 0.05 && local < clip.duration - 0.05
    }

    func splitAtPlayhead() {
        guard let (clip, index, start) = document.clip(atTimeline: currentTime) else { return }
        let local = currentTime - start
        guard local > 0.05, local < clip.duration - 0.05 else { return }
        pushUndo()
        let mid = clip.sourceIn + local
        var left = clip
        left.sourceOut = mid
        left.fadeOut = 0
        var right = WorkbenchClip(sourceIn: mid, sourceOut: clip.sourceOut)
        right.fadeIn = 0
        document.clips[index] = left
        document.clips.insert(right, at: index + 1)
        selection = .clip(left.id)
        rebuildTimeline()
    }

    func deleteClip(_ id: UUID) {
        guard document.clips.count > 1 else {
            status = L("至少保留一个片段")
            return
        }
        guard let index = document.clips.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        let clip = document.clips.remove(at: index)
        document.removeEffects(inside: clip.sourceIn, sourceOut: clip.sourceOut)
        if selection == .clip(id) { selection = document.clips.first.map { .clip($0.id) } }
        rebuildTimeline()
    }

    /// 裁剪开始：压入撤销快照（拖动过程不再压）
    func beginTrim() { pushUndo() }

    /// 各类拖拽（裁剪/特效）统一在起始时压撤销快照
    func beginUndoableDrag() { pushUndo() }

    /// 裁剪拖动中：只改文档刷新时间轴，播放时间线等拖完再重建
    func updateClipRange(id: UUID, sourceIn: Double, sourceOut: Double) {
        guard let index = document.clips.firstIndex(where: { $0.id == id }),
              let mediaDuration = media?.duration, mediaDuration > 0 else { return }
        var inValue = max(0, min(sourceIn, mediaDuration))
        var outValue = max(0, min(sourceOut, mediaDuration))
        if outValue - inValue < 0.05 {
            if inValue == document.clips[index].sourceIn {
                outValue = inValue + 0.05
            } else {
                inValue = outValue - 0.05
            }
        }
        document.clips[index].sourceIn = inValue
        document.clips[index].sourceOut = outValue
    }

    /// 裁剪结束：重建时间线
    func endTrim() { rebuildTimeline() }

    /// 拖动排序：把片段移到目标下标（目标下标按「移除后」的数组计）
    func moveClip(id: UUID, toIndex target: Int) {
        guard let index = document.clips.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(target, document.clips.count - 1))
        guard clamped != index else { return }
        pushUndo()
        let clip = document.clips.remove(at: index)
        document.clips.insert(clip, at: clamped)
        rebuildTimeline()
    }

    /// 片段整体音量（连续调节不压撤销；创建/分割时已压过）
    func setClipVolume(_ value: Double, forClip id: UUID) {
        guard let index = document.clips.firstIndex(where: { $0.id == id }) else { return }
        document.clips[index].volume = max(0, min(2, value))
        refreshOverlays()
    }

    func toggleClipMute(_ id: UUID) {
        guard let index = document.clips.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        document.clips[index].muted.toggle()
        refreshOverlays()
    }

    func setClipFade(_ kind: FadeKind, _ value: Double, forClip id: UUID) {
        guard let index = document.clips.firstIndex(where: { $0.id == id }) else { return }
        let maxFade = document.clips[index].duration / 2
        switch kind {
        case .in: document.clips[index].fadeIn = max(0, min(maxFade, value))
        case .out: document.clips[index].fadeOut = max(0, min(maxFade, value))
        }
        refreshOverlays()
    }

    enum FadeKind { case `in`, out }

    // MARK: - 音轨操作

    func setLaneVolume(_ volume: Double, lane index: Int) {
        guard document.lanes.indices.contains(index) else { return }
        document.lanes[index].volume = max(0, min(1, volume))
        refreshOverlays()
    }

    func toggleLaneMute(_ index: Int) {
        guard document.lanes.indices.contains(index) else { return }
        pushUndo()
        document.lanes[index].muted.toggle()
        refreshOverlays()
    }

    // MARK: - 聚焦特效（时间轴上拖拽创建，两端夹点 = sourceIn/Out）

    func createFocusRange(timelineStart: Double, timelineEnd: Double) {
        guard let sIn = document.sourceTime(atTimeline: timelineStart),
              let sOut = document.sourceTime(atTimeline: timelineEnd) else { return }
        pushUndo()
        let effect = WorkbenchFocus(id: UUID(), sourceIn: sIn,
                                    sourceOut: max(sIn + 0.2, sOut))
        document.focuses.append(effect)
        beginFocusEdit(effect.id)
    }

    func updateFocus(_ focus: WorkbenchFocus) {
        guard let index = document.focuses.firstIndex(where: { $0.id == focus.id }) else { return }
        document.focuses[index] = focus
        if editingFocusID == nil { refreshOverlays() }
    }

    func beginFocusEdit(_ id: UUID) {
        if editingAnnotationID != nil { finishAnnotationSelection(commit: true) }
        beginScrub()
        editingFocusID = id
        selection = .focus(id)
        refreshOverlays()
    }

    /// 放大倍数（滑杆连续调节，不压撤销；创建段时已压过一次）
    func setFocusZoom(_ value: Double, id: UUID) {
        guard let index = document.focuses.firstIndex(where: { $0.id == id }) else { return }
        document.focuses[index].zoom = max(1, min(6, value))
        refreshOverlays()
    }

    /// 预览画面上自由框选的矩形（归一化，左上原点），拖动中实时生效
    func updateFocusRect(_ rect: CGRect) {
        guard let editingFocusID,
              let index = document.focuses.firstIndex(where: { $0.id == editingFocusID }) else { return }
        var r = rect
        r.size.width = max(WorkbenchFocus.minSide, min(1, r.size.width))
        r.size.height = max(WorkbenchFocus.minSide, min(1, r.size.height))
        r.origin.x = max(0, min(1 - r.size.width, r.origin.x))
        r.origin.y = max(0, min(1 - r.size.height, r.origin.y))
        document.focuses[index].rect = r
    }

    func finishFocusEdit() {
        editingFocusID = nil
        refreshOverlays()
    }

    func removeFocus(_ id: UUID) {
        guard document.focuses.contains(where: { $0.id == id }) else { return }
        pushUndo()
        document.focuses.removeAll { $0.id == id }
        if editingFocusID == id { editingFocusID = nil }
        if selection == .focus(id) { selection = nil }
        refreshOverlays()
    }

    // MARK: - 音量段（音频轨上拖拽创建：就地静音 / 降音量）

    func createGainRange(laneIndex: Int, timelineStart: Double, timelineEnd: Double) {
        guard document.lanes.indices.contains(laneIndex),
              let sIn = document.sourceTime(atTimeline: timelineStart),
              let sOut = document.sourceTime(atTimeline: timelineEnd) else { return }
        pushUndo()
        let gain = WorkbenchAudioGain(id: UUID(), laneIndex: laneIndex,
                                      sourceIn: sIn, sourceOut: max(sIn + 0.2, sOut),
                                      volume: 0)
        document.audioGains.append(gain)
        selection = .audioGain(gain.id)
        refreshOverlays()
    }

    func updateGain(_ gain: WorkbenchAudioGain) {
        guard let index = document.audioGains.firstIndex(where: { $0.id == gain.id }) else { return }
        document.audioGains[index] = gain
        refreshOverlays()
    }

    /// 音量滑杆连续拖动，不压撤销（创建时已压过一次）
    func setGainVolume(_ volume: Double, id: UUID) {
        guard let index = document.audioGains.firstIndex(where: { $0.id == id }) else { return }
        document.audioGains[index].volume = max(0, min(1, volume))
        refreshOverlays()
    }

    /// 静音 ⇄ 恢复原音量（50%）
    func toggleGainMute(_ id: UUID) {
        guard let index = document.audioGains.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        document.audioGains[index].volume = document.audioGains[index].volume == 0 ? 0.5 : 0
        refreshOverlays()
    }

    func removeGain(_ id: UUID) {
        guard document.audioGains.contains(where: { $0.id == id }) else { return }
        pushUndo()
        document.audioGains.removeAll { $0.id == id }
        if selection == .audioGain(id) { selection = nil }
        refreshOverlays()
    }

    // MARK: - 标注特效（时间轴上拖拽创建）

    func createAnnotationRange(timelineStart: Double, timelineEnd: Double) {
        guard let sIn = document.sourceTime(atTimeline: timelineStart),
              let sOut = document.sourceTime(atTimeline: timelineEnd) else { return }
        pushUndo()
        let segment = WorkbenchAnnotation(id: UUID(), sourceIn: sIn,
                                          sourceOut: max(sIn + 0.2, sOut))
        document.annotations.append(segment)
        beginAnnotationSelection(segment.id)
    }

    func beginAnnotationSelection(_ id: UUID) {
        if editingAnnotationID != nil { finishAnnotationSelection(commit: true) }
        if editingFocusID != nil { finishFocusEdit() }
        beginScrub()
        editingAnnotationID = id
        selection = .annotation(id)
        if let segment = document.annotations.first(where: { $0.id == id }) {
            annotationCanvas.loadMarks(segment.marks)
            annotationCanvas.previewFrame = nil
            annotationCanvas.tool = annotationTool
            annotationCanvas.mosaicStyle = annotationMosaicStyle
            annotationCanvas.color = annotationColor
            annotationCanvas.lineWidth = annotationLineWidth
            annotationCanvas.onChange = { [weak self] in self?.objectWillChange.send() }
            seek(to: document.timelineTime(forSource: (segment.sourceIn + segment.sourceOut) / 2),
                 updateTimeline: true)
        }
        refreshOverlays()
        Task { await loadAnnotationFrame(for: id, at: currentTime) }
    }

    private func loadAnnotationFrame(for id: UUID, at timelineSeconds: Double) async {
        guard let media,
              let segment = document.annotations.first(where: { $0.id == id }) else { return }
        let generator = AVAssetImageGenerator(asset: media.asset)
        generator.appliesPreferredTrackTransform = true
        if let comp = WorkbenchEngine.videoComposition(document: document, base: media.asset,
                                                       renderSize: videoSize, excluding: id) {
            generator.videoComposition = comp
        }
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // 标注锚定源时间：取段中点的源帧
        let sourceSeconds = (segment.sourceIn + segment.sourceOut) / 2
        let frame = try? await generator.image(at: CMTime(seconds: sourceSeconds, preferredTimescale: 600)).image
        guard editingAnnotationID == id else { return }
        annotationCanvas.previewFrame = frame
    }

    func finishAnnotationSelection(commit: Bool = true) {
        guard editingAnnotationID != nil else { return }
        if commit {
            annotationCanvas.finishEditing()
            if let id = editingAnnotationID,
               let index = document.annotations.firstIndex(where: { $0.id == id }) {
                document.annotations[index].marks = annotationCanvas.marks
            }
        }
        editingAnnotationID = nil
        annotationCanvas.previewFrame = nil
        refreshOverlays()
    }

    func updateAnnotationRange(_ annotation: WorkbenchAnnotation) {
        guard let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        document.annotations[index] = annotation
        refreshOverlays()
    }

    func removeAnnotation(_ id: UUID) {
        guard document.annotations.contains(where: { $0.id == id }) else { return }
        pushUndo()
        finishAnnotationSelection(commit: false)
        document.annotations.removeAll { $0.id == id }
        if selection == .annotation(id) { selection = nil }
        refreshOverlays()
    }

    // MARK: - 播放

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if editingAnnotationID != nil { finishAnnotationSelection(commit: true) }
            if editingFocusID != nil { finishFocusEdit() }
            if playbackEnded || duration <= 0 || currentTime >= duration - 0.15 {
                seek(to: 0, updateTimeline: true)
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double, updateTimeline: Bool = true) {
        let t = max(0, min(duration, seconds))
        if updateTimeline, let id = editingAnnotationID,
           let segment = document.annotations.first(where: { $0.id == id }) {
            let s = document.timelineTime(forSource: segment.sourceIn)
            let e = document.timelineTime(forSource: segment.sourceOut)
            if t < s - 0.01 || t > e + 0.01 { finishAnnotationSelection(commit: true) }
        }
        currentTime = t
        playbackEnded = false
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stepFrames(_ count: Int) {
        if isPlaying { togglePlay() }
        seek(to: currentTime + Double(count) / 30.0)
    }

    func beginScrub() {
        if isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    // MARK: - 导出

    var hasEdits: Bool {
        if document.clips.count > 1 { return true }
        if let first = document.clips.first, duration > 0,
           abs(first.sourceIn) > 0.01 || abs(first.sourceOut - duration) > 0.01 { return true }
        if document.clips.contains(where: { $0.muted || $0.volume != 1 || $0.fadeIn > 0 || $0.fadeOut > 0 }) { return true }
        if document.lanes.contains(where: { $0.muted || $0.volume != 1 }) { return true }
        if !document.focuses.isEmpty { return true }
        if document.annotations.contains(where: { !$0.marks.isEmpty }) { return true }
        if !document.audioGains.isEmpty { return true }
        return false
    }

    func exportTapped() {
        guard duration > 0.05 else { status = L("裁剪区间太短"); return }
        if editingAnnotationID != nil { finishAnnotationSelection(commit: true) }
        let outURL = Self.availableURL(for: Self.outputURL(for: sourceURL))
        let alert = NSAlert()
        alert.messageText = L("导出剪辑后的视频")
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

    func export(deleteOriginal: Bool, to outURL: URL) async {
        guard duration > 0.05 else { status = L("裁剪区间太短"); return }
        guard let media else { status = L("无法读取视频时长"); return }
        isExporting = true
        status = nil
        player.pause()
        isPlaying = false
        defer { isExporting = false }

        do {
            let built = try await WorkbenchEngine.build(asset: media.asset, document: document,
                                                        videoSource: videoTrack, audioSources: audioSourceTracks)
            let preset = isAudioOnly
                ? (hasEdits ? AVAssetExportPresetAppleM4A : AVAssetExportPresetPassthrough)
                : (hasEdits ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough)
            guard let exporter = AVAssetExportSession(asset: built.composition, presetName: preset) else {
                status = L("无法创建导出任务")
                return
            }
            if !isAudioOnly {
                exporter.videoComposition = WorkbenchEngine.videoComposition(document: document,
                                                                             base: built.composition,
                                                                             renderSize: videoSize)
            }
            exporter.audioMix = WorkbenchEngine.audioMix(document: document, audioTrackIDs: built.audioTrackIDs)
            exporter.shouldOptimizeForNetworkUse = true
            if #available(macOS 15.0, *) {
                try await exporter.export(to: outURL, as: isAudioOnly ? .m4a : .mp4)
            } else {
                exporter.outputURL = outURL
                exporter.outputFileType = isAudioOnly ? .m4a : .mp4
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    exporter.exportAsynchronously {
                        if let error = exporter.error { cont.resume(throwing: error) }
                        else { cont.resume() }
                    }
                }
            }
            if deleteOriginal {
                do {
                    try FileManager.default.removeItem(at: sourceURL)
                    status = String(format: L("已导出并删除原文件：%@"), outURL.lastPathComponent)
                } catch {
                    // 原文件没删掉要如实说，不能沿用「已删除」的成功文案
                    Log.app.error("导出后删除原文件失败: \(self.sourceURL.lastPathComponent, privacy: .public) \(error.localizedDescription, privacy: .public)")
                    status = String(format: L("已导出 %@（原文件删除失败，请手动删除）"), outURL.lastPathComponent)
                }
            } else {
                status = String(format: L("已导出 %@"), outURL.lastPathComponent)
            }
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
            isProgrammaticClose = true
            requestClose?()
        } catch {
            status = String(format: L("导出失败：%@"), error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = L("导出失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L("好"))
            runModalAlert(alert)
        }
    }

    func exportGIFTapped() {
        guard duration > 0.05 else { status = L("裁剪区间太短"); return }
        if editingAnnotationID != nil { finishAnnotationSelection(commit: true) }
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
        guard duration > 0.05 else { status = L("裁剪区间太短"); return }
        guard let media else { status = L("无法读取视频时长"); return }
        isExporting = true
        status = nil
        player.pause()
        isPlaying = false
        defer { isExporting = false }

        do {
            let built = try await WorkbenchEngine.build(asset: media.asset, document: document,
                                                        videoSource: videoTrack, audioSources: audioSourceTracks)
            try await GIFExporter.export(asset: built.composition,
                                         timeRange: CMTimeRange(start: .zero,
                                                                duration: CMTime(seconds: built.duration, preferredTimescale: 600)),
                                         size: size,
                                         videoComposition: WorkbenchEngine.videoComposition(document: document,
                                                                                             base: built.composition,
                                                                                             renderSize: videoSize),
                                         to: outURL)
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

    /// 截帧：把播放头所在帧（含特效与标注）存为 PNG，并打开标注编辑器
    func captureFrameTapped() {
        guard !isExporting, let dir = OutputDirectoryPicker.ensureDirectory(current: AppSettings.shared.outputDirectory) else { return }
        if editingAnnotationID != nil { finishAnnotationSelection(commit: true) }
        player.pause()
        isPlaying = false
        let compositionAsset = appliedTimeline?.composition ?? AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: compositionAsset)
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = WorkbenchEngine.videoComposition(document: document,
                                                                       base: compositionAsset,
                                                                       renderSize: videoSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        Task { @MainActor in
            do {
                let cg = try await generator.image(at: time).image
                let url = dir.appendingPathComponent(FileName.make(ext: "png"))
                guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
                try data.write(to: url, options: .atomic)
                status = String(format: L("已截帧 %@"), url.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                AnnotationEditorController.shared.open(image: cg, suggestedName: url.lastPathComponent, source: .existingFile)
            } catch {
                status = String(format: L("截帧失败：%@"), error.localizedDescription)
            }
        }
    }

    /// 删除原始录像文件
    func deleteTapped() {
        let alert = NSAlert()
        alert.messageText = isAudioOnly ? L("删除录音文件") : L("删除录像文件")
        alert.informativeText = String(format: L("确定要删除「%@」吗？此操作不可撤销。"), sourceURL.lastPathComponent)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("取消"))
        alert.addButton(withTitle: L("删除"))
        guard runModalAlert(alert) == .alertSecondButtonReturn else { return }

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

    /// 关窗确认；返回 true 允许关闭
    func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.messageText = isAudioOnly ? L("确定放弃编辑吗？") : L("确定放弃剪辑吗？")
        var deleteCheckbox: NSButton?
        if origin == .recording {
            let box = NSButton(checkboxWithTitle: isAudioOnly ? L("删除录音原文件") : L("删除录屏原文件"),
                               target: nil, action: nil)
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
            player.replaceCurrentItem(with: nil)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        return true
    }

    // MARK: - 文件名

    private static func outputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = (url.pathExtension.lowercased() == "m4a" || url.pathExtension.lowercased() == "mp3") ? "m4a" : "mp4"
        return dir.appendingPathComponent("\(base) - \(L("剪辑")).\(ext)")
    }

    private static func gifOutputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(base) - \(L("剪辑")).gif")
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
}
