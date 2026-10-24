import AppKit
import Foundation

/// AI 对话客户端：复用「设置 → 翻译」里配置的服务商（三种接口格式），
/// SSE 流式输出；多模态图片按各家格式编码（仅携带最近一条用户消息的图片，
/// 更早的图片不出示给模型以节省 token）。
enum AIChatClient {
    enum ChatError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case http(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return L("请先在「设置 → 翻译」里填写 API Key")
            case .invalidURL: return L("AI 接口地址无效")
            case .http(let code, let body): return String(format: L("AI 请求失败（%d）：%@"), code, body)
            case .emptyResponse: return L("AI 返回为空")
            }
        }
    }

    static let systemPrompt = """
    You are Sakura-Cap's built-in AI assistant, mainly helping users understand and analyze screen content \
    (screenshots, UI, error messages, code) and answer follow-up questions. \
    Answer in the user's language. Use Markdown formatting when helpful (code blocks, lists, tables). \
    Be concise and accurate.
    """

    /// 发起一轮流式对话；onDelta 在收到增量时回调（可能来自后台线程），
    /// 返回完整的助手回复文本。
    static func stream(messages: [AIChatMessage],
                       config: TranslationConfig,
                       store: AIChatStore,
                       onDelta: @escaping (String) -> Void) async throws -> String {
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ChatError.missingAPIKey }
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw ChatError.invalidURL }
        let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = config.format.endpointSuffix
        let endpoint = base.hasSuffix(suffix) ? base : trimmedBase + suffix
        guard let url = URL(string: endpoint) else { throw ChatError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch config.format {
        case .openAIChat, .openAIResponses:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            messages: messages, config: config, store: store))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 400 { break } }
            throw ChatError.http(http.statusCode, String(body.prefix(300)))
        }

        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let delta = Self.delta(json, format: config.format)
            if let delta, !delta.isEmpty {
                full += delta
                onDelta(delta)
            }
        }
        guard !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatError.emptyResponse }
        return full
    }

    /// 从各格式的 SSE data 里取文本增量
    private static func delta(_ json: [String: Any], format: CustomAPIFormat) -> String? {
        switch format {
        case .openAIChat:
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { return nil }
            return delta["content"] as? String
        case .openAIResponses:
            guard (json["type"] as? String) == "response.output_text.delta" else { return nil }
            return json["delta"] as? String
        case .anthropic:
            guard (json["type"] as? String) == "content_block_delta",
                  let delta = json["delta"] as? [String: Any],
                  (delta["type"] as? String) == "text_delta" else { return nil }
            return delta["text"] as? String
        }
    }

    /// 各格式请求体（历史 + 多模态）
    private static func requestBody(messages: [AIChatMessage], config: TranslationConfig, store: AIChatStore) -> [String: Any] {
        // 只带最后一条用户消息的图片
        let lastImageUserID = messages.last(where: { $0.role == .user && !$0.imageFiles.isEmpty })?.id

        func imageParts(_ message: AIChatMessage) -> [[String: Any]] {
            guard message.id == lastImageUserID else { return [] }
            return message.imageFiles.compactMap { name -> [String: Any]? in
                guard let cg = store.loadImage(name),
                      let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
                let base64 = data.base64EncodedString()
                switch config.format {
                case .openAIChat:
                    return ["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                case .openAIResponses:
                    return ["type": "input_image",
                            "image_url": "data:image/jpeg;base64,\(base64)"]
                case .anthropic:
                    return ["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]]
                }
            }
        }

        switch config.format {
        case .openAIChat:
            let history: [[String: Any]] = [["role": "system", "content": systemPrompt]] + messages.map { message in
                let parts = imageParts(message)
                if parts.isEmpty {
                    return ["role": message.role == .user ? "user" : "assistant", "content": message.text]
                }
                var content: [[String: Any]] = [["type": "text", "text": message.text]]
                content += parts
                return ["role": "user", "content": content]
            }
            return ["model": config.model, "stream": true, "messages": history]
        case .openAIResponses:
            let history: [[String: Any]] = messages.map { message in
                let parts = imageParts(message)
                if parts.isEmpty {
                    return ["role": message.role == .user ? "user" : "assistant", "content": message.text]
                }
                var content: [[String: Any]] = [["type": "input_text", "text": message.text]]
                content += parts
                return ["role": "user", "content": content]
            }
            return ["model": config.model, "stream": true, "instructions": systemPrompt, "input": history]
        case .anthropic:
            let history: [[String: Any]] = messages.map { message in
                let parts = imageParts(message)
                if parts.isEmpty {
                    return ["role": message.role == .user ? "user" : "assistant", "content": message.text]
                }
                var content: [[String: Any]] = [["type": "text", "text": message.text]]
                content += parts
                return ["role": "user", "content": content]
            }
            return ["model": config.model, "max_tokens": 4096, "stream": true,
                    "system": systemPrompt, "messages": history]
        }
    }
}
