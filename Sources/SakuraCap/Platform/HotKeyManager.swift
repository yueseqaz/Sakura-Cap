import AppKit
import Carbon.HIToolbox

struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

/// 全局快捷键：Carbon RegisterEventHotKey（零第三方依赖，LSUIElement 下可用）。
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
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

    func register(_ combo: HotKeyCombo) {
        installHandlerIfNeeded()
        unregister()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534B_4350) /* 'SKCP' */, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
            Log.app.info("全局快捷键已注册: \(combo.display, privacy: .public)")
        } else {
            Log.app.error("全局快捷键注册失败（可能被占用）: OSStatus \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                HotKeyManager.shared.onToggle?()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, nil)
    }
}
