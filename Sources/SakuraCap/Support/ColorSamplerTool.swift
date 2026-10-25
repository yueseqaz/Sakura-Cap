import AppKit

/// 全局取色器：系统放大镜 UI 选取屏幕任意位置的颜色，
/// HEX 自动进剪贴板，Toast 里附 RGB 值。无需任何权限。
@MainActor
enum ColorSamplerTool {
    /// NSColorSampler 在完成回调前必须被持有，提前释放会连取色 UI 一起关闭
    private static var activeSampler: NSColorSampler?

    static func sample() {
        let sampler = NSColorSampler()
        activeSampler = sampler
        sampler.show { color in
            Task { @MainActor in
                activeSampler = nil
                guard let srgb = color?.usingColorSpace(.sRGB) else { return } // 按 Esc = 取消
                let red = Int((srgb.redComponent * 255).rounded())
                let green = Int((srgb.greenComponent * 255).rounded())
                let blue = Int((srgb.blueComponent * 255).rounded())
                let hex = String(format: "#%02X%02X%02X", red, green, blue)
                let rgb = "rgb(\(red), \(green), \(blue))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
                Toast.show(title: String(format: L("已复制颜色 %@"), hex),
                           detail: rgb + L("（HEX 已进剪贴板）"))
            }
        }
    }
}
