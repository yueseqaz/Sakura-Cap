import AppKit
import AVFoundation
import SwiftUI

// MARK: - 窗口与呈现

/// 音频编辑器入口：窗口创建/去重/快捷键/关窗确认统一在 MediaEditorWindowPresenter，
/// 此处保留类名与 show(url:origin:) 接口，调用方无需改动。
@MainActor
final class AudioEditorPresenter {
    static let shared = AudioEditorPresenter()

    func show(url: URL, origin: TrimOrigin) {
        MediaEditorWindowPresenter.shared.show(url: url, origin: origin, kind: .audioEditor)
    }
}

// MARK: - 页面

struct AudioEditorView: View {
    @ObservedObject var model: WorkbenchViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            AudioWaveform(model: model)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 110, maxHeight: 160)
            Divider()
            AudioTimeline(model: model)
                .frame(maxWidth: .infinity, minHeight: timelineMinHeight)
            Divider()
            inspector
        }
        .background(SettingsAppearance.color(SettingsAppearance.canvas))
        .tint(SettingsAppearance.color(SettingsAppearance.accent))
        .frame(minWidth: 540, minHeight: 400)
        .task { await model.load() }
        .onDisappear { model.player.pause() }
    }

    private var timelineMinHeight: CGFloat {
        20 + 40 + CGFloat(model.document.lanes.count) * 30 + 12
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.bordered).disabled(!model.canUndo).help(L("撤销 ⌘Z"))
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.bordered).disabled(!model.canRedo).help(L("重做 ⇧⌘Z"))
            Button { model.splitAtPlayhead() } label: { Image(systemName: "rectangle.split.2x1") }
                .buttonStyle(.bordered).disabled(!model.canSplit).help(L("在播放头处分割 S"))
            Divider().frame(height: 20)
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .buttonStyle(.bordered).help(L("播放 / 暂停 空格"))
            Text(CompletionNotifier.format(model.currentTime)).monospacedDigit()
            Text("/").foregroundStyle(.secondary)
            Text(CompletionNotifier.format(model.duration)).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            if model.isExporting { ProgressView().controlSize(.small) }
            if let status = model.status {
                Text(status).font(SettingsAppearance.detailFont).foregroundStyle(.secondary).lineLimit(1)
            }
            Button(L("导出")) { model.exportTapped() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting || model.duration <= 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// 底部操作区：按选中对象显示（片段 → 淡入淡出/静音/删除；音量段 → 音量/静音/删除）
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.selection {
            case .clip(let id):
                if let clip = model.document.clips.first(where: { $0.id == id }) {
                    // 控件一行放不下时自动换成两行，避免「片段静音/删除片段」被裁出视野
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            clipHeader
                            fadeSlider(label: L("声音淡入"), value: clip.fadeIn) { model.setClipFade(.in, $0, forClip: id) }
                            fadeSlider(label: L("声音淡出"), value: clip.fadeOut) { model.setClipFade(.out, $0, forClip: id) }
                            clipVolumeControls(clip: clip, id: id)
                            clipMuteToggle(clip: clip, id: id)
                            Spacer(minLength: 12)
                            clipDeleteButton(id: id)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 14) {
                                clipHeader
                                fadeSlider(label: L("声音淡入"), value: clip.fadeIn) { model.setClipFade(.in, $0, forClip: id) }
                                fadeSlider(label: L("声音淡出"), value: clip.fadeOut) { model.setClipFade(.out, $0, forClip: id) }
                            }
                            HStack(spacing: 14) {
                                clipVolumeControls(clip: clip, id: id)
                                clipMuteToggle(clip: clip, id: id)
                                Spacer(minLength: 12)
                                clipDeleteButton(id: id)
                            }
                        }
                    }
                }
            case .audioGain(let id):
                if let gain = model.document.audioGains.first(where: { $0.id == id }) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            gainHeader
                            gainVolumeControls(gain: gain, id: id)
                            Button(gain.volume == 0 ? L("恢复音量") : L("静音此段")) { model.toggleGainMute(id) }
                                .buttonStyle(.bordered)
                            Spacer(minLength: 12)
                            Button(L("删除音量段"), role: .destructive) { model.removeGain(id) }
                                .buttonStyle(.bordered)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 14) {
                                gainHeader
                                gainVolumeControls(gain: gain, id: id)
                            }
                            HStack(spacing: 14) {
                                Button(gain.volume == 0 ? L("恢复音量") : L("静音此段")) { model.toggleGainMute(id) }
                                    .buttonStyle(.bordered)
                                Spacer(minLength: 12)
                                Button(L("删除音量段"), role: .destructive) { model.removeGain(id) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            default:
                HStack(spacing: 12) {
                    Text(L("在时间轴上：拖边缘裁剪片段，拖动排序；音量轨上拖拽创建音量段。"))
                        .font(SettingsAppearance.detailFont).foregroundStyle(.secondary)
                    Spacer()
                    if !model.document.lanes.isEmpty {
                        Menu(L("在播放头添加音量段")) {
                            ForEach(Array((model.media?.audioTracks ?? []).enumerated()), id: \.offset) { index, track in
                                Button(track.title) {
                                    model.createGainRange(laneIndex: index,
                                                          timelineStart: model.currentTime,
                                                          timelineEnd: min(model.duration, model.currentTime + 3))
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 54, alignment: .center)
    }

    private var clipHeader: some View {
        Text(L("音频片段")).font(SettingsAppearance.detailFont.weight(.semibold)).foregroundStyle(.secondary)
    }

    private var gainHeader: some View {
        Text(L("音量段")).font(SettingsAppearance.detailFont.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func clipVolumeControls(clip: WorkbenchClip, id: UUID) -> some View {
        HStack(spacing: 6) {
            Text(L("音量")).font(SettingsAppearance.detailFont)
            Slider(value: Binding(get: { clip.volume },
                                  set: { model.setClipVolume($0, forClip: id) }), in: 0...2)
                .controlSize(.small).frame(width: 90)
            Text("\(Int(clip.volume * 100))%").monospacedDigit()
                .font(SettingsAppearance.detailFont).frame(width: 40)
        }
    }

    private func clipMuteToggle(clip: WorkbenchClip, id: UUID) -> some View {
        Toggle(L("片段静音"), isOn: Binding(get: { clip.muted }, set: { _ in model.toggleClipMute(id) }))
            .font(SettingsAppearance.detailFont)
    }

    private func clipDeleteButton(id: UUID) -> some View {
        Button(L("删除片段"), role: .destructive) { model.deleteClip(id) }
            .buttonStyle(.bordered)
            .disabled(model.document.clips.count <= 1)
    }

    private func gainVolumeControls(gain: WorkbenchAudioGain, id: UUID) -> some View {
        HStack(spacing: 6) {
            Text(L("音量")).font(SettingsAppearance.detailFont)
            Slider(value: Binding(get: { gain.volume }, set: { model.setGainVolume($0, id: id) }), in: 0...1)
                .frame(width: 140)
            Text("\(Int(gain.volume * 100))%").font(SettingsAppearance.detailFont).frame(width: 40)
        }
    }

    private func fadeSlider(label: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(SettingsAppearance.detailFont)
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...2)
                .controlSize(.small).frame(width: 90)
            Text("\(String(format: "%.1f", value))s").monospacedDigit()
                .font(SettingsAppearance.detailFont).foregroundStyle(.secondary).frame(width: 32)
        }
    }
}
