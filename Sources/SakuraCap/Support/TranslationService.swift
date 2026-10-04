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

struct TranslationConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let source: TranslateLanguage
    let target: TranslateLanguage
    let style: TranslateStyle
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
        let endpoint = base.hasSuffix("/chat/completions")
            ? base
            : base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: endpoint) else { throw TranslationError.invalidURL }

        let system = """
        You are a professional translation engine. Translate the user's text from \(config.source.promptName) \
        into \(config.target.promptName). Style: \(config.style.promptHint) \
        Preserve the original line breaks and formatting. \
        Output only the translation, without any explanation, notes, or surrounding quotes.
        """
        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text],
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.http(http.statusCode, String(message.prefix(300)))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 拉取可用模型列表（OpenAI 兼容的 GET /models）
    static func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw TranslationError.invalidURL }
        let endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models"
        guard let url = URL(string: endpoint) else { throw TranslationError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
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
