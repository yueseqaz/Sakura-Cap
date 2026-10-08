import SwiftUI
import AVFoundation

/// 设置面板：左侧分区导航 + 右侧内容。同时作为菜单栏弹出的主面板。
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject private var controller: RecordingController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var indicator = IndicatorEngine.shared
    @ObservedObject private var keyDisplay = KeyDisplay.shared
    @ObservedObject private var camera = CameraPiP.shared

    private enum Section: String, CaseIterable, Identifiable {
        case record, assist, hotkeys, translate, permissions, general, about

        var id: String { rawValue }
        var label: String {
            switch self {
            case .record: return L("录制")
            case .assist: return L("辅助")
            case .hotkeys: return L("快捷键")
            case .translate: return L("翻译")
            case .permissions: return L("权限")
            case .general: return L("通用")
            case .about: return L("关于")
            }
        }
        var icon: String {
            switch self {
            case .record: return "record.circle"
            case .assist: return "wand.and.stars"
            case .hotkeys: return "keyboard"
            case .translate: return "character.bubble"
            case .permissions: return "lock.shield"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    private let labelWidth: CGFloat = 92

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.controller = viewModel.controller
    }

    private var selected: Section {
        Section(rawValue: viewModel.settingsSection) ?? .general
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                header
                ScrollView(.vertical, showsIndicators: true) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
                if let banner = controller.banner {
                    Label(banner, systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                footer
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.regularMaterial)
        .tint(.accentColor)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .onAppear {
            viewModel.appear()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // macOS 的隐私设置在外部修改；回到应用时重新读取，避免显示旧状态。
            viewModel.refreshPermissions()
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "camera.aperture")
                    .font(.title3)
                    .foregroundStyle(.pink)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.pink.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sakura-Cap")
                        .font(.headline)
                    Text("录制 · 截图 · 标注")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 3) {
            ForEach(Section.allCases) { section in
                Button {
                    viewModel.settingsSection = section.rawValue
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.icon)
                            .frame(width: 18)
                        Text(section.label)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(selected == section ? Color.accentColor.opacity(0.16) : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(selected == section ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 0.5))
                    .foregroundStyle(selected == section ? Color.accentColor : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Label(controller.state == .recording ? L("正在录制") : L("准备就绪"),
                      systemImage: controller.state == .recording ? "record.circle.fill" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(controller.state == .recording ? .red : .secondary)
                Text(L("从菜单栏图标开始录制或截图"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .padding(.top, 2)
        .frame(width: 204)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "camera.aperture").foregroundStyle(.pink)
            Text("Sakura-Cap").font(.headline)
            Spacer()
            if controller.state == .recording {
                Text(StatusItemController.mmss(controller.elapsed))
                    .font(.headline).monospacedDigit().foregroundStyle(.red)
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

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .record: recordSection
        case .assist: assistSection
        case .hotkeys: hotkeysSection
        case .translate: translateSection
        case .permissions: permissionsSection
        case .general: generalSection
        case .about: aboutSection
        }
    }

    // MARK: 录制

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("音频", icon: "waveform") {
                Toggle("系统声音", isOn: $settings.recordSystemAudio)
                Toggle("麦克风", isOn: $settings.recordMicrophone)
                    .onChange(of: settings.recordMicrophone) { enabled in
                        if enabled { viewModel.ensureMicrophonePermission() }
                    }
                if settings.recordMicrophone {
                    Picker("麦克风设备", selection: $settings.microphoneDeviceID) {
                        Text(L("系统默认")).tag("")
                        ForEach(CaptureDevices.microphones(), id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                }
                footnote("系统声音与麦克风分开录制，可在播放器中切换。")
            }
            group("画质", icon: "film") {
                Picker("画质", selection: $settings.quality) {
                    ForEach(VideoQuality.allCases) { q in Text(q.label).tag(q) }
                }
                if settings.quality == .custom {
                    sliderRow("码率", value: $settings.customBitrateMbps, range: 2...80, step: 2,
                              text: "\(Int(settings.customBitrateMbps)) Mbps", width: 72)
                }
                Picker("输出分辨率", selection: $settings.outputResolution) {
                    ForEach(OutputResolution.allCases) { r in Text(r.label).tag(r) }
                }
                settingRow("编码") {
                    HStack(spacing: 8) {
                        Picker("", selection: $settings.codec) {
                            ForEach(VideoCodec.allCases) { c in Text(c.label).tag(c) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Picker("", selection: $settings.fps) {
                            ForEach(FPSOption.allCases) { f in Text(f.label).tag(f) }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 92)
                    }
                }
                Picker("色彩空间", selection: $settings.colorSpace) {
                    ForEach(ColorSpaceOption.allCases) { cs in Text(cs.label).tag(cs) }
                }
                footnote("HEVC 同画质下文件更小、更省空间；H.264 兼容性更广。")
            }
            group("其它", icon: "switch.2") {
                Toggle("开始前 3 秒倒计时", isOn: $settings.countdownEnabled)
                Toggle("显示鼠标指针", isOn: $settings.showCursor)
                Toggle("开始 / 结束提示音", isOn: $settings.soundEnabled)
                footnote("录制前可在悬浮控制条上临时切换；这里设为默认值。")
            }
        }
    }

    // MARK: 辅助

    private var assistSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("鼠标点击标记", icon: "cursorarrow.rays") {
                Toggle("在画面中标记鼠标点击", isOn: $settings.clickIndicatorEnabled)
                    .onChange(of: settings.clickIndicatorEnabled) { enabled in
                        if enabled { IndicatorEngine.shared.start() } else { IndicatorEngine.shared.stop() }
                    }
                if settings.clickIndicatorEnabled {
                    ColorPicker("颜色", selection: Binding(
                        get: { settings.indicatorColor },
                        set: { settings.indicatorColor = $0 }
                    ), supportsOpacity: false)
                    sliderRow("大小", value: $settings.indicatorSize, range: 36...100, step: 4,
                              text: "\(Int(settings.indicatorSize))", width: 30)
                    sliderRow("时长", value: $settings.indicatorDuration, range: 0.3...1.5, step: 0.1,
                              text: String(format: "%.1fs", settings.indicatorDuration), width: 36)
                    Toggle("包含右键点击", isOn: $settings.indicatorIncludeRightClick)
                }
            }
            group("键盘按键显示", icon: "keyboard") {
                Toggle("在画面左下角显示所按的按键", isOn: $settings.keyDisplayEnabled)
                    .onChange(of: settings.keyDisplayEnabled) { enabled in
                        if enabled { KeyDisplay.shared.start() } else { KeyDisplay.shared.stop() }
                    }
                footnote("约 1 秒后淡出。")
            }
            group("摄像头画中画", icon: "web.camera") {
                Toggle("在画面中显示摄像头", isOn: $settings.cameraPiPEnabled)
                    .onChange(of: settings.cameraPiPEnabled) { enabled in
                        CameraPiP.shared.setEnabled(enabled)
                    }
                if settings.cameraPiPEnabled {
                    Picker("摄像头", selection: $settings.cameraPiPDeviceID) {
                        Text(L("系统默认")).tag("")
                        ForEach(camera.devices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .onChange(of: settings.cameraPiPDeviceID) { _ in CameraPiP.shared.refreshConfiguration() }
                    sliderRow("大小", value: $settings.cameraPiPSize, range: 10...40, step: 2,
                              text: "\(Int(settings.cameraPiPSize))%", width: 40)
                    settingRow("位置") {
                        Picker("", selection: $settings.cameraPiPCorner) {
                            ForEach(PiPCorner.allCases) { corner in Text(corner.label).tag(corner) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .onChange(of: settings.cameraPiPCorner) { _ in CameraPiP.shared.refreshConfiguration() }
                    }
                    Toggle("镜像画面", isOn: $settings.cameraPiPMirror)
                        .onChange(of: settings.cameraPiPMirror) { _ in CameraPiP.shared.refreshConfiguration() }
                    footnote("录制时摄像头以圆角小窗显示在所选角落，可拖动调整位置。")
                }
            }
        }
    }

    // MARK: 快捷键

    private var hotkeysSection: some View {
        group("全局快捷键", icon: "command") {
            ForEach(HotKeyAction.allCases) { action in
                HStack {
                    Text(action.label).font(.callout).frame(width: 132, alignment: .leading)
                    HotKeyRecorderView(action: action).frame(height: 28)
                }
            }
            footnote("默认为空（未设置）。点一下输入框后按下组合键即可设置，按 Delete 清除。")
        }
    }

    // MARK: 翻译

    private var translateSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("翻译服务", icon: "character.bubble") {
                settingRow("服务商") {
                    Picker("", selection: $settings.translateProvider) {
                        ForEach(TranslateProvider.allCases) { p in Text(p.label).tag(p) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                if settings.translateProvider == .deepSeek {
                    footnote("DeepSeek：模型默认 deepseek-chat，只需填 API Key。")
                } else {
                    fieldRow("API 地址") {
                        TextField("https://…/v1", text: $settings.translateBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                fieldRow("API Key") {
                    HStack(spacing: 6) {
                        SecureField("", text: settings.translateProvider == .deepSeek ? $settings.translateAPIKey : $settings.translateCustomAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Button("清除") {
                            if settings.translateProvider == .deepSeek { settings.translateAPIKey = "" } else { settings.translateCustomAPIKey = "" }
                        }
                        .controlSize(.small)
                    }
                }
                fieldRow("模型") {
                    HStack(spacing: 6) {
                        if settings.activeTranslateModels.isEmpty {
                            TextField("", text: settings.translateProvider == .deepSeek ? $settings.translateModel : $settings.translateCustomModel)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("", selection: settings.translateProvider == .deepSeek ? $settings.translateModel : $settings.translateCustomModel) {
                                ForEach(settings.activeTranslateModels, id: \.self) { m in Text(m).tag(m) }
                            }
                            .labelsHidden()
                        }
                        Button("获取模型") { fetchModels() }.controlSize(.small)
                    }
                }
                footnote("Key 仅保存在本机，除所填翻译服务外不会发送到任何地方。")
            }
            group("翻译方向", icon: "arrow.left.arrow.right") {
                Picker("原文语言", selection: $settings.translateSourceLang) {
                    ForEach(TranslateLanguage.allCases) { l in Text(l.label).tag(l.rawValue) }
                }
                Picker("译文语言", selection: $settings.translateTargetLang) {
                    ForEach(TranslateLanguage.allCases.filter { $0 != .auto }) { l in Text(l.label).tag(l.rawValue) }
                }
                Picker("翻译风格", selection: $settings.translateStyle) {
                    ForEach(TranslateStyle.allCases) { s in Text(s.label).tag(s.rawValue) }
                }
                footnote("截图子菜单「翻译」：框选后识别文字，按这里预设的方向与风格翻译。")
            }
        }
    }

    private func fetchModels() {
        let provider = settings.translateProvider
        let base = provider == .deepSeek ? provider.defaultBaseURL : settings.translateBaseURL
        let key = settings.activeTranslateAPIKey
        Task {
            do {
                let models = try await TranslationService.fetchModels(baseURL: base, apiKey: key)
                guard !models.isEmpty else {
                    Toast.show(title: L("获取模型失败"), detail: L("返回为空"))
                    return
                }
                if provider == .deepSeek {
                    settings.translateModels = models
                    if !models.contains(settings.translateModel) { settings.translateModel = models[0] }
                } else {
                    settings.translateCustomModels = models
                    if !models.contains(settings.translateCustomModel) { settings.translateCustomModel = models[0] }
                }
                Toast.show(title: L("已获取模型"), detail: "\(models.count)")
            } catch {
                Toast.show(title: L("获取模型失败"), detail: error.localizedDescription)
            }
        }
    }

    // MARK: 权限

    private var permissionsSection: some View {
        Group {
            let _ = viewModel.permissionRefreshToken
            group("权限", icon: "lock.shield") {
            permissionRow(name: L("屏幕录制"),
                          granted: PermissionCenter.screenCaptureGranted(),
                          detail: L("录制与截图需要。"),
                          action: { PermissionCenter.openScreenCaptureSettings() })
            permissionRow(name: L("麦克风"),
                          state: PermissionCenter.microphoneAccess,
                          detail: L("录制麦克风声音需要。"),
                          action: requestMicrophonePermission)
            permissionRow(name: L("输入监控"),
                          granted: PermissionCenter.inputMonitoringGranted(),
                          detail: L("鼠标点击标记 / 键盘按键显示需要。"),
                          action: { PermissionCenter.openInputMonitoringSettings() })
            permissionRow(name: L("摄像头"),
                          state: PermissionCenter.cameraAccess,
                          detail: camera.devices.isEmpty ? L("未检测到摄像头设备。") : L("摄像头画中画需要。"),
                          action: requestCameraPermission)
            }
        }
    }

    private func requestMicrophonePermission() {
        if PermissionCenter.microphoneAccess == .notDetermined {
            PermissionCenter.requestMicrophone { _ in
                Task { @MainActor in viewModel.refreshPermissions() }
            }
        } else {
            PermissionCenter.openMicrophoneSettings()
        }
    }

    private func requestCameraPermission() {
        camera.requestPermission {
            viewModel.refreshPermissions()
            if PermissionCenter.cameraAccess != .authorized {
                PermissionCenter.openCameraSettings()
            }
        }
    }

    private func permissionRow(name: String, state: PermissionCenter.AccessState? = nil,
                               granted: Bool? = nil, detail: String, action: @escaping () -> Void) -> some View {
        let isGranted = state?.isAuthorized ?? (granted ?? false)
        let isPending = state == .notDetermined
        let statusText: String = isGranted ? L("已授权") : L("未授权")
        let statusIcon = isGranted ? "checkmark.circle.fill" : "xmark.circle.fill"
        let statusColor: Color = isGranted ? .green : (isPending ? .orange : .red)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name).font(.callout).fontWeight(.medium)
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(isGranted || isPending ? L("打开系统设置") : L("去授权")) { action() }
                .controlSize(.small)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
    }

    // MARK: 通用

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("输出目录", icon: "folder") {
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(settings.outputDirectory?.path ?? L("尚未选择（开始录制时会要求选择）"))
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("更改…") { viewModel.chooseOutputDirectory() }.controlSize(.small)
                }
            }
            group("文件命名", icon: "textformat.abc") {
                TextField("{date}-{time}-{rand}", text: $settings.fileNamePattern)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    Text("示例：").font(.caption).foregroundStyle(.secondary)
                    Text(FileName.make(ext: "png"))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("恢复默认") { settings.fileNamePattern = FileName.defaultPattern }
                        .controlSize(.small)
                }
                footnote("占位符：{date} 日期、{time} 时间、{datetime} 日期时间、{rand} 5 位随机数。")
            }
            group("启动与行为", icon: "power") {
                Toggle("开机时自动启动", isOn: $settings.launchAtLogin)
                Toggle("录屏结束后自动打开裁剪页", isOn: $settings.autoTrimAfterRecording)
            }
            group("录屏勿扰", icon: "moon") {
                Toggle("录屏时开启勿扰模式", isOn: $settings.dndDuringRecording)
                if settings.dndDuringRecording {
                    footnote("通过「快捷指令」切换专注模式：在「快捷指令」App 新建两个快捷指令（用「设置专注模式」动作），名称如下：")
                    fieldRow("开启") { TextField("", text: $settings.dndOnShortcut).textFieldStyle(.roundedBorder) }
                    fieldRow("关闭") { TextField("", text: $settings.dndOffShortcut).textFieldStyle(.roundedBorder) }
                }
            }
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Sakura-Cap", icon: "info.circle") {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sakura-Cap").font(.title3).fontWeight(.semibold)
                        Text("\(L("版本")) \(AppInfo.version)")
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        Text(L("菜单栏常驻的极简 Mac 录屏 / 截图 / 标注工具。"))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button("欢迎使用…") { OnboardingWindowController.shared.show() }
                    Button("检查更新") { UpdateChecker.check(manual: true) }
                    Spacer()
                }
            }
            group("功能", icon: "square.grid.2x2") {
                aboutItem("record.circle", L("录制"), L("全屏 / 区域 / 窗口，暂停续录、摄像头画中画、点击标记、按键显示。"))
                aboutItem("camera.viewfinder", L("截图"), L("全屏 / 区域截图、OCR 取字、二维码识别、滚动截屏、AI 翻译。"))
                aboutItem("pencil.tip", L("标注与编辑"), L("画笔 / 箭头 / 矩形 / 文字 / 序号 / 马赛克 / 裁剪；吸管取色、两点测量、截图对比。"))
                aboutItem("film", L("视频处理"), L("录后裁剪与删除原文件、视频截帧、GIF 导出（可选尺寸）。"))
            }
            group("链接", icon: "link") {
                linkRow(L("GitHub 仓库"), AppInfo.repository)
                linkRow(L("发布版本"), AppInfo.repository.appendingPathComponent("releases"))
                linkRow(L("开发文档"), AppInfo.repository.appendingPathComponent("blob/main/docs/DEVELOPMENT.md"))
                footnote("© 2026 Sakura · 零第三方依赖，仅系统框架")
            }
        }
    }

    private func aboutItem(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.pink).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func linkRow(_ title: String, _ url: URL) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).frame(width: labelWidth, alignment: .leading)
            Text(url.absoluteString).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button("打开") { NSWorkspace.shared.open(url) }.controlSize(.small)
        }
    }

    // MARK: - 通用组件

    private var footer: some View {
        HStack {
            Spacer()
            Button("退出") { NSApp.terminate(nil) }.controlSize(.small)
        }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    private func settingRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).font(.callout).frame(width: labelWidth, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        settingRow(title) { content() }
    }

    private func sliderRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String, width: CGFloat) -> some View {
        settingRow(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step)
                Text(text).font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: width, alignment: .trailing)
            }
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
