import AppKit
import SwiftUI

/// Settings-only semantic colors from @radix-ui/colors 3.0.0 (sRGB).
/// Steps 1–2: surfaces; 3–5: interaction; 6–8: borders; 11–12: text.
enum SettingsAppearance {
    static let canvas = adaptive(0xFCFCFD, 0x111113)       // Slate 1
    static let sidebar = adaptive(0xF9F9FB, 0x18191B)      // Slate 2
    static let control = adaptive(0xF0F0F3, 0x212225)      // Slate 3
    static let pressed = adaptive(0xE0E1E6, 0x2E3135)      // Slate 5
    static let separator = adaptive(0xD9D9E0, 0x363A3F)    // Slate 6
    static let border = adaptive(0xCDCED6, 0x43484E)       // Slate 7
    static let text = adaptive(0x1C2024, 0xEDEEF0)         // Slate 12
    static let secondary = adaptive(0x60646C, 0xB0B4BA)    // Slate 11
    static let selection = adaptive(0xE6F4FE, 0x0D2847)    // Blue 3
    static let selectionPressed = adaptive(0xC2E5FF, 0x004074) // Blue 5
    static let focus = adaptive(0x0D74CE, 0x70B8FF)        // Blue 11, high-contrast keyboard focus
    static let accent = adaptive(0x0090FF, 0x0090FF)       // Blue 9
    static let accentText = adaptive(0x113264, 0xC2E6FF)    // Blue 12 on Blue 3 selection
    static let success = adaptive(0x218358, 0x3DD68C)       // Green 11
    static let warning = adaptive(0x4F3422, 0xFFCA16)       // Amber 12/11 for small status text
    static let error = adaptive(0xCE2C31, 0xFF9592)         // Red 11

    static let titleFont = Font.system(size: 16, weight: .semibold)
    static let bodyFont = Font.system(size: 13)
    static let detailFont = Font.system(size: 12)
    static let borderWidth: CGFloat = 0.5
    static let controlRadius: CGFloat = 5
    static let rowHeight: CGFloat = 30

    static func color(_ color: NSColor) -> Color { Color(nsColor: color) }

    static func applySurface(to view: NSView, fill: NSColor = canvas, border: NSColor = separator,
                             radius: CGFloat = 0) {
        view.wantsLayer = true
        view.layer?.backgroundColor = fill.cgColor
        view.layer?.borderColor = border.cgColor
        view.layer?.borderWidth = borderWidth
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = radius > 0
    }

    static func styleToolbarButton(_ button: NSButton) {
        button.contentTintColor = text
        button.font = NSFont.systemFont(ofSize: 13)
        button.controlSize = .regular
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsAppearance.bodyFont)
            .foregroundStyle(SettingsAppearance.color(isEnabled ? SettingsAppearance.text : SettingsAppearance.secondary))
            .padding(.horizontal, 10)
            .frame(minHeight: SettingsAppearance.rowHeight)
            .background(RoundedRectangle(cornerRadius: SettingsAppearance.controlRadius)
                .fill(SettingsAppearance.color(configuration.isPressed ? SettingsAppearance.pressed :
                    SettingsAppearance.control)))
            .overlay(RoundedRectangle(cornerRadius: SettingsAppearance.controlRadius)
                .strokeBorder(SettingsAppearance.color(SettingsAppearance.border), lineWidth: SettingsAppearance.borderWidth))
    }
}

struct SettingsNavigationStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsAppearance.bodyFont.weight(selected ? .semibold : .regular))
            .foregroundStyle(SettingsAppearance.color(selected ? SettingsAppearance.accentText : SettingsAppearance.text))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: SettingsAppearance.controlRadius)
                .fill(SettingsAppearance.color(configuration.isPressed ? SettingsAppearance.selectionPressed :
                    (selected ? SettingsAppearance.selection : SettingsAppearance.sidebar))))
    }
}

struct SettingsFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(SettingsAppearance.bodyFont)
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 8)
            .frame(minHeight: SettingsAppearance.rowHeight)
            .background(RoundedRectangle(cornerRadius: SettingsAppearance.controlRadius)
                .fill(SettingsAppearance.color(SettingsAppearance.canvas)))
            .overlay(RoundedRectangle(cornerRadius: SettingsAppearance.controlRadius)
                .strokeBorder(SettingsAppearance.color(focused ? SettingsAppearance.focus : SettingsAppearance.border),
                              lineWidth: SettingsAppearance.borderWidth))
    }
}
