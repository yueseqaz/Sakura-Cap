import AppKit

/// An app-owned color menu; unlike NSColorWell it never opens the shared NSColorPanel.
final class AnnotationColorPicker: NSButton {
    var selectedColor: NSColor = .systemRed { didSet { updateAppearance() } }
    var onSelect: ((NSColor) -> Void)?

    private static let swatches: [(String, NSColor)] = [
        ("红色", .systemRed), ("橙色", .systemOrange), ("黄色", .systemYellow),
        ("绿色", .systemGreen), ("青色", .systemTeal), ("蓝色", .systemBlue),
        ("紫色", .systemPurple), ("粉色", .systemPink), ("白色", .white),
        ("灰色", .systemGray), ("黑色", .black)
    ]

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = ""
        target = self
        action = #selector(showColors)
        toolTip = L("标注颜色")
        setAccessibilityLabel(L("标注颜色"))
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateAppearance() {
        let color = selectedColor
        image = NSImage(size: NSSize(width: 17, height: 17), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        imagePosition = .imageOnly
    }

    @objc private func showColors() {
        let menu = NSMenu()
        for (index, swatch) in Self.swatches.enumerated() {
            let item = NSMenuItem(title: swatch.0, action: #selector(chooseColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                swatch.1.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            item.state = selectedColor.usingColorSpace(.sRGB) == swatch.1.usingColorSpace(.sRGB) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let custom = NSMenuItem(title: "HEX…", action: #selector(enterHex), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
    }

    @objc private func chooseColor(_ item: NSMenuItem) {
        guard Self.swatches.indices.contains(item.tag) else { return }
        select(Self.swatches[item.tag].1)
    }

    @objc private func enterHex() {
        let alert = NSAlert()
        alert.messageText = L("输入颜色 HEX")
        alert.informativeText = "#RRGGBB"
        alert.addButton(withTitle: L("确定"))
        alert.addButton(withTitle: L("取消"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 210, height: 24))
        if let color = selectedColor.usingColorSpace(.sRGB) {
            field.stringValue = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                                       Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
        }
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let hex = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return }
        select(NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                       green: CGFloat((value >> 8) & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255, alpha: 1))
    }

    private func select(_ color: NSColor) {
        selectedColor = color
        onSelect?(color)
    }
}
