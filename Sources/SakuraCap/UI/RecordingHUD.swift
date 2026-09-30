import AppKit
import SwiftUI
import Combine

/// 录制中的悬浮控制条：计时 / 暂停继续 / 停止。
/// 窗口 sharingType = .none，因此永远不会出现在录像画面里；可拖动，位置自动记忆。
@MainActor
final class RecordingHUDController {
    private let controller: RecordingController
    private var window: NSWindow?
    private var hosting: NSHostingView<RecordingHUDView>?
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
        // 等 SwiftUI 根据新状态布局后，再按内容尺寸调整窗口（保持右上角不动）
        DispatchQueue.main.async { [weak self] in self?.resizeToFit() }
    }

    private func resizeToFit() {
        guard let window, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        guard abs(window.frame.width - size.width) > 0.5 || abs(window.frame.height - size.height) > 0.5 else { return }
        // 保持底部居中不动
        let centerX = window.frame.midX
        let bottomY = window.frame.minY
        window.setFrame(NSRect(x: centerX - size.width / 2, y: bottomY,
                               width: size.width, height: size.height), display: true)
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: RecordingHUDView(controller: controller))
        self.hosting = hosting
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
        // 位置持久化；无历史记录时落在主屏底部居中
        if !window.setFrameAutosaveName("RecordingHUDBottom") || window.frame.origin == .zero {
            positionBottomCenter(window, size: size)
        }
        return window
    }

    private func positionBottomCenter(_ window: NSWindow, size: NSSize) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                      y: visible.minY + 24))
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct RecordingHUDView: View {
    @ObservedObject var controller: RecordingController
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            switch controller.state {
            case .ready:
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("准备就绪").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 4)
                resolutionPicker
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
        .frame(height: 44)
        .fixedSize()
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
    }

    private var resolutionPicker: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.compress.vertical")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Picker("", selection: $settings.outputResolution) {
                ForEach(OutputResolution.allCases) { resolution in
                    Text(resolution.label).tag(resolution)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .help("输出分辨率")
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
