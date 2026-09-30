import AppKit
import Carbon.HIToolbox

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

/// 可配置全局快捷键的动作（默认全部为空，由用户自行设置）
enum HotKeyAction: String, CaseIterable, Identifiable {
    case recordFull
    case recordWindow
    case recordRegion
    case shotFull
    case shotRegion
    case ocr
    case scrolling

    var id: String { rawValue }
    var label: String {
        switch self {
        case .recordFull: return L("全屏录制")
        case .recordWindow: return L("窗口录制")
        case .recordRegion: return L("区域录制")
        case .shotFull: return L("全屏截图")
        case .shotRegion: return L("区域截图")
        case .ocr: return L("识别文字（OCR）")
        case .scrolling: return L("滚动截屏")
        }
    }
}

/// 全局快捷键：Carbon RegisterEventHotKey（零第三方依赖，LSUIElement 下可用）。
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func modifiersDisplay(_ m: UInt32) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey) != 0 { s += "⌥" }
        if m & UInt32(shiftKey) != 0 { s += "⇧" }
        if m & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    /// 重新注册全部快捷键（先清空旧的）
    func register(_ combos: [(action: HotKeyAction, combo: HotKeyCombo)], handler: @escaping (HotKeyAction) -> Void) {
        installHandlerIfNeeded()
        unregisterAll()
        for entry in combos {
            let id = nextID
            nextID += 1
            handlers[id] = { handler(entry.action) }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x534B_4350) /* 'SKCP' */, id: id)
            let status = RegisterEventHotKey(entry.combo.keyCode, entry.combo.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                refs[id] = ref
                Log.app.info("快捷键已注册: \(entry.action.rawValue, privacy: .public) \(entry.combo.display, privacy: .public)")
            } else {
                Log.app.error("快捷键注册失败（可能被占用）: \(entry.action.rawValue, privacy: .public) OSStatus \(status)")
            }
        }
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func dispatch(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyManager.shared.dispatch(id) }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, nil)
    }
}
