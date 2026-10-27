import AppKit
import SwiftUI

/// Shared semantic colors from @radix-ui/colors 3.0.0 (sRGB).
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
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = radius > 0
        let surface = AppearanceSurfaceView(fill: fill, border: border, radius: radius)
        surface.frame = view.bounds
        surface.autoresizingMask = [.width, .height]
        view.addSubview(surface, positioned: .below, relativeTo: nil)
    }

    static func styleToolbarButton(_ button: NSButton) {
        button.contentTintColor = text
        button.font = NSFont.systemFont(ofSize: 13)
        button.controlSize = .regular
    }

    /// Match the selected appearance of the annotation segmented control on
    /// standalone icon buttons.  A light selection surface keeps a vertical
    /// rail from turning into a column of saturated blue pills while still
    /// making the active tool unambiguous.
    static func setToolActive(_ button: NSButton, _ active: Bool, inactiveColor: NSColor = text) {
        button.wantsLayer = true
        button.isBordered = false
        button.layer?.cornerRadius = controlRadius
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = active ? selection.cgColor : NSColor.clear.cgColor
        button.layer?.borderWidth = active ? borderWidth : 0
        button.layer?.borderColor = active ? focus.withAlphaComponent(0.32).cgColor : nil
        button.contentTintColor = active ? focus : inactiveColor
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

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsAppearance.bodyFont.weight(.medium))
            .foregroundStyle(isEnabled ? Color.white : SettingsAppearance.color(SettingsAppearance.secondary))
            .padding(.horizontal, 12)
            .frame(minHeight: SettingsAppearance.rowHeight)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(SettingsAppearance.color(isEnabled ? SettingsAppearance.focus : SettingsAppearance.control)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Resolve semantic colors at draw time, in the owning window's appearance.
/// A CGColor stored on a layer is only a snapshot and does not adapt to theme changes.
final class AppearanceSurfaceView: NSView {
    private let fill: NSColor
    private let border: NSColor
    private let radius: CGFloat

    init(fill: NSColor, border: NSColor, radius: CGFloat) {
        self.fill = fill
        self.border = border
        self.radius = radius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        border.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: SettingsAppearance.borderWidth / 2,
                                                          dy: SettingsAppearance.borderWidth / 2),
                                xRadius: radius, yRadius: radius)
        path.lineWidth = SettingsAppearance.borderWidth
        path.stroke()
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
