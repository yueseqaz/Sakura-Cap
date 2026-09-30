import Foundation

/// 应用元信息（版本、仓库地址），供「关于」等界面使用。
enum AppInfo {
    static let repository = URL(string: "https://github.com/yueseqaz/Sakura-Cap")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
}
