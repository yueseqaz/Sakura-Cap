import SwiftUI

/// 主面板：模式选择、显示器/窗口/区域、音频、点击指示、编码与帧率、输出目录、快捷键、权限引导。
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject private var controller: RecordingController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var catalog = DisplayCatalog.shared
    @ObservedObject private var indicator = IndicatorEngine.shared

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case audio
        case appearance
        case video
        case general

        var id: String { rawValue }
        var label: String {
            switch self {
            case .audio: return "音频"
            case .appearance: return "指示"
            case .video: return "画质"
            case .general: return "通用"
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
            indicatorCard
                .disabled(controller.isBusy)
        case .video:
            optionsCard
                .disabled(controller.isBusy)
        case .general:
            outputCard
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
        case .preparing: return "准备中…"
        case .countdown: return "即将开始…"
        case .finalizing: return "正在保存…"
        default: return ""
        }
    }

    private var recordButton: some View {
        Button(action: { viewModel.toggleRecord() }) {
            HStack(spacing: 8) {
                Image(systemName: controller.state == .recording ? "stop.fill" : "record.circle")
                Text(controller.state == .recording
                     ? "停止录制（\(StatusItemController.mmss(controller.elapsed))）"
                     : "开始录制（\(settings.hotKeyDisplay)）")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
        }
        .buttonStyle(.borderedProminent)
        .tint(controller.state == .recording ? .red : .pink)
        .disabled(controller.state == .preparing || controller.state == .finalizing)
    }

    // MARK: - 录制内容

    private var contentCard: some View {
        card("录制内容") {
            Picker("模式", selection: $settings.captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch settings.captureMode {
            case .display:
                if catalog.displays.isEmpty {
                    Text(catalogHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: $settings.selectedDisplayID) {
                        ForEach(catalog.displays) { display in
                            HStack {
                                Text(display.name)
                                if display.isMain {
                                    Text("主屏").font(.caption2).foregroundStyle(.pink)
                                }
                                Text("\(display.resolutionText) · \(display.scaleText)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(display.id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Toggle("所有显示器分别保存（并行录制）", isOn: $settings.allDisplaysParallel)
                }
            case .region:
                Text(viewModel.regionSummary).font(.callout)
                Button("框选区域并开始录制…") { viewModel.pickRegion() }
                Text("也可以点菜单栏图标 →「开始录制 → 框选区域」")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var catalogHint: String {
        PermissionCenter.screenCaptureGranted() ? "正在加载显示器…" : "需要「屏幕录制」权限后才能列出显示器"
    }

    // MARK: - 音频

    private var audioCard: some View {
        card("音频") {
            Toggle("系统声音", isOn: $settings.recordSystemAudio)
            Toggle("麦克风", isOn: $settings.recordMicrophone)
                .onChange(of: settings.recordMicrophone) { enabled in
                    if enabled { viewModel.ensureMicrophonePermission() }
                }
            Text("系统声音与麦克风将保存为两条独立音轨")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 点击指示

    private var indicatorCard: some View {
        card("鼠标点击指示") {
            Toggle("在视频中标记鼠标点击", isOn: $settings.clickIndicatorEnabled)
                .onChange(of: settings.clickIndicatorEnabled) { enabled in
                    if enabled {
                        IndicatorEngine.shared.start()
                    } else {
                        IndicatorEngine.shared.stop()
                    }
                }
            if settings.clickIndicatorEnabled {
                Picker("样式", selection: $settings.indicatorStyle) {
                    ForEach(IndicatorStyleKind.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
                                   detail: "授权后点击标记才会显示（录制本身不受影响）。去系统设置勾选 Sakura-Cap 后，重新开始录制即可生效。",
                                   buttonTitle: "打开系统设置") {
                        PermissionCenter.openInputMonitoringSettings()
                    }
                }
            }
        }
    }

    // MARK: - 选项 / 输出 / 快捷键

    private var optionsCard: some View {
        card("选项") {
            Toggle("开始前 3 秒倒计时（不录入视频）", isOn: $settings.countdownEnabled)
            Toggle("显示鼠标指针", isOn: $settings.showCursor)
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
            Text("提示：HEVC 同画质下文件明显更小；「高」画质 4K30 约 27Mbps（H.264）。色彩标注为 BT.709，可用 ./verify.sh 校验")
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

    private var hotKeyCard: some View {
        card("全局快捷键") {
            HotKeyRecorderView().frame(height: 30)
            Text("开始 / 停止录制，当前：\(settings.hotKeyDisplay)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 权限

    @ViewBuilder
    private var permissionCards: some View {
        if !PermissionCenter.screenCaptureGranted() {
            permissionCard(title: "缺少「屏幕录制」权限",
                           detail: "授权后 Sakura-Cap 才能采集屏幕画面。勾选后如未生效请重启应用。",
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

    private func permissionCard(title: String, detail: String, buttonTitle: String,
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
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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
