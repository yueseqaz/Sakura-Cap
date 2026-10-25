import Foundation
import CoreGraphics
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

/// 全部设置项，UserDefaults 持久化。更改即时生效并写盘。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private struct Keys {
        static let outputDir = "outputDirectory"
        static let mode = "captureMode"
        static let displayID = "selectedDisplayID"
        static let allDisplays = "allDisplaysParallel"
        static let region = "lastRegionData"
        static let systemAudio = "recordSystemAudio"
        static let microphone = "recordMicrophone"
        static let microphoneDevice = "microphoneDeviceID"
        static let indicator = "clickIndicatorEnabled"
        static let indicatorColor = "indicatorColorRGBA"
        static let indicatorSize = "indicatorSize"
        static let indicatorDuration = "indicatorDuration"
        static let indicatorRight = "indicatorIncludeRightClick"
        static let keyDisplay = "keyDisplayEnabled"
        static let sound = "soundEnabled"
        static let cameraPiP = "cameraPiPEnabled"
        static let cameraDevice = "cameraPiPDeviceID"
        static let cameraSize = "cameraPiPSize"
        static let cameraMirror = "cameraPiPMirror"
        static let cameraCorner = "cameraPiPCorner"
        static let outputResolution = "outputResolution"
        static let dnd = "dndDuringRecording"
        static let dndOn = "dndOnShortcut"
        static let dndOff = "dndOffShortcut"
        static let autoTrim = "autoTrimAfterRecording"
        static let countdown = "countdownEnabled"
        static let codec = "videoCodec"
        static let quality = "videoQuality"
        static let customBitrate = "customBitrateMbps"
        static let colorSpace = "colorSpace"
        static let showCursor = "showCursor"
        static let fps = "frameRate"
        static let fpsOverlay = "showFPSOverlay"
        static let hotKeys = "hotKeys"
        static let onboarding = "hasCompletedOnboarding"
        static let fileNamePattern = "fileNamePattern"
        static let translateProvider = "translateProvider"
        static let translateCustomFormat = "translateCustomFormat"
        static let translateBaseURL = "translateBaseURL"
        static let translateModel = "translateModel"
        static let translateModels = "translateModels"
        static let translateCustomModel = "translateCustomModel"
        static let translateCustomModels = "translateCustomModels"
        static let translateStyle = "translateStyle"
        static let translateAPIKey = "translateAPIKey"
        static let translateCustomAPIKey = "translateCustomAPIKey"
        static let translateAPIKeyObf = "translateAPIKey.b64"
        static let translateCustomAPIKeyObf = "translateCustomAPIKey.b64"
        static let translateSourceLang = "translateSourceLang"
        static let translateTargetLang = "translateTargetLang"
        // 图床
        static let imageHostProvider = "imageHostProvider"
        static let imageHostLinkFormat = "imageHostLinkFormat"
        static let imageHostPathPattern = "imageHostPathPattern"
        static let imageHostS3Endpoint = "imageHostS3Endpoint"
        static let imageHostS3Region = "imageHostS3Region"
        static let imageHostS3Bucket = "imageHostS3Bucket"
        static let imageHostS3AccessKeyID = "imageHostS3AccessKeyID"
        static let imageHostS3SecretKeyObf = "imageHostS3SecretKey.b64"
        static let imageHostS3PublicPrefix = "imageHostS3PublicPrefix"
        static let imageHostGitHubRepo = "imageHostGitHubRepo"
        static let imageHostGitHubBranch = "imageHostGitHubBranch"
        static let imageHostGitHubTokenObf = "imageHostGitHubToken.b64"
        static let imageHostCustomURL = "imageHostCustomURL"
        static let imageHostCustomHeaders = "imageHostCustomHeaders"
        static let imageHostCustomFileField = "imageHostCustomFileField"
        static let imageHostCustomURLPath = "imageHostCustomURLPath"
        static let imageHostCustomURLRegex = "imageHostCustomURLRegex"
    }

    private let d = UserDefaults.standard

    @Published var outputDirectory: URL? { didSet { d.set(outputDirectory?.path, forKey: Keys.outputDir) } }
    @Published var captureMode: CaptureMode = .display { didSet { d.set(captureMode.rawValue, forKey: Keys.mode) } }
    @Published var selectedDisplayID: UInt32 = 0 { didSet { d.set(Int(selectedDisplayID), forKey: Keys.displayID) } }
    @Published var allDisplaysParallel = false { didSet { d.set(allDisplaysParallel, forKey: Keys.allDisplays) } }
    @Published private(set) var lastRegionData: Data? { didSet { d.set(lastRegionData, forKey: Keys.region) } }

    @Published var recordSystemAudio = true { didSet { d.set(recordSystemAudio, forKey: Keys.systemAudio) } }
    @Published var recordMicrophone = false { didSet { d.set(recordMicrophone, forKey: Keys.microphone) } }
    @Published var microphoneDeviceID = "" { didSet { d.set(microphoneDeviceID, forKey: Keys.microphoneDevice) } }

    // 点击指示：默认关闭（产品确认）
    @Published var clickIndicatorEnabled = false { didSet { d.set(clickIndicatorEnabled, forKey: Keys.indicator) } }
    @Published var indicatorColorRGBA: [Double] = [0.93, 0.25, 0.38, 0.95] { didSet { d.set(indicatorColorRGBA, forKey: Keys.indicatorColor) } }
    @Published var indicatorSize: Double = 56 { didSet { d.set(indicatorSize, forKey: Keys.indicatorSize) } }
    @Published var indicatorDuration: Double = 0.8 { didSet { d.set(indicatorDuration, forKey: Keys.indicatorDuration) } }
    @Published var indicatorIncludeRightClick = false { didSet { d.set(indicatorIncludeRightClick, forKey: Keys.indicatorRight) } }

    // 键盘按键显示（默认关闭）
    @Published var keyDisplayEnabled = false { didSet { d.set(keyDisplayEnabled, forKey: Keys.keyDisplay) } }
    // 录制开始/结束提示音（默认开启）
    @Published var soundEnabled = true { didSet { d.set(soundEnabled, forKey: Keys.sound) } }

    // 摄像头画中画（默认关闭）
    @Published var cameraPiPEnabled = false { didSet { d.set(cameraPiPEnabled, forKey: Keys.cameraPiP) } }
    @Published var cameraPiPDeviceID = "" { didSet { d.set(cameraPiPDeviceID, forKey: Keys.cameraDevice) } }
    @Published var cameraPiPSize: Double = 18 { didSet { d.set(cameraPiPSize, forKey: Keys.cameraSize) } }
    @Published var cameraPiPMirror = true { didSet { d.set(cameraPiPMirror, forKey: Keys.cameraMirror) } }
    @Published var cameraPiPCorner: PiPCorner = .bottomRight { didSet { d.set(cameraPiPCorner.rawValue, forKey: Keys.cameraCorner) } }

    // 输出分辨率（按需缩小；默认原始）
    @Published var outputResolution: OutputResolution = .native { didSet { d.set(outputResolution.rawValue, forKey: Keys.outputResolution) } }

    // 录屏时开启勿扰（通过「快捷指令」切换专注模式）
    @Published var dndDuringRecording = false { didSet { d.set(dndDuringRecording, forKey: Keys.dnd) } }
    @Published var dndOnShortcut = "Sakura-Cap 开启勿扰" { didSet { d.set(dndOnShortcut, forKey: Keys.dndOn) } }
    @Published var dndOffShortcut = "Sakura-Cap 关闭勿扰" { didSet { d.set(dndOffShortcut, forKey: Keys.dndOff) } }

    // 录制完成后自动打开裁剪页
    @Published var autoTrimAfterRecording = true { didSet { d.set(autoTrimAfterRecording, forKey: Keys.autoTrim) } }

    @Published var countdownEnabled = true { didSet { d.set(countdownEnabled, forKey: Keys.countdown) } }
    @Published var codec: VideoCodec = .h264 { didSet { d.set(codec.rawValue, forKey: Keys.codec) } }
    @Published var quality: VideoQuality = .high { didSet { d.set(quality.rawValue, forKey: Keys.quality) } }
    @Published var customBitrateMbps: Double = 20 { didSet { d.set(customBitrateMbps, forKey: Keys.customBitrate) } }
    @Published var colorSpace: ColorSpaceOption = .sRGB { didSet { d.set(colorSpace.rawValue, forKey: Keys.colorSpace) } }
    @Published var showCursor = true { didSet { d.set(showCursor, forKey: Keys.showCursor) } }
    @Published var fps: FPSOption = .fps30 { didSet { d.set(fps.rawValue, forKey: Keys.fps) } }
    @Published var showFPSOverlay = false { didSet { d.set(showFPSOverlay, forKey: Keys.fpsOverlay) } }

    // 是否已看过首次引导（含欢迎页）
    @Published var hasCompletedOnboarding = false { didSet { d.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }

    // 自动命名模板（截图 / 录屏 / 截帧）
    @Published var fileNamePattern = FileName.defaultPattern { didSet { d.set(fileNamePattern, forKey: Keys.fileNamePattern) } }

    // 翻译
    @Published var translateProvider: TranslateProvider = .deepSeek { didSet { d.set(translateProvider.rawValue, forKey: Keys.translateProvider) } }
    /// 自定义服务商的接口格式
    @Published var translateCustomFormat: String = CustomAPIFormat.openAIChat.rawValue { didSet { d.set(translateCustomFormat, forKey: Keys.translateCustomFormat) } }
    @Published var translateBaseURL = "" { didSet { d.set(translateBaseURL, forKey: Keys.translateBaseURL) } }
    @Published var translateModel = "deepseek-chat" { didSet { d.set(translateModel, forKey: Keys.translateModel) } }
    @Published var translateModels: [String] = [] { didSet { d.set(translateModels, forKey: Keys.translateModels) } }
    @Published var translateCustomModel = "" { didSet { d.set(translateCustomModel, forKey: Keys.translateCustomModel) } }
    @Published var translateCustomModels: [String] = [] { didSet { d.set(translateCustomModels, forKey: Keys.translateCustomModels) } }
    @Published var translateStyle = TranslateStyle.natural.rawValue { didSet { d.set(translateStyle, forKey: Keys.translateStyle) } }
    // 敏感值（API Key）：UserDefaults + base64 脱敏存储。
    // 脱敏 ≠ 加密：防的是备份/偏好文件里肉眼直接读到明文，不防有意的本地读取。
    // 2.4.0–2.4.1 曾用 Keychain，因 ad-hoc 签名每次构建变化导致频繁弹授权框而移除；
    // Keychain 里的旧值不迁移（受影响用户重填一次即可）。
    @Published var translateAPIKey = "" { didSet { storeObfuscated(translateAPIKey, key: Keys.translateAPIKeyObf) } }
    @Published var translateCustomAPIKey = "" { didSet { storeObfuscated(translateCustomAPIKey, key: Keys.translateCustomAPIKeyObf) } }
    @Published var translateSourceLang = TranslateLanguage.auto.rawValue { didSet { d.set(translateSourceLang, forKey: Keys.translateSourceLang) } }
    @Published var translateTargetLang = TranslateLanguage.zhHans.rawValue { didSet { d.set(translateTargetLang, forKey: Keys.translateTargetLang) } }

    // 图床（密钥与 Token 同 API Key 一样 base64 脱敏存 UserDefaults）
    @Published var imageHostProvider: ImageHostProvider = .s3 { didSet { d.set(imageHostProvider.rawValue, forKey: Keys.imageHostProvider) } }
    @Published var imageHostLinkFormat: ImageLinkFormat = .url { didSet { d.set(imageHostLinkFormat.rawValue, forKey: Keys.imageHostLinkFormat) } }
    @Published var imageHostPathPattern = ImageHost.defaultPathPattern { didSet { d.set(imageHostPathPattern, forKey: Keys.imageHostPathPattern) } }
    @Published var imageHostS3Endpoint = "" { didSet { d.set(imageHostS3Endpoint, forKey: Keys.imageHostS3Endpoint) } }
    @Published var imageHostS3Region = "auto" { didSet { d.set(imageHostS3Region, forKey: Keys.imageHostS3Region) } }
    @Published var imageHostS3Bucket = "" { didSet { d.set(imageHostS3Bucket, forKey: Keys.imageHostS3Bucket) } }
    @Published var imageHostS3AccessKeyID = "" { didSet { d.set(imageHostS3AccessKeyID, forKey: Keys.imageHostS3AccessKeyID) } }
    @Published var imageHostS3SecretKey = "" { didSet { storeObfuscated(imageHostS3SecretKey, key: Keys.imageHostS3SecretKeyObf) } }
    @Published var imageHostS3PublicPrefix = "" { didSet { d.set(imageHostS3PublicPrefix, forKey: Keys.imageHostS3PublicPrefix) } }
    @Published var imageHostGitHubRepo = "" { didSet { d.set(imageHostGitHubRepo, forKey: Keys.imageHostGitHubRepo) } }
    @Published var imageHostGitHubBranch = "main" { didSet { d.set(imageHostGitHubBranch, forKey: Keys.imageHostGitHubBranch) } }
    @Published var imageHostGitHubToken = "" { didSet { storeObfuscated(imageHostGitHubToken, key: Keys.imageHostGitHubTokenObf) } }
    @Published var imageHostCustomURL = "" { didSet { d.set(imageHostCustomURL, forKey: Keys.imageHostCustomURL) } }
    @Published var imageHostCustomHeaders = "" { didSet { d.set(imageHostCustomHeaders, forKey: Keys.imageHostCustomHeaders) } }
    @Published var imageHostCustomFileField = "file" { didSet { d.set(imageHostCustomFileField, forKey: Keys.imageHostCustomFileField) } }
    @Published var imageHostCustomURLPath = "data.url" { didSet { d.set(imageHostCustomURLPath, forKey: Keys.imageHostCustomURLPath) } }
    @Published var imageHostCustomURLRegex = "" { didSet { d.set(imageHostCustomURLRegex, forKey: Keys.imageHostCustomURLRegex) } }

    /// 开机自启（登录项）。真实状态以系统 SMAppService 为准。
    @Published var launchAtLogin: Bool = false { didSet { applyLaunchAtLogin() } }
    private var applyingLaunchAtLogin = false

    // 全局快捷键（默认全部为空，用户自行设置）
    @Published var hotKeys: [HotKeyAction: HotKeyCombo] = [:] {
        didSet {
            let raw = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(raw) { d.set(data, forKey: Keys.hotKeys) }
        }
    }

    private init() {
        outputDirectory = d.string(forKey: Keys.outputDir).map { URL(fileURLWithPath: $0) }
        if let raw = d.string(forKey: Keys.mode), let mode = CaptureMode(rawValue: raw) { captureMode = mode }
        selectedDisplayID = UInt32(d.integer(forKey: Keys.displayID))
        allDisplaysParallel = d.bool(forKey: Keys.allDisplays)
        lastRegionData = d.data(forKey: Keys.region)
        recordSystemAudio = d.object(forKey: Keys.systemAudio) == nil ? true : d.bool(forKey: Keys.systemAudio)
        recordMicrophone = d.bool(forKey: Keys.microphone)
        microphoneDeviceID = d.string(forKey: Keys.microphoneDevice) ?? ""
        clickIndicatorEnabled = d.bool(forKey: Keys.indicator)
        if let rgba = d.array(forKey: Keys.indicatorColor) as? [Double], rgba.count == 4 { indicatorColorRGBA = rgba }
        if d.object(forKey: Keys.indicatorSize) != nil { indicatorSize = d.double(forKey: Keys.indicatorSize) }
        if d.object(forKey: Keys.indicatorDuration) != nil { indicatorDuration = d.double(forKey: Keys.indicatorDuration) }
        indicatorIncludeRightClick = d.bool(forKey: Keys.indicatorRight)
        keyDisplayEnabled = d.bool(forKey: Keys.keyDisplay)
        soundEnabled = d.object(forKey: Keys.sound) == nil ? true : d.bool(forKey: Keys.sound)
        cameraPiPEnabled = d.bool(forKey: Keys.cameraPiP)
        cameraPiPDeviceID = d.string(forKey: Keys.cameraDevice) ?? ""
        if d.object(forKey: Keys.cameraSize) != nil { cameraPiPSize = d.double(forKey: Keys.cameraSize) }
        cameraPiPMirror = d.object(forKey: Keys.cameraMirror) == nil ? true : d.bool(forKey: Keys.cameraMirror)
        if let raw = d.string(forKey: Keys.cameraCorner), let corner = PiPCorner(rawValue: raw) { cameraPiPCorner = corner }
        if let raw = d.string(forKey: Keys.outputResolution), let r = OutputResolution(rawValue: raw) { outputResolution = r }
        dndDuringRecording = d.bool(forKey: Keys.dnd)
        if let s = d.string(forKey: Keys.dndOn) { dndOnShortcut = s }
        if let s = d.string(forKey: Keys.dndOff) { dndOffShortcut = s }
        autoTrimAfterRecording = d.object(forKey: Keys.autoTrim) == nil ? true : d.bool(forKey: Keys.autoTrim)
        countdownEnabled = d.object(forKey: Keys.countdown) == nil ? true : d.bool(forKey: Keys.countdown)
        if let raw = d.string(forKey: Keys.codec), let c = VideoCodec(rawValue: raw) { codec = c }
        if let raw = d.string(forKey: Keys.quality), let q = VideoQuality(rawValue: raw) { quality = q }
        if d.object(forKey: Keys.customBitrate) != nil { customBitrateMbps = d.double(forKey: Keys.customBitrate) }
        if let raw = d.string(forKey: Keys.colorSpace), let cs = ColorSpaceOption(rawValue: raw) { colorSpace = cs }
        if d.object(forKey: Keys.showCursor) != nil { showCursor = d.bool(forKey: Keys.showCursor) }
        if let f = FPSOption(rawValue: d.integer(forKey: Keys.fps)) { fps = f }
        showFPSOverlay = d.bool(forKey: Keys.fpsOverlay)
        hasCompletedOnboarding = d.bool(forKey: Keys.onboarding)
        if let s = d.string(forKey: Keys.fileNamePattern) { fileNamePattern = s }
        if let raw = d.string(forKey: Keys.translateProvider), let p = TranslateProvider(rawValue: raw) { translateProvider = p }
        if let raw = d.string(forKey: Keys.translateCustomFormat), let f = CustomAPIFormat(rawValue: raw) { translateCustomFormat = raw }
        translateBaseURL = d.string(forKey: Keys.translateBaseURL) ?? ""
        translateModel = d.string(forKey: Keys.translateModel) ?? "deepseek-chat"
        translateModels = d.stringArray(forKey: Keys.translateModels) ?? []
        translateCustomModel = d.string(forKey: Keys.translateCustomModel) ?? ""
        translateCustomModels = d.stringArray(forKey: Keys.translateCustomModels) ?? []
        if let s = d.string(forKey: Keys.translateStyle) { translateStyle = s }
        translateAPIKey = loadObfuscated(legacyKey: Keys.translateAPIKey, obfKey: Keys.translateAPIKeyObf)
        translateCustomAPIKey = loadObfuscated(legacyKey: Keys.translateCustomAPIKey, obfKey: Keys.translateCustomAPIKeyObf)
        if let s = d.string(forKey: Keys.translateSourceLang) { translateSourceLang = s }
        if let s = d.string(forKey: Keys.translateTargetLang) { translateTargetLang = s }
        // 图床
        if let raw = d.string(forKey: Keys.imageHostProvider), let p = ImageHostProvider(rawValue: raw) { imageHostProvider = p }
        if let raw = d.string(forKey: Keys.imageHostLinkFormat), let f = ImageLinkFormat(rawValue: raw) { imageHostLinkFormat = f }
        if let s = d.string(forKey: Keys.imageHostPathPattern), !s.isEmpty { imageHostPathPattern = s }
        imageHostS3Endpoint = d.string(forKey: Keys.imageHostS3Endpoint) ?? ""
        if let s = d.string(forKey: Keys.imageHostS3Region) { imageHostS3Region = s }
        imageHostS3Bucket = d.string(forKey: Keys.imageHostS3Bucket) ?? ""
        imageHostS3AccessKeyID = d.string(forKey: Keys.imageHostS3AccessKeyID) ?? ""
        imageHostS3SecretKey = loadObfuscated(legacyKey: "", obfKey: Keys.imageHostS3SecretKeyObf)
        imageHostS3PublicPrefix = d.string(forKey: Keys.imageHostS3PublicPrefix) ?? ""
        imageHostGitHubRepo = d.string(forKey: Keys.imageHostGitHubRepo) ?? ""
        imageHostGitHubBranch = d.string(forKey: Keys.imageHostGitHubBranch) ?? "main"
        imageHostGitHubToken = loadObfuscated(legacyKey: "", obfKey: Keys.imageHostGitHubTokenObf)
        imageHostCustomURL = d.string(forKey: Keys.imageHostCustomURL) ?? ""
        imageHostCustomHeaders = d.string(forKey: Keys.imageHostCustomHeaders) ?? ""
        imageHostCustomFileField = d.string(forKey: Keys.imageHostCustomFileField) ?? "file"
        imageHostCustomURLPath = d.string(forKey: Keys.imageHostCustomURLPath) ?? "data.url"
        imageHostCustomURLRegex = d.string(forKey: Keys.imageHostCustomURLRegex) ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let data = d.data(forKey: Keys.hotKeys),
           let raw = try? JSONDecoder().decode([String: HotKeyCombo].self, from: data) {
            hotKeys = Dictionary(uniqueKeysWithValues: raw.compactMap { key, combo in
                HotKeyAction(rawValue: key).map { ($0, combo) }
            })
        }
    }

    // MARK: - 敏感值存取（UserDefaults + base64 脱敏）

    /// 写入：空值删键；非空值 base64 编码后存（与旧明文同域不同键，避免误判）
    private func storeObfuscated(_ value: String, key: String) {
        if value.isEmpty {
            d.removeObject(forKey: key)
        } else {
            d.set(Data(value.utf8).base64EncodedString(), forKey: key)
        }
    }

    /// 读取：优先脱敏键（base64 解码）；没有则读旧明文键（≤2.3.0）就地迁移并删除明文。
    private func loadObfuscated(legacyKey: String, obfKey: String) -> String {
        if let b64 = d.string(forKey: obfKey),
           let data = Data(base64Encoded: b64),
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        if let legacy = d.string(forKey: legacyKey), !legacy.isEmpty {
            storeObfuscated(legacy, key: obfKey)
            d.removeObject(forKey: legacyKey)
            Log.app.notice("已把明文 API Key 迁移为脱敏存储: \(legacyKey, privacy: .public)")
            return legacy
        }
        return ""
    }

    // MARK: - 开机自启

    private func applyLaunchAtLogin() {
        guard !applyingLaunchAtLogin else { return }
        let desired = launchAtLogin
        do {
            if desired {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            Log.app.error("设置开机自启失败: \(error.localizedDescription, privacy: .public)")
            // 回滚开关到系统真实状态，避免 UI 与实际不符
            applyingLaunchAtLogin = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            applyingLaunchAtLogin = false
        }
    }

    // MARK: - 翻译

    var translationConfig: TranslationConfig {
        TranslationConfig(
            baseURL: translateProvider == .deepSeek ? translateProvider.defaultBaseURL : translateBaseURL,
            apiKey: activeTranslateAPIKey,
            model: activeTranslateModel,
            source: TranslateLanguage(rawValue: translateSourceLang) ?? .auto,
            target: TranslateLanguage(rawValue: translateTargetLang) ?? .zhHans,
            style: TranslateStyle(rawValue: translateStyle) ?? .natural,
            format: translateProvider == .deepSeek ? .openAIChat
                : (CustomAPIFormat(rawValue: translateCustomFormat) ?? .openAIChat)
        )
    }

    /// 当前服务商对应的 API Key（DeepSeek 与自定义各自独立）
    var activeTranslateAPIKey: String {
        translateProvider == .deepSeek ? translateAPIKey : translateCustomAPIKey
    }

    /// 当前服务商对应的模型名
    var activeTranslateModel: String {
        let model = translateProvider == .deepSeek ? translateModel : translateCustomModel
        let trimmed = model.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? translateProvider.defaultModel : trimmed
    }

    /// 当前服务商拉取到的模型列表
    var activeTranslateModels: [String] {
        translateProvider == .deepSeek ? translateModels : translateCustomModels
    }

    // MARK: - 区域

    var lastRegion: RegionSelection? {
        lastRegionData.flatMap { try? JSONDecoder().decode(RegionSelection.self, from: $0) }
    }

    func updateRegion(_ region: RegionSelection?) {
        if let region, let data = try? JSONEncoder().encode(region) {
            lastRegionData = data
        } else {
            lastRegionData = nil
        }
    }

    // MARK: - 指示器颜色

    var indicatorColor: Color {
        get {
            let c = indicatorColorRGBA
            return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3])
        }
        set {
            if let n = NSColor(newValue).usingColorSpace(.sRGB) {
                indicatorColorRGBA = [Double(n.redComponent), Double(n.greenComponent),
                                      Double(n.blueComponent), Double(n.alphaComponent)]
            }
        }
    }

    // MARK: - 快捷键

    func updateHotKey(_ action: HotKeyAction, combo: HotKeyCombo?) {
        if let combo { hotKeys[action] = combo } else { hotKeys.removeValue(forKey: action) }
    }
}
