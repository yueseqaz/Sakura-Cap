import AVFoundation
import CoreImage

// MARK: - 剪辑模型（磁性时间轴）

/// 视频片段：源文件上的一段 [sourceIn, sourceOut]，在时间轴上按数组顺序无缝排布。
struct WorkbenchClip: Identifiable, Equatable {
    let id: UUID
    var sourceIn: Double
    var sourceOut: Double
    var fadeIn: Double = 0       // 音频淡入（秒）
    var fadeOut: Double = 0      // 音频淡出（秒）
    var muted: Bool = false      // 片段整体静音（所有音轨）
    var duration: Double { max(0, sourceOut - sourceIn) }

    init(id: UUID = UUID(), sourceIn: Double, sourceOut: Double) {
        self.id = id
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }
}

/// 音轨状态（下标与源文件音轨一一对应：系统声 / 麦克风）
struct WorkbenchLane: Equatable {
    var volume: Double = 1
    var muted: Bool = false
}

/// 画面聚焦段：锚定在【源时间】上，裁剪后跟随画面内容而非时间轴位置。
struct WorkbenchFocus: Identifiable, Equatable {
    let id: UUID
    var sourceIn: Double
    var sourceOut: Double
    var x: Double = 0.5
    var y: Double = 0.5
    var scale: Double = 2
}

/// 标注段：同上，源时间锚定；marks 归一化坐标基于视频画面尺寸。
struct WorkbenchAnnotation: Identifiable, Equatable {
    let id: UUID
    var sourceIn: Double
    var sourceOut: Double
    var marks: [VideoMark] = []
}

/// 音量段：在某条音轨的源时间段内降低音量（0 = 静音）。
/// 在时间轴音频轨上拖拽创建，两端的夹点即 sourceIn / sourceOut。
struct WorkbenchAudioGain: Identifiable, Equatable {
    let id: UUID
    var laneIndex: Int
    var sourceIn: Double
    var sourceOut: Double
    var volume: Double
}

/// 一份可撤销的剪辑文档。所有字段为值类型，撤销/重做直接快照整个结构体。
struct WorkbenchDocument: Equatable {
    var clips: [WorkbenchClip] = []
    var lanes: [WorkbenchLane] = []
    var focuses: [WorkbenchFocus] = []
    var annotations: [WorkbenchAnnotation] = []
    var audioGains: [WorkbenchAudioGain] = []

    var duration: Double { clips.reduce(0) { $0 + $1.duration } }

    // MARK: 时间轴 ↔ 源时间换算（磁性排布）

    /// 片段在时间轴上的起点
    func timelineStart(ofClip clipID: UUID) -> Double {
        var cursor = 0.0
        for clip in clips {
            if clip.id == clipID { return cursor }
            cursor += clip.duration
        }
        return cursor
    }

    /// 时间轴时间 → 源时间；越界时钳制到首/尾片段边界
    func sourceTime(atTimeline t: Double) -> Double? {
        guard let first = clips.first else { return nil }
        var cursor = 0.0
        for (index, clip) in clips.enumerated() {
            if t <= cursor + clip.duration || index == clips.count - 1 {
                return clip.sourceIn + max(0, min(clip.duration, t - cursor))
            }
            cursor += clip.duration
        }
        return first.sourceIn
    }

    /// 源时间 → 时间轴时间；落在被剪掉的源区间时钳制到最近的片段边界
    func timelineTime(forSource s: Double) -> Double {
        var cursor = 0.0
        for clip in clips {
            if s < clip.sourceIn { return cursor }
            if s <= clip.sourceOut { return cursor + (s - clip.sourceIn) }
            cursor += clip.duration
        }
        return cursor
    }

    /// 播放头所在片段（含时间轴起点与下标）
    func clip(atTimeline t: Double) -> (clip: WorkbenchClip, index: Int, start: Double)? {
        var cursor = 0.0
        for (index, clip) in clips.enumerated() {
            let d = clip.duration
            if t < cursor + d || index == clips.count - 1 {
                return (clip, index, cursor)
            }
            cursor += d
        }
        return nil
    }

    /// 把源区间内的特效清掉（删除片段时调用）
    mutating func removeEffects(inside sourceIn: Double, sourceOut: Double) {
        focuses.removeAll { $0.sourceIn >= sourceIn - 0.001 && $0.sourceOut <= sourceOut + 0.001 }
        annotations.removeAll { $0.sourceIn >= sourceIn - 0.001 && $0.sourceOut <= sourceOut + 0.001 }
        audioGains.removeAll { $0.sourceIn >= sourceIn - 0.001 && $0.sourceOut <= sourceOut + 0.001 }
    }
}

// MARK: - AVFoundation 引擎：从文档构建可播放/可导出的时间线

@MainActor
enum WorkbenchEngine {
    enum EngineError: LocalizedError {
        case noVideoTrack
        case insertFailed
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return L("视频缺少画面轨，无法编辑")
            case .insertFailed: return L("构建时间线失败")
            }
        }
    }

    struct BuiltTimeline {
        let composition: AVMutableComposition
        let audioTrackIDs: [CMPersistentTrackID]   // 与文档 lanes 一一对应
        let duration: Double
    }

    /// 按文档把片段拼成 AVMutableComposition（元数据级操作，不解码）。
    static func build(asset: AVAsset, document: WorkbenchDocument,
                      videoSource: AVAssetTrack?, audioSources: [AVAssetTrack]) async throws -> BuiltTimeline {
        guard let videoSource else { throw EngineError.noVideoTrack }
        let composition = AVMutableComposition()

        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        for clip in document.clips where clip.duration > 0 {
            let range = CMTimeRange(start: CMTime(seconds: clip.sourceIn, preferredTimescale: 600),
                                    end: CMTime(seconds: clip.sourceOut, preferredTimescale: 600))
            try videoTrack?.insertTimeRange(range, of: videoSource, at: cursor)
            cursor = CMTimeAdd(cursor, range.duration)
        }

        var audioTrackIDs: [CMPersistentTrackID] = []
        for source in audioSources {
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            var audioCursor = CMTime.zero
            for clip in document.clips where clip.duration > 0 {
                let range = CMTimeRange(start: CMTime(seconds: clip.sourceIn, preferredTimescale: 600),
                                        end: CMTime(seconds: clip.sourceOut, preferredTimescale: 600))
                try? track?.insertTimeRange(range, of: source, at: audioCursor)
                audioCursor = CMTimeAdd(audioCursor, range.duration)
            }
            if let id = track?.trackID { audioTrackIDs.append(id) }
        }

        return BuiltTimeline(composition: composition, audioTrackIDs: audioTrackIDs,
                             duration: CMTimeGetSeconds(cursor))
    }

    /// 画面特效合成器：聚焦缩放 + 马赛克 + 标注叠加（特效按源时间锚定，
    /// 合成时间经文档映射回源时间）。excluding 用于标注编辑时隐藏当前段。
    /// base 为当前合成（或源）asset，提供渲染尺寸等元信息。
    static func videoComposition(document: WorkbenchDocument, base: AVAsset, renderSize: CGSize,
                                 excluding annotationID: UUID? = nil) -> AVVideoComposition? {
        guard !document.clips.isEmpty else { return nil }
        let segments = document.clips.map { (start: timelineStartIn(document: document, clip: $0),
                                             duration: $0.duration, sourceIn: $0.sourceIn) }
        let focuses = document.focuses
        let layers = document.annotations.filter { $0.id != annotationID && !$0.marks.isEmpty }.map { segment in
            (start: segment.sourceIn, end: segment.sourceOut,
             overlay: VideoAnnotationCanvas.image(marks: segment.marks, size: renderSize).map { CIImage(cgImage: $0) },
             mosaic: segment.marks.filter { $0.tool == .mosaic })
        }
        guard !focuses.isEmpty || !layers.isEmpty else { return nil }

        let outputSize = renderSize
        return AVVideoComposition(asset: base) { request in
            let timelineSeconds = CMTimeGetSeconds(request.compositionTime)
            // 合成时间 → 源时间（特效锚定）
            var sourceSeconds = timelineSeconds
            for segment in segments where timelineSeconds >= segment.start && timelineSeconds < segment.start + segment.duration {
                sourceSeconds = segment.sourceIn + (timelineSeconds - segment.start)
                break
            }
            let image = request.sourceImage
            let bounds = image.extent
            var magnification: CGFloat = 1.0
            var point = CGPoint(x: 0.5, y: 0.5)
            if let focus = focuses.last(where: { sourceSeconds >= $0.sourceIn && sourceSeconds < $0.sourceOut }) {
                let fade = min(1, max(0, min(sourceSeconds - focus.sourceIn, focus.sourceOut - sourceSeconds) / 0.3))
                let smooth = fade * fade * (3 - 2 * fade)
                magnification = 1 + (focus.scale - 1) * smooth
                point = CGPoint(x: focus.x, y: 1 - focus.y)
            }
            let margin = 0.5 / magnification
            let focusX = bounds.minX + bounds.width * min(1 - margin, max(margin, point.x))
            let focusY = bounds.minY + bounds.height * min(1 - margin, max(margin, point.y))
            let transform = CGAffineTransform(translationX: bounds.midX - focusX * magnification,
                                              y: bounds.midY - focusY * magnification)
                .scaledBy(x: magnification, y: magnification)
            var output = image.transformed(by: transform).cropped(to: bounds)
            for layer in layers where sourceSeconds >= layer.start && sourceSeconds < layer.end {
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

    private static func timelineStartIn(document: WorkbenchDocument, clip: WorkbenchClip) -> Double {
        document.timelineStart(ofClip: clip.id)
    }

    /// 音频混音：整轨音量/静音 + 片段静音 + 淡入淡出 + 音量段。
    /// 在所有「音量拐点」（片段边界、淡入淡出端点、音量段首尾、文档首尾）上采样求值，
    /// 交给 AVAudioMix 在拐点间线性插值。
    static func audioMix(document: WorkbenchDocument, audioTrackIDs: [CMPersistentTrackID]) -> AVAudioMix? {
        guard audioTrackIDs.count == document.lanes.count, !audioTrackIDs.isEmpty else { return nil }
        let hasNoEdits = document.lanes.allSatisfy { $0.volume == 1 && !$0.muted }
            && document.clips.allSatisfy { !$0.muted && $0.fadeIn == 0 && $0.fadeOut == 0 }
            && document.audioGains.isEmpty
        if hasNoEdits { return nil }

        // 音量段投影到时间轴（源时间锚定）
        func gainRanges(_ laneIndex: Int) -> [(start: Double, end: Double, volume: Double)] {
            document.audioGains
                .filter { $0.laneIndex == laneIndex }
                .sorted { $0.sourceIn < $1.sourceIn }
                .map { (document.timelineTime(forSource: $0.sourceIn),
                        document.timelineTime(forSource: $0.sourceOut),
                        $0.volume) }
        }

        func effectiveVolume(lane: WorkbenchLane, laneIndex: Int, at t: Double) -> Float {
            var v = lane.muted ? 0 : lane.volume
            guard let hit = document.clip(atTimeline: t) else { return Float(v) }
            let (clip, _, clipStart) = hit
            let local = t - clipStart
            if clip.muted { return 0 }
            if clip.fadeIn > 0, local < clip.fadeIn { v *= local / clip.fadeIn }
            if clip.fadeOut > 0, local > clip.duration - clip.fadeOut {
                v *= max(0, (clip.duration - local) / clip.fadeOut)
            }
            if let gain = gainRanges(laneIndex).last(where: { t >= $0.start && t < $0.end }) {
                v *= gain.volume
            }
            return Float(max(0, min(1, v)))
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = audioTrackIDs.enumerated().map { index, trackID in
            let lane = document.lanes[index]
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = trackID
            var boundaries: Set<Double> = [0, document.duration]
            for clip in document.clips {
                let start = document.timelineStart(ofClip: clip.id)
                boundaries.insert(start)
                boundaries.insert(start + clip.duration)
                if clip.fadeIn > 0 { boundaries.insert(start + clip.fadeIn) }
                if clip.fadeOut > 0 { boundaries.insert(start + clip.duration - clip.fadeOut) }
            }
            for gain in gainRanges(index) {
                boundaries.insert(gain.start)
                boundaries.insert(gain.end)
            }
            for t in boundaries.sorted() {
                parameters.setVolume(effectiveVolume(lane: lane, laneIndex: index, at: t),
                                     at: CMTime(seconds: t, preferredTimescale: 600))
            }
            return parameters
        }
        return mix
    }
}
