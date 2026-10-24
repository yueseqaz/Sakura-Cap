import AppKit
import AVKit
import SwiftUI

/// 录屏后期工作台：顶部工具栏 / 中央预览 / 右侧属性面板 / 底部多轨时间轴。
struct WorkbenchView: View {
    @ObservedObject var model: WorkbenchViewModel

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            HStack(spacing: 8) {
                preview
                if !model.isFullscreen {
                    propertiesPanel
                        .frame(width: 252)
                }
            }
            .frame(maxHeight: .infinity)
            if !model.isFullscreen {
                WorkbenchTimeline(model: model)
                    .frame(height: timelineHeight)
            }
        }
        .padding(12)
        .background(SettingsAppearance.color(SettingsAppearance.canvas))
        .tint(SettingsAppearance.color(SettingsAppearance.accent))
        .frame(minWidth: 980, minHeight: 660)
        .task { await model.load() }
        .onDisappear { model.player.pause() }
    }

    private var timelineHeight: CGFloat {
        let rows = 24 + 64 + model.document.lanes.count * 44 + 26 * 2
        return CGFloat(rows) + 46
    }

    // MARK: 顶部工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canUndo)
            .help(L("撤销 ⌘Z"))

            Button { model.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canRedo)
            .help(L("重做 ⇧⌘Z"))

            Button { model.splitAtPlayhead() } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canSplit)
            .help(L("在播放头处分割 S"))

            Divider().frame(height: 20)

            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .buttonStyle(.bordered)
            .help(L("播放 / 暂停 空格"))

            Text(CompletionNotifier.format(model.currentTime)).monospacedDigit()
            Text("/").foregroundStyle(.secondary)
            Text(CompletionNotifier.format(model.duration)).monospacedDigit().foregroundStyle(.secondary)

            Spacer()

            if model.isExporting { ProgressView().controlSize(.small) }
            Button { model.captureFrameTapped() } label: { Text(L("截帧")) }
                .buttonStyle(.bordered)
                .disabled(model.isExporting)
                .help(L("把当前帧存为 PNG 并打开标注"))
            Button { model.exportGIFTapped() } label: { Text(L("GIF")) }
                .buttonStyle(.bordered)
                .disabled(model.isExporting || model.duration <= 0)
            Button { model.deleteTapped() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(model.isExporting)
            .help(L("删除录像文件"))
            Button(L("导出")) { model.exportTapped() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting || model.duration <= 0)
        }
    }

    // MARK: 中央预览

    private var preview: some View {
        PlayerView(player: model.player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if let id = model.editingFocusID,
                   let focus = model.document.focuses.first(where: { $0.id == id }) {
                    FocusCanvas(focus: focus, aspect: model.videoAspect,
                                onPoint: { model.setFocusPoint(x: $0, y: $1) },
                                onScale: { value in
                                    var updated = focus
                                    updated.scale = value
                                    model.updateFocus(updated)
                                },
                                onDone: { model.finishFocusEdit() })
                }
            }
            .overlay {
                if model.editingAnnotationID != nil {
                    GeometryReader { geometry in
                        let width = min(geometry.size.width, geometry.size.height * max(model.videoAspect, 0.1))
                        let height = width / max(model.videoAspect, 0.1)
                        VideoAnnotationView(canvas: model.annotationCanvas)
                            .frame(width: width, height: height)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if model.editingAnnotationID != nil {
                    AnnotationFloatingToolbar(model: model)
                        .padding(.bottom, 8)
                }
            }
    }

    // MARK: 右侧属性面板

    private var propertiesPanel: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                switch model.selection {
                case .clip(let id): clipProperties(id)
                case .lane(let index): laneProperties(index)
                case .focus(let id): focusProperties(id)
                case .annotation(let id): annotationProperties(id)
                case .audioGain(let id): gainProperties(id)
                case nil: documentProperties()
                }
                if let status = model.status {
                    Text(status)
                        .font(SettingsAppearance.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(SettingsAppearance.color(SettingsAppearance.sidebar))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(SettingsAppearance.detailFont.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func documentProperties() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("视频"))
            LabeledRow(label: L("分辨率"), value: "\(Int(videoSizeText.width))×\(Int(videoSizeText.height))")
            LabeledRow(label: L("时长"), value: CompletionNotifier.format(model.duration))
            if !model.document.lanes.isEmpty {
                sectionTitle(L("音轨"))
                ForEach(model.document.lanes.indices, id: \.self) { index in
                    if index < model.media?.audioTracks.count ?? 0 {
                        laneVolumeRow(index: index, title: model.media!.audioTracks[index].title)
                    }
                }
            }
            Text(L("在轨道上拖拽创建聚焦 / 标注 / 音量段；点击片段或音轨编辑属性。"))
                .font(SettingsAppearance.detailFont).foregroundStyle(.secondary)
        }
    }

    private var videoSizeText: CGSize { model.videoSize }

    private func clipProperties(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("视频片段"))
            if let clip = model.document.clips.first(where: { $0.id == id }) {
                LabeledRow(label: L("时长"), value: CompletionNotifier.format(clip.duration))
                LabeledRow(label: L("源区间"),
                           value: "\(CompletionNotifier.format(clip.sourceIn)) – \(CompletionNotifier.format(clip.sourceOut))")
                Toggle(L("片段静音"), isOn: Binding(
                    get: { clip.muted },
                    set: { _ in model.toggleClipMute(id) }))
                    .font(SettingsAppearance.detailFont)
                fadeRow(label: L("淡入"), value: clip.fadeIn) { model.setClipFade(.in, $0, forClip: id) }
                fadeRow(label: L("淡出"), value: clip.fadeOut) { model.setClipFade(.out, $0, forClip: id) }
                Button(L("删除片段"), role: .destructive) { model.deleteClip(id) }
                    .buttonStyle(.bordered)
                    .disabled(model.document.clips.count <= 1)
            }
        }
    }

    private func fadeRow(label: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(SettingsAppearance.detailFont)
                Spacer()
                Text("\(String(format: "%.1f", value))s")
                    .font(SettingsAppearance.detailFont).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...2)
                .controlSize(.small)
        }
    }

    private func laneProperties(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("音轨"))
            if index < model.media?.audioTracks.count ?? 0 {
                laneVolumeRow(index: index, title: model.media!.audioTracks[index].title)
                Toggle(L("整轨静音"), isOn: Binding(
                    get: { model.document.lanes.indices.contains(index) && model.document.lanes[index].muted },
                    set: { _ in model.toggleLaneMute(index) }))
                    .font(SettingsAppearance.detailFont)
            }
        }
    }

    private func laneVolumeRow(index: Int, title: String) -> some View {
        HStack {
            Text(title).font(SettingsAppearance.detailFont)
            Spacer()
            Slider(value: Binding(
                get: { model.document.lanes.indices.contains(index) ? model.document.lanes[index].volume : 1 },
                set: { model.setLaneVolume($0, lane: index) }), in: 0...1)
                .frame(width: 100)
            Text("\(Int((model.document.lanes.indices.contains(index) ? model.document.lanes[index].volume : 1) * 100))%")
                .font(SettingsAppearance.detailFont).monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func focusProperties(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("画面聚焦"))
            if let focus = model.document.focuses.first(where: { $0.id == id }) {
                LabeledRow(label: L("范围"),
                           value: "\(CompletionNotifier.format(focus.sourceIn)) – \(CompletionNotifier.format(focus.sourceOut))")
                HStack {
                    Text(L("放大倍数")).font(SettingsAppearance.detailFont)
                    Spacer()
                    Text(String(format: "%.1f×", focus.scale))
                        .font(SettingsAppearance.detailFont).monospacedDigit()
                }
                Slider(value: Binding(get: { focus.scale }, set: { value in
                    var updated = focus
                    updated.scale = max(1, min(3, value))
                    model.updateFocus(updated)
                }), in: 1...3)
                if model.editingFocusID == id {
                    Button(L("完成聚焦")) { model.finishFocusEdit() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(L("编辑聚焦框")) { model.beginFocusEdit(id) }
                        .buttonStyle(.bordered)
                }
                Button(L("删除聚焦"), role: .destructive) { model.removeFocus(id) }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// 音量段属性：就地调音量 / 静音 / 删除（段的两端在时间轴上直接拖）
    private func gainProperties(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("音量段"))
            if let gain = model.document.audioGains.first(where: { $0.id == id }) {
                if let tracks = model.media?.audioTracks,
                   tracks.indices.contains(gain.laneIndex) {
                    Text(tracks[gain.laneIndex].title)
                        .font(SettingsAppearance.detailFont).foregroundStyle(.secondary)
                }
                LabeledRow(label: L("范围"),
                           value: "\(CompletionNotifier.format(gain.sourceIn)) – \(CompletionNotifier.format(gain.sourceOut))")
                HStack {
                    Text(L("音量")).font(SettingsAppearance.detailFont)
                    Spacer()
                    Text("\(Int(gain.volume * 100))%")
                        .font(SettingsAppearance.detailFont).monospacedDigit()
                }
                Slider(value: Binding(get: { gain.volume },
                                      set: { model.setGainVolume($0, id: id) }), in: 0...1)
                    .controlSize(.small)
                HStack {
                    Button(gain.volume == 0 ? L("恢复音量") : L("静音此段")) { model.toggleGainMute(id) }
                        .buttonStyle(.bordered)
                    Button(L("删除音量段"), role: .destructive) { model.removeGain(id) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func annotationProperties(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("标注段"))
            if let segment = model.document.annotations.first(where: { $0.id == id }) {
                LabeledRow(label: L("范围"),
                           value: "\(CompletionNotifier.format(segment.sourceIn)) – \(CompletionNotifier.format(segment.sourceOut))")
                if model.editingAnnotationID == id {
                    Text(L("工具栏在预览画面下方，直接在画面上绘制。"))
                        .font(SettingsAppearance.detailFont).foregroundStyle(.secondary)
                    Button(L("完成标注")) { model.finishAnnotationSelection(commit: true) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(L("编辑标注")) { model.beginAnnotationSelection(id) }
                        .buttonStyle(.bordered)
                }
                Button(L("删除标注段"), role: .destructive) { model.removeAnnotation(id) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(SettingsAppearance.detailFont).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(SettingsAppearance.detailFont).monospacedDigit()
        }
    }
}

/// AppKit 的 AVPlayerView（SwiftUI 的 VideoPlayer 在 CLT 构建下会崩）
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

// MARK: - 聚焦编辑浮层（移植自旧裁剪页，坐标语义不变）

private struct FocusCanvas: View {
    let focus: WorkbenchFocus
    let aspect: CGFloat
    let onPoint: (Double, Double) -> Void
    let onScale: (Double) -> Void
    let onDone: () -> Void

    @ObservedObject private var dragState = FocusDragStateBox()

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * max(aspect, 0.1))
            let height = width / max(aspect, 0.1)
            let imageRect = CGRect(x: (geometry.size.width - width) / 2,
                                   y: (geometry.size.height - height) / 2,
                                   width: width, height: height)
            let frameWidth = width / focus.scale
            let frameHeight = height / focus.scale
            let center = CGPoint(x: imageRect.minX + width * focus.x,
                                 y: imageRect.minY + height * focus.y)

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
                            if dragState.point == nil { dragState.point = CGPoint(x: focus.x, y: focus.y) }
                            guard let origin = dragState.point else { return }
                            let margin = 0.5 / focus.scale
                            onPoint(min(1 - margin, max(margin, origin.x + value.translation.width / width)),
                                    min(1 - margin, max(margin, origin.y + value.translation.height / height)))
                        }.onEnded { _ in dragState.point = nil })
                Circle().fill(.white)
                    .overlay { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9)).foregroundStyle(.black) }
                    .frame(width: 24, height: 24)
                    .position(x: center.x + frameWidth / 2, y: center.y + frameHeight / 2)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragState.scale == nil { dragState.scale = focus.scale }
                            guard let origin = dragState.scale else { return }
                            onScale(min(3, max(1, origin / max(0.3, 1 + Double(value.translation.width / width) * origin * 2))))
                        }.onEnded { _ in dragState.scale = nil })
                Button(L("完成聚焦"), action: onDone)
                    .buttonStyle(.borderedProminent).padding(10)
            }
        }
    }
}

/// 无 @State 环境下的拖拽临时状态盒（CLT 工具链不支持 SwiftUI 宏）
final class FocusDragStateBox: ObservableObject {
    @Published var point: CGPoint?
    @Published var scale: Double?
}

/// 标注编辑时悬浮在预览画面下方的工具栏：工具 / 颜色粗细 / 马赛克样式 / 撤回 / 完成
struct AnnotationFloatingToolbar: View {
    @ObservedObject var model: WorkbenchViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(VideoMarkTool.allCases) { tool in
                    Button { model.annotationTool = tool } label: {
                        Image(systemName: tool.symbol).frame(width: 22, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.annotationTool == tool ? SettingsAppearance.color(SettingsAppearance.accent) : nil)
                    .help(tool.label)
                }
                Divider().frame(height: 18)
                Button(L("撤回")) { model.annotationCanvas.undo() }
                    .disabled(model.annotationCanvas.undoStack.isEmpty)
                Button(L("删除选中")) { model.annotationCanvas.deleteSelected() }
                    .disabled(model.annotationCanvas.selectedIndex == nil)
                Button(L("清空")) { model.annotationCanvas.clear() }
                    .disabled(model.annotationCanvas.marks.isEmpty)
                Divider().frame(height: 18)
                Button(L("完成标注")) { model.finishAnnotationSelection(commit: true) }
                    .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 10) {
                if model.annotationTool == .mosaic {
                    Text(L("马赛克样式")).font(SettingsAppearance.detailFont)
                    Picker(L("马赛克样式"), selection: $model.annotationMosaicStyle) {
                        ForEach(MosaicStyle.allCases) { style in Text(style.label).tag(style) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                } else {
                    Text(L("颜色")).font(SettingsAppearance.detailFont)
                    ForEach([NSColor.systemRed, .systemYellow, .systemBlue, .systemGreen, .white], id: \.self) { color in
                        Button { model.annotationColor = color } label: {
                            Circle().fill(Color(nsColor: color))
                                .frame(width: 14, height: 14)
                                .padding(3)
                                .overlay(Circle().stroke(model.annotationColor == color ? Color.accentColor : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                    Text(L("粗细")).font(SettingsAppearance.detailFont)
                    Slider(value: Binding(get: { Double(model.annotationLineWidth) },
                                          set: { model.annotationLineWidth = CGFloat($0) }), in: 1...12)
                        .frame(width: 90)
                }
            }
            .font(SettingsAppearance.detailFont)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
