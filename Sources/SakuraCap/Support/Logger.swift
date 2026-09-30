import Foundation
import os

// 统一日志。查看：log stream --predicate 'process == "SakuraCap"' --level debug
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.sakura.sakuracap"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let writer = Logger(subsystem: subsystem, category: "writer")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let indicator = Logger(subsystem: subsystem, category: "indicator")
    static let permission = Logger(subsystem: subsystem, category: "permission")
}
