import SwiftUI
import AVFoundation

private final class SettingsHelpState: ObservableObject {
    @Published var showsFileName = false
    @Published var showsShortcuts = false
}

/// 设置面板：左侧分区导航，右侧即时生效的设置。
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject private var controller: RecordingController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var camera = CameraPiP.shared
    @ObservedObject private var help = SettingsHelpState()

    private enum Section: String, CaseIterable, Identifiable {
        case record, assist, hotkeys, translate, imageHost, permissions, general, about

        var id: String { rawValue }
        var label: String {
            switch self {
            case .record: return L("录制")
            case .assist: return L("辅助")
            case .hotkeys: return L("快捷键")
            case .translate: return L("翻译与 AI")
            case .imageHost: return L("图床")
            case .permissions: return L("权限")
            case .general: return L("通用")
            case .about: return L("关于")
            }
        }
        var icon: String {
            switch self {
            case .record: return "record.circle"
            case .assist: return "cursorarrow.rays"
            case .hotkeys: return "keyboard"
            case .translate: return "character.bubble"
            case .imageHost: return "cloud"
            case .permissions: return "lock.shield"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    private let labelWidth: CGFloat = 112

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
            Rectangle()
                .fill(SettingsAppearance.color(SettingsAppearance.separator))
                .frame(width: SettingsAppearance.borderWidth)
            VStack(alignment: .leading, spacing: 20) {
                header
                ScrollView(.vertical, showsIndicators: true) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
                if let banner = controller.banner {
                    Label(banner, systemImage: "info.circle")
                        .font(SettingsAppearance.detailFont)
                        .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                footer
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsAppearance.color(SettingsAppearance.canvas))
        .foregroundStyle(SettingsAppearance.color(SettingsAppearance.text))
        .font(SettingsAppearance.bodyFont)
        .tint(SettingsAppearance.color(SettingsAppearance.accent))
        .buttonStyle(SettingsButtonStyle())
        .textFieldStyle(SettingsFieldStyle())
        .controlSize(.regular)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .onAppear { viewModel.appear() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissions()
        }
    }

    // MARK: - 导航与状态

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sakura-Cap")
                .font(SettingsAppearance.bodyFont.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.top, 22)
                .padding(.bottom, 24)
            VStack(spacing: 4) {
                ForEach(Section.allCases) { section in
                    Button {
                        viewModel.settingsSection = section.rawValue
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon).frame(width: 18)
                                .accessibilityHidden(true)
                            Text(section.label)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsNavigationStyle(selected: selected == section))
                    .accessibilityAddTraits(selected == section ? .isSelected : [])
                }
            }
            Spacer(minLength: 16)
            if controller.state != .idle {
                Label(controller.state == .recording ? L("正在录制") : statusText,
                      systemImage: controller.state == .recording ? "record.circle.fill" : "circle.dotted")
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(SettingsAppearance.color(controller.state == .recording ? SettingsAppearance.error : SettingsAppearance.secondary))
                    .padding(10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 168)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SettingsAppearance.color(SettingsAppearance.sidebar))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selected.label).font(SettingsAppearance.titleFont)
            Spacer()
            if controller.state == .recording {
                Text(StatusItemController.mmss(controller.elapsed))
                    .font(SettingsAppearance.bodyFont.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.error))
            }
        }
        .frame(minHeight: 24)
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

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .record: recordSection
        case .assist: assistSection
        case .hotkeys: hotkeysSection
        case .translate: translateSection
        case .imageHost: imageHostSection
        case .permissions: permissionsSection
        case .general: generalSection
        case .about: aboutSection
        }
    }

    // MARK: - 录制

    /// 下拉框统一收窄宽度，避免被 settingRow 的撑满布局拉成整行长条
    private let pickerWidth: CGFloat = 190

    /// 成对控件自适应排版：宽度够时并排（省纵向空间），不够时自动竖排——
    /// 任何窗口宽度下都不裁切内容
    @ViewBuilder
    private func settingPair<A: View, B: View>(_ first: A, _ second: B) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                first.frame(maxWidth: .infinity)
                second.frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 12) {
                first
                second
            }
        }
    }

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("音频") {
                settingPair(
                    Toggle("系统声音", isOn: $settings.recordSystemAudio)
                        .help(L("系统声音与麦克风分开录制，可在播放器中切换。")),
                    Toggle("麦克风", isOn: $settings.recordMicrophone)
                        .onChange(of: settings.recordMicrophone) { enabled in
                            if enabled { viewModel.ensureMicrophonePermission() }
                        })
                if settings.recordMicrophone {
                    settingRow("麦克风设备") {
                        Picker("麦克风设备", selection: $settings.microphoneDeviceID) {
                            Text(L("系统默认")).tag("")
                            ForEach(CaptureDevices.microphones(), id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }.labelsHidden().frame(width: pickerWidth)
                    }
                }
            }
            group("视频") {
                settingPair(
                    settingRow("画质") {
                        Picker("画质", selection: $settings.quality) {
                            ForEach(VideoQuality.allCases) { q in Text(q.label).tag(q) }
                        }.labelsHidden().frame(width: pickerWidth)
                    },
                    settingRow("帧率") {
                        Picker("帧率", selection: $settings.fps) {
                            ForEach(FPSOption.allCases) { f in Text(f.label).tag(f) }
                        }.labelsHidden().frame(width: pickerWidth)
                    })
                settingPair(
                    settingRow("输出分辨率") {
                        Picker("输出分辨率", selection: $settings.outputResolution) {
                            ForEach(OutputResolution.allCases) { r in Text(r.label).tag(r) }
                        }.labelsHidden().frame(width: pickerWidth)
                    },
                    settingRow("色彩空间") {
                        Picker("色彩空间", selection: $settings.colorSpace) {
                            ForEach(ColorSpaceOption.allCases) { cs in Text(cs.label).tag(cs) }
                        }.labelsHidden().frame(width: pickerWidth)
                    })
                settingRow("视频编码") {
                    Picker("视频编码", selection: $settings.codec) {
                        ForEach(VideoCodec.allCases) { c in Text(c.label).tag(c) }
                    }.pickerStyle(.segmented).labelsHidden()
                        .help(L("HEVC 文件更小，H.264 兼容性更广。"))
                }
                if settings.quality == .custom {
                    sliderRow("码率", value: $settings.customBitrateMbps, range: 2...80, step: 2,
                              text: "\(Int(settings.customBitrateMbps)) Mbps", width: 72)
                }
            }
            group("录制选项") {
                settingPair(
                    Toggle("开始前倒计时 3 秒", isOn: $settings.countdownEnabled),
                    Toggle("显示鼠标指针", isOn: $settings.showCursor))
                settingPair(
                    Toggle("显示录制帧率", isOn: $settings.showFPSOverlay),
                    Toggle("录制提示音", isOn: $settings.soundEnabled))
                Toggle("所有显示器并行录制（每屏各存一份）", isOn: $settings.allDisplaysParallel)
                    .help(L("开启后「全屏录制」不再点选屏幕，直接同时录制所有显示器，每块屏各存一个文件；系统声音与麦克风只写进主屏文件。想只录某一块屏时，请先关闭本开关再点选。"))
            }
        }
    }

    // MARK: - 辅助

    private var assistSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("鼠标点击标记") {
                Toggle("显示点击标记", isOn: $settings.clickIndicatorEnabled)
                if settings.clickIndicatorEnabled {
                    settingRow("颜色") {
                        ColorPicker("颜色", selection: Binding(
                            get: { settings.indicatorColor }, set: { settings.indicatorColor = $0 }
                        ), supportsOpacity: false).labelsHidden()
                    }
                    sliderRow("大小", value: $settings.indicatorSize, range: 36...100, step: 4,
                              text: "\(Int(settings.indicatorSize))", width: 30)
                    sliderRow("时长", value: $settings.indicatorDuration, range: 0.3...1.5, step: 0.1,
                              text: String(format: "%.1fs", settings.indicatorDuration), width: 36)
                    Toggle("包含右键点击", isOn: $settings.indicatorIncludeRightClick)
                }
            }
            group("键盘按键显示") {
                Toggle("显示按键", isOn: $settings.keyDisplayEnabled)
                    .help(L("在画面左下角显示按键，约 1 秒后淡出。"))
            }
            group("摄像头画中画") {
                Toggle("显示摄像头", isOn: $settings.cameraPiPEnabled)
                    .onChange(of: settings.cameraPiPEnabled) { enabled in
                        CameraPiP.shared.setEnabled(enabled)
                    }
                if settings.cameraPiPEnabled {
                    settingRow("摄像头") {
                        Picker("摄像头", selection: $settings.cameraPiPDeviceID) {
                            Text(L("系统默认")).tag("")
                            ForEach(camera.devices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }.labelsHidden()
                            .onChange(of: settings.cameraPiPDeviceID) { _ in CameraPiP.shared.refreshConfiguration() }
                    }
                    sliderRow("大小", value: $settings.cameraPiPSize, range: 10...40, step: 2,
                              text: "\(Int(settings.cameraPiPSize))%", width: 40)
                    settingRow("位置") {
                        Picker("位置", selection: $settings.cameraPiPCorner) {
                            ForEach(PiPCorner.allCases) { corner in Text(corner.label).tag(corner) }
                        }.pickerStyle(.segmented).labelsHidden()
                            .onChange(of: settings.cameraPiPCorner) { _ in CameraPiP.shared.refreshConfiguration() }
                    }
                    Toggle("镜像画面", isOn: $settings.cameraPiPMirror)
                        .onChange(of: settings.cameraPiPMirror) { _ in CameraPiP.shared.refreshConfiguration() }
                }
            }
        }
    }

    // MARK: - 快捷键

    private var hotkeysSection: some View {
        group("全局快捷键") {
            ForEach(HotKeyAction.allCases) { action in
                HStack(spacing: 12) {
                    Text(action.label)
                        .frame(width: 148, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HotKeyRecorderView(action: action)
                        .frame(minWidth: 120, maxWidth: .infinity)
                        .frame(height: SettingsAppearance.rowHeight)
                        .accessibilityLabel(action.label)
                }
            }
            footnote("点击输入组合键，按 Delete 清除。")
        }
    }

    // MARK: - 翻译

    private var translateSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("翻译与 AI 服务") {
                settingRow("服务商") {
                    Picker("服务商", selection: $settings.translateProvider) {
                        ForEach(TranslateProvider.allCases) { p in Text(p.label).tag(p) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                // 明示当前生效的服务：文本翻译 / OCR 翻译实际走的就是它
                HStack(spacing: 6) {
                    Image(systemName: activeProviderConfigured ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(SettingsAppearance.color(activeProviderConfigured ? SettingsAppearance.success : SettingsAppearance.warning))
                    Text(activeProviderStatus)
                        .font(SettingsAppearance.detailFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if settings.translateProvider != .deepSeek {
                    fieldRow("API 地址") {
                        TextField("https://…/v1", text: $settings.translateBaseURL)
                            .accessibilityLabel(L("API 地址"))
                    }
                    settingRow("接口格式") {
                        Picker("接口格式", selection: $settings.translateCustomFormat) {
                            ForEach(CustomAPIFormat.allCases) { f in Text(f.label).tag(f.rawValue) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                }
                fieldRow("API Key") {
                    HStack(spacing: 8) {
                        SecureField("", text: settings.translateProvider == .deepSeek ? $settings.translateAPIKey : $settings.translateCustomAPIKey)
                            .accessibilityLabel(L("API Key"))
                        Button("清除") {
                            if settings.translateProvider == .deepSeek { settings.translateAPIKey = "" } else { settings.translateCustomAPIKey = "" }
                        }
                    }
                }
                fieldRow("模型") {
                    HStack(spacing: 8) {
                        if settings.activeTranslateModels.isEmpty {
                            TextField("", text: settings.translateProvider == .deepSeek ? $settings.translateModel : $settings.translateCustomModel)
                                .accessibilityLabel(L("模型"))
                        } else {
                            Picker("模型", selection: settings.translateProvider == .deepSeek ? $settings.translateModel : $settings.translateCustomModel) {
                                ForEach(settings.activeTranslateModels, id: \.self) { m in Text(m).tag(m) }
                            }.labelsHidden()
                        }
                        Button("获取模型") { fetchModels() }
                    }
                }
                footnote("密钥保存在本机，仅发送给所选翻译服务。")
            }
            group("翻译偏好") {
                settingRow("原文语言") {
                    Picker("原文语言", selection: $settings.translateSourceLang) {
                        ForEach(TranslateLanguage.allCases) { l in Text(l.label).tag(l.rawValue) }
                    }.labelsHidden()
                }
                settingRow("译文语言") {
                    Picker("译文语言", selection: $settings.translateTargetLang) {
                        ForEach(TranslateLanguage.allCases.filter { $0 != .auto }) { l in Text(l.label).tag(l.rawValue) }
                    }.labelsHidden()
                }
                settingRow("翻译风格") {
                    Picker("翻译风格", selection: $settings.translateStyle) {
                        ForEach(TranslateStyle.allCases) { s in Text(s.label).tag(s.rawValue) }
                    }.labelsHidden()
                }
            }
        }
    }

    /// 当前生效服务的描述：翻译窗口与 OCR 都走这个
    private var activeProviderStatus: String {
        guard activeProviderConfigured else { return L("已选择服务，尚未配置 API Key") }
        if settings.translateProvider == .deepSeek {
            return String(format: L("当前使用：DeepSeek（%@）"), settings.activeTranslateModel)
        }
        let format = CustomAPIFormat(rawValue: settings.translateCustomFormat) ?? .openAIChat
        return String(format: L("当前使用：自定义 · %@（%@）"), format.label, settings.activeTranslateModel)
    }

    private var activeProviderConfigured: Bool {
        !settings.activeTranslateAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fetchModels() {
        let provider = settings.translateProvider
        let base = provider == .deepSeek ? provider.defaultBaseURL : settings.translateBaseURL
        let key = settings.activeTranslateAPIKey
        Task {
            do {
                let format = provider == .deepSeek ? .openAIChat
                    : (CustomAPIFormat(rawValue: settings.translateCustomFormat) ?? .openAIChat)
                let models = try await TranslationService.fetchModels(baseURL: base, apiKey: key, format: format)
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

    // MARK: - 图床

    private var imageHostSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("服务") {
                settingRow("图床类型") {
                    Picker("图床类型", selection: $settings.imageHostProvider) {
                        ForEach(ImageHostProvider.allCases) { p in Text(p.label).tag(p) }
                    }.labelsHidden().frame(width: pickerWidth)
                }
                switch settings.imageHostProvider {
                case .s3:
                    fieldRow("Endpoint") {
                        TextField("https://xxx.r2.cloudflarestorage.com", text: $settings.imageHostS3Endpoint)
                    }
                    settingPair(
                        fieldRow("Region") {
                            TextField("auto", text: $settings.imageHostS3Region)
                        },
                        fieldRow("存储桶") {
                            TextField("my-bucket", text: $settings.imageHostS3Bucket)
                        })
                    fieldRow("Access Key ID") {
                        TextField("", text: $settings.imageHostS3AccessKeyID)
                    }
                    fieldRow("Secret Access Key") {
                        SecureField("", text: $settings.imageHostS3SecretKey)
                    }
                    fieldRow("公开 URL 前缀") {
                        TextField("https://cdn.example.com", text: $settings.imageHostS3PublicPrefix)
                    }
                    footnote("适用于 Cloudflare R2 / MinIO / 各云厂商的 S3 兼容接口（路径风格）。Region 填 auto 或实际区域。公开 URL 前缀是拼接访问链接用的地址（如绑定的 CDN 或桶的公开域名），不是上传接口。")
                case .github:
                    fieldRow("仓库") {
                        TextField("owner/repo", text: $settings.imageHostGitHubRepo)
                    }
                    settingPair(
                        fieldRow("分支") {
                            TextField("main", text: $settings.imageHostGitHubBranch)
                        },
                        fieldRow("Token") {
                            SecureField("ghp_…", text: $settings.imageHostGitHubToken)
                        })
                    footnote("图片以 PNG 提交到仓库，链接使用 raw.githubusercontent.com 直连地址；Token 需要仓库写权限，仓库需公开可访问。")
                case .custom:
                    fieldRow("上传接口") {
                        TextField("https://api.example.com/upload", text: $settings.imageHostCustomURL)
                    }
                    fieldRow("请求头") {
                        TextField("Authorization: Bearer xxx", text: $settings.imageHostCustomHeaders)
                    }
                    settingPair(
                        fieldRow("文件字段名") {
                            TextField("file", text: $settings.imageHostCustomFileField)
                        },
                        fieldRow("URL JSON 路径") {
                            TextField("data.url", text: $settings.imageHostCustomURLPath)
                        })
                    fieldRow("URL 正则（可选）") {
                        TextField("https://\\S+", text: $settings.imageHostCustomURLRegex)
                    }
                    footnote("POST multipart 上传；请求头多个用分号分隔，格式 Key: Value。链接先按 JSON 路径取（如 data.url），取不到再按正则匹配响应文本。")
                }
            }
            group("上传") {
                fieldRow("存储路径") {
                    TextField("sakura-cap/{date}/{time}-{rand}", text: $settings.imageHostPathPattern)
                }
                footnote("占位符：{date} 日期、{time} 时间、{rand} 5 位随机数；扩展名 .png 自动追加。")
                settingRow("剪贴板格式") {
                    Picker("剪贴板格式", selection: $settings.imageHostLinkFormat) {
                        ForEach(ImageLinkFormat.allCases) { f in Text(f.label).tag(f) }
                    }.labelsHidden().frame(width: pickerWidth)
                }
                footnote("在标注编辑器右侧点「上传图床」，成功后按此格式复制到剪贴板。")
            }
        }
    }

    // MARK: - 权限

    private var permissionsSection: some View {
        Group {
            let _ = viewModel.permissionRefreshToken
            VStack(spacing: 0) {
                permissionRow(name: L("屏幕录制"), granted: PermissionCenter.screenCaptureGranted(),
                              detail: L("录制与截图"), action: { PermissionCenter.openScreenCaptureSettings() })
                rule
                permissionRow(name: L("麦克风"), state: PermissionCenter.microphoneAccess,
                              detail: L("录制麦克风声音"), action: requestMicrophonePermission)
                rule
                permissionRow(name: L("输入监控"), granted: PermissionCenter.inputMonitoringGranted(),
                              detail: L("点击标记与按键显示"), action: { PermissionCenter.openInputMonitoringSettings() })
                rule
                permissionRow(name: L("辅助功能"), granted: PermissionCenter.accessibilityGranted(),
                              detail: L("长截图自动滚动"), requestsAccess: true,
                              action: { PermissionCenter.authorizeAccessibility() })
                rule
                permissionRow(name: L("摄像头"), state: PermissionCenter.cameraAccess,
                              detail: camera.devices.isEmpty ? L("未检测到摄像头") : L("摄像头画中画"),
                              action: requestCameraPermission)
            }
        }
    }

    private func requestMicrophonePermission() {
        if PermissionCenter.microphoneAccess == .notDetermined {
            PermissionCenter.requestMicrophone { _ in
                Task { @MainActor in
                    viewModel.refreshPermissions()
                }
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
                               granted: Bool? = nil, detail: String, requestsAccess: Bool = false,
                               action: @escaping () -> Void) -> some View {
        let isGranted = state?.isAuthorized ?? (granted ?? false)
        let isPending = state == .notDetermined
        let statusText = isGranted ? L("已授权") : (isPending ? L("未请求") : L("未授权"))
        let statusColor = isGranted ? SettingsAppearance.success : (isPending ? SettingsAppearance.warning : SettingsAppearance.error)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).fontWeight(.medium)
                Spacer(minLength: 8)
                Label(statusText, systemImage: isGranted ? "checkmark.circle" : "exclamationmark.circle")
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(SettingsAppearance.color(statusColor))
            }
            HStack(alignment: .center, spacing: 12) {
                Text(detail)
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(isPending || (requestsAccess && !isGranted) ? L("授权…") : L("打开系统设置"), action: action)
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - 通用

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("输出目录") {
                Text(settings.outputDirectory?.path ?? L("未选择文件夹"))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("更改…") { viewModel.chooseOutputDirectory() }
                    Button("打开文件夹") {
                        if let directory = settings.outputDirectory { NSWorkspace.shared.open(directory) }
                    }.disabled(settings.outputDirectory == nil)
                }
            }
            group("语言") {
                settingRow("界面语言") {
                    Picker("界面语言", selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: pickerWidth)
                }
                Text("更改后请重启 Sakura-Cap，界面语言才会完全生效。")
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            group("文件命名") {
                HStack(spacing: 8) {
                    TextField("{date}-{time}-{rand}", text: $settings.fileNamePattern)
                        .accessibilityLabel(L("文件名格式"))
                    helpButton("文件名占位符", isPresented: $help.showsFileName) {
                        Text(L("占位符：{date} 日期、{time} 时间、{datetime} 日期时间、{rand} 5 位随机数。"))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(FileName.make(ext: "png"))
                        .font(SettingsAppearance.detailFont)
                        .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                        .lineLimit(1).truncationMode(.middle)
                        .help(L("文件名示例"))
                    Spacer(minLength: 0)
                    Button("恢复默认") { settings.fileNamePattern = FileName.defaultPattern }
                }
            }
            group("启动与行为") {
                Toggle("登录时启动", isOn: $settings.launchAtLogin)
                Toggle("录制结束后打开工作台", isOn: $settings.autoTrimAfterRecording)
            }
            group("截图标注") {
                Picker("截图标注方式", selection: $settings.screenshotAnnotationMode) {
                    ForEach(ScreenshotAnnotationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("独立窗口保留现有流程；原地标注会冻结屏幕，可调整选框并直接标注、复制或保存。")
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
            }
            group("录制勿扰") {
                Toggle("录制时开启勿扰模式", isOn: $settings.dndDuringRecording)
                if settings.dndDuringRecording {
                    fieldRow("开启快捷指令") {
                        TextField("", text: $settings.dndOnShortcut).accessibilityLabel(L("开启快捷指令"))
                    }
                    fieldRow("关闭快捷指令") {
                        TextField("", text: $settings.dndOffShortcut).accessibilityLabel(L("关闭快捷指令"))
                    }
                    HStack(spacing: 8) {
                        Button("打开快捷指令…") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                        }
                        helpButton("快捷指令设置教程", isPresented: $help.showsShortcuts) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L("1. 在「快捷指令」中新建快捷指令，添加「设置专注模式」动作。"))
                                Text(L("2. 选择「勿扰模式」并设为「打开」，名称与「开启快捷指令」一致。"))
                                Text(L("3. 再创建一个设为「关闭」的快捷指令，名称与「关闭快捷指令」一致。"))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sakura-Cap").font(SettingsAppearance.titleFont)
                    Text("\(L("版本")) \(AppInfo.version)")
                        .font(SettingsAppearance.detailFont)
                        .monospacedDigit()
                        .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                }
            }
            HStack(spacing: 8) {
                Button("检查更新") { UpdateChecker.check(manual: true) }
                Button("欢迎使用…") { OnboardingWindowController.shared.show() }
            }
            group("项目链接") {
                linkRow(L("GitHub 仓库"), AppInfo.repository)
                linkRow(L("发布版本"), AppInfo.repository.appendingPathComponent("releases"))
                linkRow(L("开发文档"), AppInfo.repository.appendingPathComponent("blob/main/docs/DEVELOPMENT.md"))
            }
            Text("© 2026 Sakura · Sakura最可爱了")
                .font(SettingsAppearance.detailFont)
                .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
        }
    }

    private func linkRow(_ title: String, _ url: URL) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button { NSWorkspace.shared.open(url) } label: {
                Image(systemName: "arrow.up.right")
            }
            .accessibilityLabel(String(format: L("打开%@"), title))
            .help(url.absoluteString)
        }
    }

    // MARK: - 通用组件

    private var footer: some View { EmptyView() }

    private var rule: some View {
        Rectangle()
            .fill(SettingsAppearance.color(SettingsAppearance.separator))
            .frame(height: SettingsAppearance.borderWidth)
            .accessibilityHidden(true)
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(SettingsAppearance.bodyFont.weight(.semibold))
            rule
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: labelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: SettingsAppearance.rowHeight)
    }

    private func fieldRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        settingRow(title, content: content)
    }

    private func sliderRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String, width: CGFloat) -> some View {
        settingRow(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step).accessibilityLabel(Text(title))
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                    .frame(width: width, alignment: .trailing)
            }
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(SettingsAppearance.detailFont)
            .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func helpButton<Content: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button { isPresented.wrappedValue.toggle() } label: {
            Image(systemName: "questionmark.circle")
        }
        .accessibilityLabel(L(title))
        .help(L(title))
        .popover(isPresented: isPresented) {
            content()
                .font(SettingsAppearance.detailFont)
                .foregroundStyle(SettingsAppearance.color(SettingsAppearance.text))
                .padding(16)
                .frame(width: 320, alignment: .leading)
                .background(SettingsAppearance.color(SettingsAppearance.canvas))
        }
    }
}
