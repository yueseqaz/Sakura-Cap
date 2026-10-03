import Foundation

/// 自动命名：截图 / 录屏 / 截帧统一使用设置里的模板。
/// 模板占位符：{date} 日期、{time} 时间、{datetime} 日期+时间、{rand} 5 位随机数。
enum FileName {
    static let defaultPattern = "Sakura-cap-{date}-{time}-{rand}"

    /// 生成不含扩展名的文件名基底（同一次录制多屏共用同一个随机码）。
    static func base(pattern: String? = nil, date: Date = Date(), random: Int? = nil) -> String {
        let raw = pattern ?? AppSettings.shared.fileNamePattern
        let template = raw.trimmingCharacters(in: .whitespaces).isEmpty ? defaultPattern : raw
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.dateFormat = "HH.mm.ss"
        let code = String(format: "%05d", random ?? Int.random(in: 10000...99999))
        var name = template
            .replacingOccurrences(of: "{date}", with: day.string(from: date))
            .replacingOccurrences(of: "{time}", with: time.string(from: date))
            .replacingOccurrences(of: "{datetime}", with: "\(day.string(from: date)) \(time.string(from: date))")
            .replacingOccurrences(of: "{rand}", with: code)
        name = sanitize(name)
        return name.isEmpty ? "Sakura-cap" : name
    }

    /// 生成完整文件名（含扩展名）。
    static func make(ext: String, pattern: String? = nil, date: Date = Date(), random: Int? = nil) -> String {
        "\(base(pattern: pattern, date: date, random: random)).\(ext)"
    }

    /// 去掉文件名中不安全的字符。
    static func sanitize(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .replacingOccurrences(of: "\\", with: "-")
    }
}
