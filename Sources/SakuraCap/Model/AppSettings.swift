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
        static let countdown = "countdownEnabled"
        static let codec = "videoCodec"
        static let quality = "videoQuality"
        static let customBitrate = "customBitrateMbps"
        static let colorSpace = "colorSpace"
        static let showCursor = "showCursor"
        static let fps = "frameRate"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyMods = "hotKeyModifiers"
        static let hotKeyDisplay = "hotKeyDisplay"
    }

    private let d = UserDefaults.standard

    @Published var outputDirectory: URL? { didSet { d.set(outputDirectory?.path, forKey: Keys.outputDir) } }
    @Published var captureMode: CaptureMode = .display { didSet { d.set(captureMode.rawValue, forKey: Keys.mode) } }
    @Published var selectedDisplayID: UInt32 = 0 { didSet { d.set(Int(selectedDisplayID), forKey: Keys.displayID) } }
    @Published var allDisplaysParallel = false { didSet { d.set(allDisplaysParallel, forKey: Keys.allDisplays) } }
    @Published private(set) var lastRegionData: Data? { didSet { d.set(lastRegionData, forKey: Keys.region) } }

    @Published var recordSystemAudio = true { didSet { d.set(recordSystemAudio, forKey: Keys.systemAudio) } }
    @Published var recordMicrophone = false { didSet { d.set(recordMicrophone, forKey: Keys.microphone) } }

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

    @Published var countdownEnabled = true { didSet { d.set(countdownEnabled, forKey: Keys.countdown) } }
    @Published var codec: VideoCodec = .h264 { didSet { d.set(codec.rawValue, forKey: Keys.codec) } }
    @Published var quality: VideoQuality = .high { didSet { d.set(quality.rawValue, forKey: Keys.quality) } }
    @Published var customBitrateMbps: Double = 20 { didSet { d.set(customBitrateMbps, forKey: Keys.customBitrate) } }
    @Published var colorSpace: ColorSpaceOption = .sRGB { didSet { d.set(colorSpace.rawValue, forKey: Keys.colorSpace) } }
    @Published var showCursor = true { didSet { d.set(showCursor, forKey: Keys.showCursor) } }
    @Published var fps: FPSOption = .fps30 { didSet { d.set(fps.rawValue, forKey: Keys.fps) } }

    /// 开机自启（登录项）。真实状态以系统 SMAppService 为准。
    @Published var launchAtLogin: Bool = false { didSet { applyLaunchAtLogin() } }
    private var applyingLaunchAtLogin = false

    // 全局快捷键，默认 ⌘⇧R
    @Published var hotKeyCode: Int = Int(kVK_ANSI_R) { didSet { d.set(hotKeyCode, forKey: Keys.hotKeyCode) } }
    @Published var hotKeyModifiers: Int = Int(cmdKey | shiftKey) { didSet { d.set(hotKeyModifiers, forKey: Keys.hotKeyMods) } }
    @Published var hotKeyDisplay: String = "⌘⇧R" { didSet { d.set(hotKeyDisplay, forKey: Keys.hotKeyDisplay) } }

    private init() {
        outputDirectory = d.string(forKey: Keys.outputDir).map { URL(fileURLWithPath: $0) }
        if let raw = d.string(forKey: Keys.mode), let mode = CaptureMode(rawValue: raw) { captureMode = mode }
        selectedDisplayID = UInt32(d.integer(forKey: Keys.displayID))
        allDisplaysParallel = d.bool(forKey: Keys.allDisplays)
        lastRegionData = d.data(forKey: Keys.region)
        recordSystemAudio = d.object(forKey: Keys.systemAudio) == nil ? true : d.bool(forKey: Keys.systemAudio)
        recordMicrophone = d.bool(forKey: Keys.microphone)
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
        countdownEnabled = d.object(forKey: Keys.countdown) == nil ? true : d.bool(forKey: Keys.countdown)
        if let raw = d.string(forKey: Keys.codec), let c = VideoCodec(rawValue: raw) { codec = c }
        if let raw = d.string(forKey: Keys.quality), let q = VideoQuality(rawValue: raw) { quality = q }
        if d.object(forKey: Keys.customBitrate) != nil { customBitrateMbps = d.double(forKey: Keys.customBitrate) }
        if let raw = d.string(forKey: Keys.colorSpace), let cs = ColorSpaceOption(rawValue: raw) { colorSpace = cs }
        if d.object(forKey: Keys.showCursor) != nil { showCursor = d.bool(forKey: Keys.showCursor) }
        if let f = FPSOption(rawValue: d.integer(forKey: Keys.fps)) { fps = f }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if d.object(forKey: Keys.hotKeyCode) != nil { hotKeyCode = d.integer(forKey: Keys.hotKeyCode) }
        if d.object(forKey: Keys.hotKeyMods) != nil { hotKeyModifiers = d.integer(forKey: Keys.hotKeyMods) }
        if let display = d.string(forKey: Keys.hotKeyDisplay) { hotKeyDisplay = display }
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

    var hotKeyCombo: HotKeyCombo {
        HotKeyCombo(keyCode: UInt32(hotKeyCode), modifiers: UInt32(hotKeyModifiers), display: hotKeyDisplay)
    }

    func updateHotKey(_ combo: HotKeyCombo) {
        hotKeyCode = Int(combo.keyCode)
        hotKeyModifiers = Int(combo.modifiers)
        hotKeyDisplay = combo.display
    }
}
