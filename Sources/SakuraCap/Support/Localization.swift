import Foundation

/// The app can keep using the system language, or pin its own language for
/// the next launch.  AppKit and SwiftUI both resolve NSLocalizedString at
/// process startup, so changing this preference is intentionally applied on
/// the next launch instead of partially changing an open window.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("跟随系统")
        case .chinese: return L("简体中文")
        case .english: return "English"
        }
    }

    func apply(to defaults: UserDefaults) {
        switch self {
        case .system:
            defaults.removeObject(forKey: "AppleLanguages")
        case .chinese:
            defaults.set(["zh-Hans"], forKey: "AppleLanguages")
        case .english:
            defaults.set(["en"], forKey: "AppleLanguages")
        }
        defaults.synchronize()
    }
}

/// 应用内本地化：以中文原文作为 key，在 Localizable.strings 中查表。
///
/// - SwiftUI 的 `Text` / `Button` / `Toggle` / `Label` / `Picker` 等接收字符串**字面量**时会
///   自动按 `LocalizedStringKey` 本地化，无需改动；
/// - 需要显式处理的 `String`（菜单项、弹窗、枚举 `label`、banner 等）用 `L("中文")`。
///
/// 翻译在 `Resources/<lang>.lproj/Localizable.strings`，由 build.sh 打进 .app。
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
