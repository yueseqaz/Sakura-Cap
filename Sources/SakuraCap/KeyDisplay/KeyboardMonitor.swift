import AppKit
import CoreGraphics

/// 全局键盘监听：CGEventTap listen-only（只听不改，不消费事件）。
/// 需要「输入监控」权限；与 ClickMonitor 同一权限，但各自独立的 tap。
final class KeyboardMonitor {
    /// 回调在主线程；label 形如 "⌘⇧R"、"A"、"Space"、""（无内容）
    var onKey: (@MainActor (String) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    @discardableResult
    func start() -> Bool {
        if eventTap != nil {
            isRunning = true
            return true
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: keyboardTapCallback, userInfo: context),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Log.indicator.error("创建键盘 CGEventTap 失败（通常为缺少「输入监控」权限）")
            isRunning = false
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        isRunning = true
        Log.indicator.info("键盘监听已启动")
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    /// 事件回调挂在主 RunLoop 上，此处必然在主线程
    fileprivate func dispatch(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let label = KeyLabel.describe(type: type, event: event)
        MainActor.assumeIsolated { onKey?(label) }
    }
}

private func keyboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue().dispatch(type: type, event: event)
    }
    return Unmanaged.passUnretained(event) // listen-only：原样放行
}

/// keyCode / 修饰键 → 人类可读文本（跟随当前键盘布局，非美式布局也能取到正确字符）
enum KeyLabel {
    static func describe(type: CGEventType, event: CGEvent) -> String {
        let mods = modifiers(event.flags)
        if type == .flagsChanged {
            return mods
        }
        // 过滤长按自动重复
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return "" }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        var key = ""
        if let ns = NSEvent(cgEvent: event), let chars = ns.charactersIgnoringModifiers,
           let scalar = chars.unicodeScalars.first {
            if scalar.value == 0x20 {
                key = "Space"
            } else if scalar.value >= 0x20 && scalar.value != 0x7F {
                key = chars.count == 1 ? chars.uppercased() : chars
            }
        }
        if key.isEmpty { key = specialLabel(keyCode) }
        return mods + key
    }

    static func modifiers(_ flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s
    }

    private static func specialLabel(_ code: Int) -> String {
        switch code {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 57: return "⇪"
        case 76: return "⌤"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 119: return "↘"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return ""
        }
    }
}
