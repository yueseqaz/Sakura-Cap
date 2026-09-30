import AppKit
import SwiftUI

/// 快捷键录制控件：点击获得焦点，按下「修饰键+按键」即注册为新的全局快捷键；Delete 清除。
struct HotKeyRecorderView: NSViewRepresentable {
    let action: HotKeyAction

    func makeNSView(context: Context) -> HotKeyCaptureView {
        let view = HotKeyCaptureView()
        view.action = action
        view.onCombo = { combo in
            AppSettings.shared.updateHotKey(action, combo: combo)
            view.needsDisplay = true
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyCaptureView, context: Context) {
        nsView.needsDisplay = true
    }
}

final class HotKeyCaptureView: NSView {
    var action: HotKeyAction = .recordFull
    var onCombo: ((HotKeyCombo?) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Delete / Backspace：清除该快捷键
        if event.keyCode == 51 || event.keyCode == 117 {
            onCombo?(nil)
            needsDisplay = true
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = HotKeyManager.carbonModifiers(from: flags)
        guard modifiers != 0 else { return } // 必须含修饰键，避免吞掉普通输入
        let glyph = (event.charactersIgnoringModifiers ?? "").uppercased()
        let display = HotKeyManager.modifiersDisplay(modifiers) + glyph
        onCombo?(HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers, display: display))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === self
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        (focused ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        border.lineWidth = focused ? 2 : 1
        border.stroke()

        let text = focused
            ? L("按下新的快捷键组合…")
            : (AppSettings.shared.hotKeys[action]?.display ?? L("未设置"))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: focused ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: 8, y: (bounds.height - size.height) / 2))
    }
}
