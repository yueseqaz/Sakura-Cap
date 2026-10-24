import Foundation

/// 翻译服务商
enum TranslateProvider: String, CaseIterable, Identifiable {
    case deepSeek, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .custom: return L("自定义")
        }
    }
    var defaultBaseURL: String {
        switch self {
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .custom: return ""
        }
    }
    var defaultModel: String {
        switch self {
        case .deepSeek: return "deepseek-chat"
        case .custom: return ""
        }
    }
}

/// 翻译语言（auto 仅用于原文）
enum TranslateLanguage: String, CaseIterable, Identifiable {
    case auto, zhHans, zhHant, en, ja, ko, fr, de, es, ru
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L("自动检测")
        case .zhHans: return L("简体中文")
        case .zhHant: return L("繁體中文")
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .ru: return "Русский"
        }
    }

    /// 给模型看的英文名
    var promptName: String {
        switch self {
        case .auto: return "the source language (auto-detect it)"
        case .zhHans: return "Simplified Chinese"
        case .zhHant: return "Traditional Chinese"
        case .en: return "English"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .fr: return "French"
        case .de: return "German"
        case .es: return "Spanish"
        case .ru: return "Russian"
        }
    }
}

/// 自定义服务商的接口格式（方言）
enum CustomAPIFormat: String, CaseIterable, Identifiable {
    case openAIChat       // POST /chat/completions
    case openAIResponses  // POST /responses
    case anthropic        // POST /messages（x-api-key + anthropic-version）

    var id: String { rawValue }
    var label: String {
        switch self {
        case .openAIChat: return "OpenAI Chat"
        case .openAIResponses: return "OpenAI Responses"
        case .anthropic: return "Anthropic"
        }
    }
    /// 该格式在 baseURL 后追加的端点
    var endpointSuffix: String {
        switch self {
        case .openAIChat: return "/chat/completions"
        case .openAIResponses: return "/responses"
        case .anthropic: return "/messages"
        }
    }
}

struct TranslationConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let source: TranslateLanguage
    let target: TranslateLanguage
    let style: TranslateStyle
    var format: CustomAPIFormat = .openAIChat
}

/// 翻译风格
enum TranslateStyle: String, CaseIterable, Identifiable {
    case natural, literal, formal, casual, concise
    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return L("自然")
        case .literal: return L("直译")
        case .formal: return L("正式")
        case .casual: return L("口语")
        case .concise: return L("简洁")
        }
    }

    var promptHint: String {
        switch self {
        case .natural: return "Natural and fluent, as a native speaker would write."
        case .literal: return "Literal and faithful to the original wording and structure."
        case .formal: return "Formal, professional, and polite."
        case .casual: return "Casual and conversational, like everyday speech."
        case .concise: return "Concise and to the point, keeping only essential meaning."
        }
    }
}

/// AI 翻译：走 OpenAI 兼容的 Chat Completions 接口（DeepSeek / 自定义均可）。
enum TranslationService {
    enum TranslationError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case http(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return L("请先在「设置 → 翻译」里填写 API Key")
            case .invalidURL: return L("翻译 API 地址无效")
            case .http(let code, let body): return String(format: L("翻译请求失败（%d）：%@"), code, body)
            case .emptyResponse: return L("翻译返回为空")
            }
        }
    }

    static func translate(_ text: String, config: TranslationConfig) async throws -> String {
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranslationError.missingAPIKey }
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw TranslationError.invalidURL }
        let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = config.format.endpointSuffix
        let endpoint = base.hasSuffix(suffix) ? base : trimmedBase + suffix
        guard let url = URL(string: endpoint) else { throw TranslationError.invalidURL }

        let system = """
        You are a professional translation engine. Translate the user's text from \(config.source.promptName) \
        into \(config.target.promptName). Style: \(config.style.promptHint) \
        Preserve the original line breaks and formatting. \
        Output only the translation, without any explanation, notes, or surrounding quotes.
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch config.format {
        case .openAIChat, .openAIResponses:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            format: config.format, model: config.model, system: system, text: text))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.http(http.statusCode, String(message.prefix(300)))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = parseResponse(json, format: config.format),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 各格式的请求体
    private static func requestBody(format: CustomAPIFormat, model: String, system: String, text: String) -> [String: Any] {
        switch format {
        case .openAIChat:
            return [
                "model": model,
                "temperature": 0.2,
                "stream": false,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": text],
                ],
            ]
        case .openAIResponses:
            return [
                "model": model,
                "instructions": system,
                "temperature": 0.2,
                "store": false,
                "input": text,
            ]
        case .anthropic:
            return [
                "model": model,
                "max_tokens": 4096,
                "temperature": 0.2,
                "system": system,
                "messages": [["role": "user", "content": text]],
            ]
        }
    }

    /// 各格式的响应解析（部分网关会互相兼容，串一层兜底）
    private static func parseResponse(_ json: [String: Any], format: CustomAPIFormat) -> String? {
        // OpenAI Chat: choices[0].message.content（最通用，很多网关都回这个）
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        switch format {
        case .openAIChat:
            return nil
        case .openAIResponses:
            // SDK 糖字段；部分网关直接给
            if let text = json["output_text"] as? String { return text }
            // 原生 REST：output[].content[].text（type == output_text）
            guard let output = json["output"] as? [[String: Any]] else { return nil }
            return output.compactMap { item -> String? in
                guard let content = item["content"] as? [[String: Any]] else { return nil }
                return content.compactMap { block -> String? in
                    guard (block["type"] as? String) == "output_text" else { return nil }
                    return block["text"] as? String
                }.joined()
            }.joined()
        case .anthropic:
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()
        }
    }

    /// 拉取可用模型列表（GET /models；Anthropic 用 x-api-key 头）
    static func fetchModels(baseURL: String, apiKey: String, format: CustomAPIFormat = .openAIChat) async throws -> [String] {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw TranslationError.invalidURL }
        let endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models"
        guard let url = URL(string: endpoint) else { throw TranslationError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        switch format {
        case .anthropic:
            request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAIChat, .openAIResponses:
            request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.http(http.statusCode, String(message.prefix(300)))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw TranslationError.emptyResponse
        }
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}
