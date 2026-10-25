import Foundation
import CryptoKit

/// 图床服务类型
enum ImageHostProvider: String, CaseIterable, Identifiable {
    case s3
    case github
    case custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .s3: return L("S3 兼容")
        case .github: return L("GitHub 仓库")
        case .custom: return L("自定义接口")
        }
    }
}

/// 上传成功后放进剪贴板的链接格式
enum ImageLinkFormat: String, CaseIterable, Identifiable {
    case url
    case markdown
    case html

    var id: String { rawValue }
    var label: String {
        switch self {
        case .url: return L("纯链接")
        case .markdown: return L("Markdown 图片")
        case .html: return L("HTML 图片")
        }
    }

    func text(url: String) -> String {
        switch self {
        case .url: return url
        case .markdown: return "![image](\(url))"
        case .html: return "<img src=\"\(url)\" />"
        }
    }
}

enum ImageHostError: LocalizedError {
    case notConfigured
    case badEndpoint
    case http(status: Int, body: String)
    case noURLInResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("图床未配置完整，请到 设置 → 图床 检查")
        case .badEndpoint: return L("Endpoint 格式不对，应形如 https://xxx.r2.cloudflarestorage.com")
        case .http(let status, let body):
            let snippet = body.count > 160 ? String(body.prefix(160)) + "…" : body
            return String(format: L("服务端返回 %d：%@"), status, snippet)
        case .noURLInResponse: return L("上传成功但没能从响应里解析出链接，请检查路径/正则配置")
        }
    }
}

/// 图床上传：S3 兼容（SigV4 PUT）/ GitHub Contents API / 自定义 multipart 接口。
/// 返回可直接访问的公开 URL 字符串。
enum ImageHost {
    static let defaultPathPattern = "sakura-cap/{date}/{time}-{rand}"

    /// 当前提供商是否已填完必需配置（用于上传按钮的前置判断）
    static var isConfigured: Bool {
        let s = AppSettings.shared
        switch s.imageHostProvider {
        case .s3:
            return !s.imageHostS3Endpoint.isEmpty && !s.imageHostS3Bucket.isEmpty
                && !s.imageHostS3AccessKeyID.isEmpty && !s.imageHostS3SecretKey.isEmpty
                && !s.imageHostS3PublicPrefix.isEmpty
        case .github:
            return !s.imageHostGitHubRepo.isEmpty && !s.imageHostGitHubToken.isEmpty
        case .custom:
            return !s.imageHostCustomURL.isEmpty
        }
    }

    /// 上传 PNG 数据，成功返回公开链接
    static func upload(png: Data) async throws -> String {
        let s = AppSettings.shared
        let key = expandPattern(s.imageHostPathPattern) + ".png"
        switch s.imageHostProvider {
        case .s3: return try await s3Put(data: png, key: key, settings: s)
        case .github: return try await githubPut(data: png, key: key, settings: s)
        case .custom: return try await customPost(data: png, filename: key, settings: s)
        }
    }

    // MARK: - 路径模板

    /// 展开存储路径模板。与本地文件名模板同一套占位符，但保留 "/" 作目录分隔
    /// （FileName.sanitize 会把 "/" 清洗掉，不适用于对象存储的层级路径）。
    static func expandPattern(_ raw: String, date: Date = Date()) -> String {
        let template = raw.trimmingCharacters(in: .whitespaces).isEmpty ? defaultPathPattern : raw
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.dateFormat = "HH.mm.ss"
        let code = String(format: "%05d", Int.random(in: 10000...99999))
        let expanded = template
            .replacingOccurrences(of: "{date}", with: day.string(from: date))
            .replacingOccurrences(of: "{time}", with: time.string(from: date))
            .replacingOccurrences(of: "{datetime}", with: "\(day.string(from: date)) \(time.string(from: date))")
            .replacingOccurrences(of: "{rand}", with: code)
        // 逐段清洗：只去掉文件名不安全字符，保留 "/"
        let segments = expanded.split(separator: "/", omittingEmptySubsequences: false).map { segment in
            let cleaned = segment
                .replacingOccurrences(of: ":", with: ".")
                .replacingOccurrences(of: "\\", with: "-")
            return cleaned.allSatisfy({ $0.isWhitespace }) ? "" : cleaned
        }
        let joined = segments.joined(separator: "/")
            .replacingOccurrences(of: "//", with: "/")
        return joined.hasPrefix("/") ? String(joined.dropFirst()) : joined
    }

    // MARK: - S3 兼容（SigV4，path-style）

    private static func s3Put(data: Data, key: String, settings s: AppSettings) async throws -> String {
        guard let endpoint = URL(string: s.imageHostS3Endpoint.trimmingCharacters(in: .whitespaces)),
              let host = endpoint.host?.lowercased(),
              !s.imageHostS3Bucket.isEmpty else { throw ImageHostError.badEndpoint }
        let bucket = s.imageHostS3Bucket.trimmingCharacters(in: .whitespaces)
        let region = s.imageHostS3Region.trimmingCharacters(in: .whitespaces)
        let regionUsed = region.isEmpty ? "auto" : region

        let port = endpoint.port.map { ":\($0)" } ?? ""
        let hostHeader = host + port
        let scheme = endpoint.scheme?.lowercased() == "http" ? "http" : "https"
        let encodedKey = key.split(separator: "/", omittingEmptySubsequences: false)
            .map { uriEncode(String($0)) }.joined(separator: "/")
        let canonicalURI = "/\(bucket)/\(encodedKey)"
        guard let requestURL = URL(string: "\(scheme)://\(hostHeader)\(canonicalURI)") else {
            throw ImageHostError.badEndpoint
        }

        let payloadHash = sha256Hex(data)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let amzDate = formatter.string(from: Date())
        let dateStamp = String(amzDate.prefix(8))

        let canonicalHeaders = "host:\(hostHeader)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = "PUT\n\(canonicalURI)\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let scope = "\(dateStamp)/\(regionUsed)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(sha256Hex(Data(canonicalRequest.utf8)))"

        let kSecret = Data("AWS4\(s.imageHostS3SecretKey)".utf8)
        let kDate = hmac(kSecret, Data(dateStamp.utf8))
        let kRegion = hmac(kDate, Data(regionUsed.utf8))
        let kService = hmac(kRegion, Data("s3".utf8))
        let kSigning = hmac(kService, Data("aws4_request".utf8))
        let signature = hmac(kSigning, Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("AWS4-HMAC-SHA256 Credential=\(s.imageHostS3AccessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)", forHTTPHeaderField: "Authorization")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let (bodyData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageHostError.badEndpoint }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageHostError.http(status: http.statusCode, body: String(data: bodyData, encoding: .utf8) ?? "")
        }
        let prefix = s.imageHostS3PublicPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(prefix)/\(key)"
    }

    /// RFC 3986：除 unreserved（字母数字 - _ . ~）外全部 %XX 大写编码
    private static func uriEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - GitHub Contents API

    private static func githubPut(data: Data, key: String, settings s: AppSettings) async throws -> String {
        let repo = s.imageHostGitHubRepo.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !repo.isEmpty else { throw ImageHostError.notConfigured }
        let branch = s.imageHostGitHubBranch.trimmingCharacters(in: .whitespaces)
        let branchUsed = branch.isEmpty ? "main" : branch
        let encodedPath = key.split(separator: "/", omittingEmptySubsequences: false)
            .map { uriEncode(String($0)) }.joined(separator: "/")
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/contents/\(encodedPath)") else {
            throw ImageHostError.badEndpoint
        }
        let payload: [String: Any] = [
            "message": "Upload via Sakura-Cap",
            "content": data.base64EncodedString(),
            "branch": branchUsed,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("Bearer \(s.imageHostGitHubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sakura-Cap", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        let (bodyData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageHostError.badEndpoint }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageHostError.http(status: http.statusCode, body: String(data: bodyData, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let downloadURL = json["content"].flatMap({ ($0 as? [String: Any])?["download_url"] as? String }),
              !downloadURL.isEmpty else {
            throw ImageHostError.noURLInResponse
        }
        return downloadURL
    }

    // MARK: - 自定义接口（multipart POST）

    private static func customPost(data: Data, filename: String, settings s: AppSettings) async throws -> String {
        guard let url = URL(string: s.imageHostCustomURL.trimmingCharacters(in: .whitespaces)) else {
            throw ImageHostError.badEndpoint
        }
        let field = s.imageHostCustomFileField.trimmingCharacters(in: .whitespaces)
        let fieldUsed = field.isEmpty ? "file" : field
        let boundary = "SakuraCap-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldUsed)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: image/png\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        // 附加自定义头（支持换行或分号分隔，每项格式 "Key: Value"）
        for line in s.imageHostCustomHeaders.components(separatedBy: CharacterSet(charactersIn: ";\n")) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let colon = trimmed.firstIndex(of: ":") else { continue }
            let name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (bodyData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageHostError.badEndpoint }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageHostError.http(status: http.statusCode, body: String(data: bodyData, encoding: .utf8) ?? "")
        }
        let text = String(data: bodyData, encoding: .utf8) ?? ""
        // 先按 JSON 点路径取（如 data.url），再退回正则
        let path = s.imageHostCustomURLPath.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            var current: Any? = json
            for segment in path.split(separator: ".") {
                guard let dict = current as? [String: Any] else { current = nil; break }
                current = dict[String(segment)]
            }
            if let url = current as? String, !url.isEmpty, url.hasPrefix("http") { return url }
        }
        let regexText = s.imageHostCustomURLRegex.trimmingCharacters(in: .whitespaces)
        if !regexText.isEmpty, let regex = try? NSRegularExpression(pattern: regexText),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                ? match.range(at: 1) : match.range
            if let swiftRange = Range(range, in: text) {
                let found = String(text[swiftRange])
                if found.hasPrefix("http") { return found }
            }
        }
        throw ImageHostError.noURLInResponse
    }

    // MARK: - 摘要工具

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(_ key: Data, _ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }
}
