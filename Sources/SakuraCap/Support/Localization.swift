import Foundation

/// 应用内本地化：以中文原文作为 key，在 Localizable.strings 中查表。
///
/// - SwiftUI 的 `Text` / `Button` / `Toggle` / `Label` / `Picker` 等接收字符串**字面量**时会
///   自动按 `LocalizedStringKey` 本地化，无需改动；
/// - 需要显式处理的 `String`（菜单项、弹窗、枚举 `label`、banner 等）用 `L("中文")`。
///
/// 翻译在 `Resources/<lang>.lproj/Localizable.strings`，由 build.sh 打进 .app。
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
