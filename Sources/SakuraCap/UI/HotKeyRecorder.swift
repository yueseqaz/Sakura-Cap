import AppKit
import SwiftUI

/// 快捷键录制控件：点击获得焦点，按下任意「修饰键+按键」即注册为新的全局快捷键。
struct HotKeyRecorderView: NSViewRepresentable {
    func makeNSView(context: Context) -> HotKeyCaptureView {
        let view = HotKeyCaptureView()
        view.onCombo = { combo in
            AppSettings.shared.updateHotKey(combo)
            view.needsDisplay = true
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyCaptureView, context: Context) {
        nsView.needsDisplay = true
    }
}

final class HotKeyCaptureView: NSView {
    var onCombo: ((HotKeyCombo) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = HotKeyManager.carbonModifiers(from: flags)
        guard modifiers != 0 else { return } // 必须含修饰键，避免吞掉普通输入
        let glyph = (event.charactersIgnoringModifiers ?? "").uppercased()
        let display = HotKeyManager.modifiersDisplay(modifiers) + glyph
        onCombo?(HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers, display: display))
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
            : AppSettings.shared.hotKeyDisplay + L("（点击修改）")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: focused ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: 8, y: (bounds.height - size.height) / 2))
    }
}
