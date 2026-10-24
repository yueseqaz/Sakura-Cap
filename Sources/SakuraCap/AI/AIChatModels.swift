import AppKit
import Foundation

/// 一条聊天消息（图片以文件引用存，避免 JSON 膨胀）
struct AIChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    var role: Role
    var text: String
    /// 附件图片文件名（存于会话图片目录）
    var imageFiles: [String] = []

    init(id: UUID = UUID(), role: Role, text: String, imageFiles: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.imageFiles = imageFiles
    }
}

/// 一次会话：标题 + 消息列表，JSON 持久化
struct AIChatSession: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [AIChatMessage]
    /// 记忆压缩：早期对话的滚动摘要（nil = 未启用）
    var summary: String?
    /// 已并入摘要的消息条数（messages 前缀长度）
    var summarizedUpTo: Int?

    init(id: UUID = UUID(), title: String = "", createdAt: Date = Date(), updatedAt: Date = Date(), messages: [AIChatMessage] = [], summary: String? = nil, summarizedUpTo: Int? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.summary = summary
        self.summarizedUpTo = summarizedUpTo
    }

    /// 首条用户消息前 24 字作为标题
    mutating func refreshTitle() {
        if title.isEmpty, let first = messages.first(where: { !$0.text.isEmpty }) {
            title = String(first.text.prefix(24))
        }
    }
}

/// 会话存储：Application Support/SakuraCap/AIChats/<id>.json + images/<文件名>
@MainActor
final class AIChatStore {
    static let shared = AIChatStore()

    private(set) var sessions: [AIChatSession] = []
    let directory: URL
    private let imagesDirectory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = support.appendingPathComponent("SakuraCap/AIChats", isDirectory: true)
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        sessions = files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(AIChatSession.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 保存（upsert）并按更新时间重排
    func save(_ session: inout AIChatSession) {
        session.updatedAt = Date()
        session.refreshTitle()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(session) {
            try? data.write(to: directory.appendingPathComponent("\(session.id.uuidString).json"), options: .atomic)
        }
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
    }

    /// 彻底删除：会话 JSON + 消息里引用的全部图片文件
    func delete(_ session: AIChatSession) {
        sessions.removeAll { $0.id == session.id }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(session.id.uuidString).json"))
        for message in session.messages {
            for name in message.imageFiles {
                try? FileManager.default.removeItem(at: imageFileURL(name))
            }
        }
    }

    /// 压缩为 JPEG 存入图片目录，返回文件名（长边压到 1600，足够视觉模型且省 token）
    @discardableResult
    func saveImage(_ image: CGImage) -> String? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(CGFloat(image.width), CGFloat(image.height)))
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let canvas = NSImage(size: size)
        canvas.lockFocusFlipped(false)
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            .draw(in: NSRect(origin: .zero, size: size),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let bitmap = NSBitmapImageRep(focusedViewRect: NSRect(origin: .zero, size: size))
        canvas.unlockFocus()
        guard let bitmap,
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    nonisolated func imageFileURL(_ name: String) -> URL {
        imagesDirectory.appendingPathComponent(name)
    }

    /// 纯文件读取，允许从非主线程（流式请求构建）调用
    nonisolated func loadImage(_ name: String) -> CGImage? {
        guard let data = try? Data(contentsOf: imageFileURL(name)) else { return nil }
        return NSBitmapImageRep(data: data)?.cgImage
    }
}
