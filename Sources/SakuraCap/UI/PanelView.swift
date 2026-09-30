import SwiftUI
import AVFoundation

/// 主面板：模式选择、显示器/窗口/区域、音频、点击指示、编码与帧率、输出目录、快捷键、权限引导。
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject private var controller: RecordingController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var indicator = IndicatorEngine.shared
    @ObservedObject private var keyDisplay = KeyDisplay.shared
    @ObservedObject private var camera = CameraPiP.shared

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case audio
        case appearance
        case video
        case general

        var id: String { rawValue }
        var label: String {
            switch self {
            case .audio: return L("音频")
            case .appearance: return L("标记")
            case .video: return L("画质")
            case .general: return L("通用")
            }
        }
    }

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.controller = viewModel.controller
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Picker("设置分区", selection: Binding(
                get: { SettingsSection(rawValue: viewModel.settingsSection) ?? .general },
                set: { viewModel.settingsSection = $0.rawValue }
            )) {
                ForEach(SettingsSection.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            settingsContent
            if let banner = controller.banner {
                Label(banner, systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(14)
        .frame(width: 392, alignment: .leading)
        .onAppear { viewModel.appear() }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch SettingsSection(rawValue: viewModel.settingsSection) ?? .general {
        case .audio:
            audioCard
                .disabled(controller.isBusy)
        case .appearance:
            VStack(alignment: .leading, spacing: 12) {
                indicatorCard
                keyDisplayCard
                cameraCard
            }
            .disabled(controller.isBusy)
        case .video:
            optionsCard
                .disabled(controller.isBusy)
        case .general:
            outputCard
            loginCard
            postRecordingCard
            dndCard
            hotKeyCard
            permissionCards
        }
    }

    // MARK: - 头部与录制按钮

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.aperture")
                .foregroundStyle(.pink)
            Text("Sakura-Cap").font(.headline)
            Spacer()
            if controller.state == .recording {
                Text(StatusItemController.mmss(controller.elapsed))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.red)
            } else if controller.state != .idle {
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch controller.state {
        case .ready: return L("准备就绪")
        case .preparing: return L("准备中…")
        case .countdown: return L("即将开始…")
        case .finalizing: return L("正在保存…")
        default: return ""
        }
    }

    // MARK: - 音频

    private var audioCard: some View {
        card("音频") {
            Toggle("系统声音", isOn: $settings.recordSystemAudio)
            Toggle("麦克风", isOn: $settings.recordMicrophone)
                .onChange(of: settings.recordMicrophone) { enabled in
                    if enabled { viewModel.ensureMicrophonePermission() }
                }
            Text("系统声音与麦克风会分开录制，可在播放器中切换。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 点击指示

    private var indicatorCard: some View {
        card("鼠标点击标记") {
            Toggle("在画面中标记鼠标点击", isOn: $settings.clickIndicatorEnabled)
                .onChange(of: settings.clickIndicatorEnabled) { enabled in
                    if enabled {
                        IndicatorEngine.shared.start()
                    } else {
                        IndicatorEngine.shared.stop()
                    }
                }
            if settings.clickIndicatorEnabled {
                ColorPicker("颜色", selection: Binding(
                    get: { settings.indicatorColor },
                    set: { settings.indicatorColor = $0 }
                ), supportsOpacity: false)
                HStack {
                    Text("大小")
                    Slider(value: $settings.indicatorSize, in: 36...100, step: 4)
                    Text("\(Int(settings.indicatorSize))").monospacedDigit().frame(width: 28)
                }
                HStack {
                    Text("时长")
                    Slider(value: $settings.indicatorDuration, in: 0.3...1.5, step: 0.1)
                    Text(String(format: "%.1fs", settings.indicatorDuration)).monospacedDigit().frame(width: 36)
                }
                Toggle("包含右键点击", isOn: $settings.indicatorIncludeRightClick)
                if indicator.permissionDenied {
                    permissionCard(title: "缺少「输入监控」权限",
                                   detail: "授权后点击标记才会显示，不影响录制。请在系统设置中勾选 Sakura-Cap。",
                                   buttonTitle: "打开系统设置") {
                        PermissionCenter.openInputMonitoringSettings()
                    }
                }
            }
        }
    }

    // MARK: - 键盘按键显示

    private var keyDisplayCard: some View {
        card("键盘按键显示") {
            Toggle("在画面左下角显示所按的按键", isOn: $settings.keyDisplayEnabled)
                .onChange(of: settings.keyDisplayEnabled) { enabled in
                    if enabled {
                        KeyDisplay.shared.start()
                    } else {
                        KeyDisplay.shared.stop()
                    }
                }
            Text("录制时在画面左下角浮出所按的按键，约 1 秒后淡出。")
                .font(.caption).foregroundStyle(.secondary)
            if settings.keyDisplayEnabled && keyDisplay.permissionDenied {
                permissionCard(title: "缺少「输入监控」权限",
                               detail: "授权后按键提示才会显示，不影响录制。请在系统设置中勾选 Sakura-Cap 并重启应用。",
                               buttonTitle: "打开系统设置") {
                    PermissionCenter.openInputMonitoringSettings()
                }
            }
        }
    }

    // MARK: - 摄像头画中画

    private var cameraCard: some View {
        card("摄像头画中画") {
            Toggle("在画面中显示摄像头", isOn: $settings.cameraPiPEnabled)
                .onChange(of: settings.cameraPiPEnabled) { enabled in
                    CameraPiP.shared.setEnabled(enabled)
                }
            if settings.cameraPiPEnabled {
                Picker("摄像头", selection: $settings.cameraPiPDeviceID) {
                    Text("系统默认").tag("")
                    ForEach(camera.devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                .onChange(of: settings.cameraPiPDeviceID) { _ in CameraPiP.shared.refreshConfiguration() }
                HStack {
                    Text("大小")
                    Slider(value: $settings.cameraPiPSize, in: 10...40, step: 2)
                        .onChange(of: settings.cameraPiPSize) { _ in CameraPiP.shared.refreshConfiguration() }
                    Text("\(Int(settings.cameraPiPSize))%").monospacedDigit().frame(width: 36)
                }
                Picker("位置", selection: $settings.cameraPiPCorner) {
                    ForEach(PiPCorner.allCases) { corner in
                        Text(corner.label).tag(corner)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.cameraPiPCorner) { _ in CameraPiP.shared.refreshConfiguration() }
                Toggle("镜像画面", isOn: $settings.cameraPiPMirror)
                    .onChange(of: settings.cameraPiPMirror) { _ in CameraPiP.shared.refreshConfiguration() }
                Text("录制时摄像头以圆角小窗显示在所选角落，可拖动调整位置。")
                    .font(.caption).foregroundStyle(.secondary)
                if camera.permissionDenied {
                    permissionCard(title: "缺少「摄像头」权限",
                                   detail: "授权后摄像头画面才会显示，不影响录制。请在系统设置中允许 Sakura-Cap 使用摄像头。",
                                   buttonTitle: "打开系统设置") {
                        PermissionCenter.openCameraSettings()
                    }
                }
            }
        }
    }

    // MARK: - 选项 / 输出 / 快捷键

    private var optionsCard: some View {
        card("选项") {
            Toggle("开始前 3 秒倒计时", isOn: $settings.countdownEnabled)
            Toggle("显示鼠标指针", isOn: $settings.showCursor)
            Toggle("开始 / 结束提示音", isOn: $settings.soundEnabled)
            Picker("画质", selection: $settings.quality) {
                ForEach(VideoQuality.allCases) { q in
                    Text(q.label).tag(q)
                }
            }
            .labelsHidden()
            if settings.quality == .custom {
                HStack {
                    Text("码率")
                    Slider(value: $settings.customBitrateMbps, in: 2...80, step: 2)
                    Text("\(Int(settings.customBitrateMbps)) Mbps").monospacedDigit().frame(width: 70)
                }
            }
            Picker("输出分辨率", selection: $settings.outputResolution) {
                ForEach(OutputResolution.allCases) { resolution in
                    Text(resolution.label).tag(resolution)
                }
            }
            Text("录制前可在悬浮控制条上临时切换；这里设为默认值。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("编码")
                Picker("", selection: $settings.codec) {
                    ForEach(VideoCodec.allCases) { codec in
                        Text(codec.label).tag(codec)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Picker("", selection: $settings.fps) {
                    ForEach(FPSOption.allCases) { fps in
                        Text(fps.label).tag(fps)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 86)
            }
            Picker("色彩空间", selection: $settings.colorSpace) {
                ForEach(ColorSpaceOption.allCases) { cs in
                    Text(cs.label).tag(cs)
                }
            }
            Text("HEVC 同画质下文件更小、更省空间；H.264 兼容性更广。画质越高画面越清晰，文件也越大。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var outputCard: some View {
        card("输出目录") {
            HStack {
                Image(systemName: "folder")
                Text(settings.outputDirectory?.path ?? "尚未选择（开始录制时会要求选择）")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("更改…") { viewModel.chooseOutputDirectory() }
            }
        }
    }

    private var loginCard: some View {
        card("启动") {
            Toggle("开机时自动启动", isOn: $settings.launchAtLogin)
            Text("随系统登录自动在菜单栏启动（首次需在系统设置→通用→登录项中允许）。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var postRecordingCard: some View {
        card("录制完成后") {
            Toggle("自动打开裁剪页", isOn: $settings.autoTrimAfterRecording)
        }
    }

    private var dndCard: some View {
        card("录屏勿扰") {
            Toggle("录屏时开启勿扰模式", isOn: $settings.dndDuringRecording)
            if settings.dndDuringRecording {
                Text("通过「快捷指令」切换专注模式：请在「快捷指令」App 里新建两个快捷指令（用「设置专注模式」动作，分别设为开启与关闭），名称如下：")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("开启").font(.caption).frame(width: 32, alignment: .leading)
                    TextField("", text: $settings.dndOnShortcut).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("关闭").font(.caption).frame(width: 32, alignment: .leading)
                    TextField("", text: $settings.dndOffShortcut).textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var hotKeyCard: some View {
        card("全局快捷键") {
            HotKeyRecorderView().frame(height: 30)
            Text(String(format: L("开始 / 停止录制，当前：%@"), settings.hotKeyDisplay))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 权限

    @ViewBuilder
    private var permissionCards: some View {
        if !PermissionCenter.screenCaptureGranted() {
            permissionCard(title: "缺少「屏幕录制」权限",
                           detail: "授权后 Sakura-Cap 才能录制屏幕画面。若已勾选但仍无效，请重启应用。",
                           buttonTitle: "打开系统设置") {
                PermissionCenter.openScreenCaptureSettings()
            }
        }
        if settings.recordMicrophone && PermissionCenter.microphoneDenied {
            permissionCard(title: "麦克风权限被拒绝",
                           detail: "录制可以继续，但不会包含麦克风声音。",
                           buttonTitle: "打开系统设置") {
                PermissionCenter.openMicrophoneSettings()
            }
        }
    }

    private func permissionCard(title: LocalizedStringKey, detail: LocalizedStringKey, buttonTitle: LocalizedStringKey,
                                action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.shield.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Button(buttonTitle, action: action).controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - 通用

    private var footer: some View {
        HStack {
            Spacer()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")")
                .font(.caption2).foregroundStyle(.tertiary)
            Button("退出") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
