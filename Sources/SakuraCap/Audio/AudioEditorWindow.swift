import AppKit
import AVFoundation
import SwiftUI

// MARK: - 窗口与呈现

/// 音频编辑器窗口：接管回车/空格/S/Delete/⌘Z 等快捷键（输入框除外）
final class AudioEditorWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// 音频编辑器：上波形、下时间轴与操作，专用页面（与录屏工作台分离）。
/// 数据与导出复用 WorkbenchViewModel 引擎，界面为音频原生。
@MainActor
final class AudioEditorPresenter: NSObject, NSWindowDelegate {
    static let shared = AudioEditorPresenter()

    private var entries: [(window: AudioEditorWindow, model: WorkbenchViewModel)] = []
    /// 每扇窗口的 willClose token，关窗时一并移除，避免 NotificationCenter 累积注册
    private var closeObservers: [NSWindow: NSObjectProtocol] = [:]

    func show(url: URL, origin: TrimOrigin) {
        if let existing = entries.first(where: { $0.model.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            NSApp.activate(ignoringOtherApps: true)
            existing.window.makeKeyAndOrderFront(nil)
            existing.window.orderFrontRegardless()
            return
        }
        let model = WorkbenchViewModel(url: url)
        model.origin = origin
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let window = AudioEditorWindow(contentRect: NSRect(x: 0, y: 0,
                                                           width: min(640, screen.width * 0.46),
                                                           height: min(460, screen.height * 0.56)),
                                       styleMask: [.titled, .closable, .resizable],
                                       backing: .buffered, defer: false)
        window.title = String(format: L("音频编辑 — %@"), url.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 540, height: 400)
        window.contentView = NSHostingView(rootView: AudioEditorView(model: model))
        window.delegate = self
        model.requestClose = { [weak window] in window?.close() }
        window.keyHandler = { [weak model] event in
            guard let model else { return false }
            return Self.handleKey(event, model: model)
        }
        window.center()
        entries.append((window, model))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                           object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let closed = note.object as? NSWindow else { return }
                self?.removeEntry(for: closed)
            }
        }
        closeObservers[window] = token
    }

    private func removeEntry(for closed: NSWindow) {
        entries.removeAll { $0.window === closed }
        if let token = closeObservers[closed] {
            NotificationCenter.default.removeObserver(token)
            closeObservers[closed] = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let entry = entries.first(where: { $0.window === sender }) else { return true }
        if entry.model.isProgrammaticClose { return true }
        return entry.model.confirmDiscard()
    }

    private static func handleKey(_ event: NSEvent, model: WorkbenchViewModel) -> Bool {
        if let view = NSApp.keyWindow?.firstResponder as? NSTextView, view.isFieldEditor { return false }
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let key = event.charactersIgnoringModifiers ?? ""
        if command {
            if key == "z" {
                if shift { model.redo() } else { model.undo() }
                return true
            }
            return false
        }
        switch key {
        case " ":
            model.togglePlay()
            return true
        case "\u{F702}":   // ←
            model.seek(to: model.currentTime - (shift ? 1 : 1 / 30.0))
            return true
        case "\u{F703}":   // →
            model.seek(to: model.currentTime + (shift ? 1 : 1 / 30.0))
            return true
        case "s", "S":
            model.splitAtPlayhead()
            return true
        case "\u{7F}", "\u{8}":
            switch model.selection {
            case .clip(let id): model.deleteClip(id)
            case .audioGain(let id): model.removeGain(id)
            default: return false
            }
            return true
        default:
            return false
        }
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
                    HStack(spacing: 14) {
                        Text(L("音频片段")).font(SettingsAppearance.detailFont.weight(.semibold)).foregroundStyle(.secondary)
                        fadeSlider(label: L("声音淡入"), value: clip.fadeIn) { model.setClipFade(.in, $0, forClip: id) }
                        fadeSlider(label: L("声音淡出"), value: clip.fadeOut) { model.setClipFade(.out, $0, forClip: id) }
                        Text(L("音量")).font(SettingsAppearance.detailFont)
                        Slider(value: Binding(get: { clip.volume },
                                              set: { model.setClipVolume($0, forClip: id) }), in: 0...2)
                            .controlSize(.small).frame(width: 90)
                        Text("\(Int(clip.volume * 100))%").monospacedDigit()
                            .font(SettingsAppearance.detailFont).frame(width: 40)
                        Toggle(L("片段静音"), isOn: Binding(get: { clip.muted }, set: { _ in model.toggleClipMute(id) }))
                            .font(SettingsAppearance.detailFont)
                        Spacer()
                        Button(L("删除片段"), role: .destructive) { model.deleteClip(id) }
                            .buttonStyle(.bordered)
                            .disabled(model.document.clips.count <= 1)
                    }
                }
            case .audioGain(let id):
                if let gain = model.document.audioGains.first(where: { $0.id == id }) {
                    HStack(spacing: 14) {
                        Text(L("音量段")).font(SettingsAppearance.detailFont.weight(.semibold)).foregroundStyle(.secondary)
                        Text(L("音量")).font(SettingsAppearance.detailFont)
                        Slider(value: Binding(get: { gain.volume }, set: { model.setGainVolume($0, id: id) }), in: 0...1)
                            .frame(width: 140)
                        Text("\(Int(gain.volume * 100))%").monospacedDigit().font(SettingsAppearance.detailFont).frame(width: 40)
                        Button(gain.volume == 0 ? L("恢复音量") : L("静音此段")) { model.toggleGainMute(id) }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button(L("删除音量段"), role: .destructive) { model.removeGain(id) }
                            .buttonStyle(.bordered)
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
