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
            WindowDragHandle()
                .frame(width: 14, height: 22)
                .help(L("拖动移动"))
            switch controller.state {
            case .ready:
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("准备就绪").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 4)
                inputToggles
                resolutionPicker
                Button(action: { controller.start() }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.red))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("开始录制")
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

    /// 每次录屏需求不同：在 HUD 上直接开关麦克风 / 系统声音 / 摄像头
    private var inputToggles: some View {
        HStack(spacing: 2) {
            InputMenuButton(
                symbol: "mic.fill",
                isOn: settings.recordMicrophone,
                toggleTitle: settings.recordMicrophone ? L("关闭麦克风") : L("开启麦克风"),
                onToggle: micToggle,
                deviceNames: CaptureDevices.microphones().map { $0.localizedName },
                onSelect: selectMicrophone
            )
            .frame(width: 24, height: 24)
            .help("麦克风")
            inputToggle("speaker.wave.2.fill", on: settings.recordSystemAudio, help: "系统声音") {
                settings.recordSystemAudio.toggle()
            }
            InputMenuButton(
                symbol: "video.fill",
                isOn: settings.cameraPiPEnabled,
                toggleTitle: settings.cameraPiPEnabled ? L("关闭摄像头") : L("开启摄像头"),
                onToggle: cameraToggle,
                deviceNames: CameraPiP.shared.devices.map { $0.localizedName },
                onSelect: selectCamera
            )
            .frame(width: 24, height: 24)
            .help("摄像头画中画")
            inputToggle("cursorarrow.click", on: settings.clickIndicatorEnabled, help: "鼠标点击标记") {
                settings.clickIndicatorEnabled.toggle()
                if settings.clickIndicatorEnabled { IndicatorEngine.shared.start() } else { IndicatorEngine.shared.stop() }
            }
            inputToggle("keyboard", on: settings.keyDisplayEnabled, help: "键盘按键显示") {
                settings.keyDisplayEnabled.toggle()
                if settings.keyDisplayEnabled { KeyDisplay.shared.start() } else { KeyDisplay.shared.stop() }
            }
        }
    }

    private func micToggle() {
        settings.recordMicrophone.toggle()
        if settings.recordMicrophone { requestMicrophone() }
    }

    private func selectMicrophone(_ index: Int) {
        let devices = CaptureDevices.microphones()
        if index < 0 {
            settings.microphoneDeviceID = ""
        } else if devices.indices.contains(index) {
            settings.microphoneDeviceID = devices[index].uniqueID
            if !settings.recordMicrophone {
                settings.recordMicrophone = true
                requestMicrophone()
            }
        }
    }

    private func cameraToggle() {
        settings.cameraPiPEnabled.toggle()
        CameraPiP.shared.setEnabled(settings.cameraPiPEnabled)
    }

    private func selectCamera(_ index: Int) {
        let devices = CameraPiP.shared.devices
        if index < 0 {
            settings.cameraPiPDeviceID = ""
        } else if devices.indices.contains(index) {
            settings.cameraPiPDeviceID = devices[index].uniqueID
        }
        if !settings.cameraPiPEnabled {
            settings.cameraPiPEnabled = true
            CameraPiP.shared.setEnabled(true)
        }
        CameraPiP.shared.refreshConfiguration()
    }

    private func inputToggle(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func requestMicrophone() {
        guard PermissionCenter.microphoneUndetermined else { return }
        PermissionCenter.requestMicrophone { granted in
            Task { @MainActor in
                if !granted { settings.recordMicrophone = false }
            }
        }
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

/// HUD 的拖动把手：SwiftUI 内容会吃掉背景拖动事件，用原生视图调用 performDrag 才拖得动。
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setFill()
        let dot: CGFloat = 3
        for row in 0..<2 {
            for col in 0..<2 {
                let rect = NSRect(x: bounds.midX - dot + CGFloat(col) * 6 - 3,
                                  y: bounds.midY - dot + CGFloat(row) * 6 - 3,
                                  width: dot, height: dot)
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }
}

/// HUD 里的输入设备按钮：用 AppKit 按钮（contentTintColor 可靠着色）+ 点击弹出 NSMenu 选设备
struct InputMenuButton: NSViewRepresentable {
    let symbol: String
    let isOn: Bool
    let toggleTitle: String
    let onToggle: () -> Void
    let deviceNames: [String]
    let onSelect: (Int) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.tapped)
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        button.contentTintColor = isOn ? .controlAccentColor : .secondaryLabelColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: InputMenuButton
        weak var button: NSButton?
        init(_ parent: InputMenuButton) { self.parent = parent }

        @objc func tapped() {
            let menu = NSMenu()
            let toggle = NSMenuItem(title: parent.toggleTitle, action: #selector(toggleAction), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
            menu.addItem(.separator())
            let defaultItem = NSMenuItem(title: L("系统默认设备"), action: #selector(selectDefault), keyEquivalent: "")
            defaultItem.target = self
            menu.addItem(defaultItem)
            for (index, name) in parent.deviceNames.enumerated() {
                let item = NSMenuItem(title: name, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            if let button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
            }
        }

        @objc func toggleAction() { parent.onToggle() }
        @objc func selectDefault() { parent.onSelect(-1) }
        @objc func selectDevice(_ sender: NSMenuItem) { parent.onSelect(sender.tag) }
    }
}
