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

    /// 仅在录制阶段显示（暂停时保持显示）
    func sync() {
        if controller.state == .recording {
            show()
        } else {
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
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
        .fixedSize()
    }
}
