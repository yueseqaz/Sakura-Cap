import AppKit
import SwiftUI
import Combine

/// 录制中的悬浮控制条：计时 / 暂停继续 / 停止。
/// 窗口 sharingType = .none，因此永远不会出现在录像画面里；可拖动，位置自动记忆。
@MainActor
final class RecordingHUDController {
    private let controller: RecordingController
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(controller: RecordingController) {
        self.controller = controller
        controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)
    }

    /// 待开始 / 准备 / 倒计时 / 录制期间都显示
    func sync() {
        switch controller.state {
        case .ready, .preparing, .countdown, .recording:
            show()
        default:
            hide()
        }
    }

    private func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.orderFrontRegardless()
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: RecordingHUDView(controller: controller))
        let size = NSSize(width: 226, height: 44)
        let window = HUDPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none // 控制条绝不进入录制
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        window.setContentSize(size)
        // 位置持久化；无历史记录时落在主屏右上角
        if !window.setFrameAutosaveName("RecordingHUD") || window.frame.origin == .zero {
            positionTopRight(window, size: size)
        }
        return window
    }

    private func positionTopRight(_ window: NSWindow, size: NSSize) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 16,
                                      y: visible.maxY - size.height - 16))
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct RecordingHUDView: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        HStack(spacing: 10) {
            switch controller.state {
            case .ready:
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("准备就绪").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 4)
                Button("开始录制") { controller.start() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                cancelButton({ controller.cancelArmed() }, help: "取消")
            case .preparing, .countdown:
                ProgressView().controlSize(.small)
                Text(controller.state == .countdown ? "即将开始…" : "准备中…")
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 4)
                cancelButton({ controller.stop() }, help: "取消")
            default:
                recordingContent
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 226, height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder
    private var recordingContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(controller.isPaused ? 0.35 : 1)
            Text(StatusItemController.mmss(controller.elapsed))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .frame(width: 50, alignment: .leading)
        }

        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 18)

        Button(action: { controller.togglePause() }) {
            Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(controller.isPaused ? "继续录制" : "暂停录制")

        Button(action: { controller.stop() }) {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.red))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("停止录制")
    }

    private func cancelButton(_ action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
