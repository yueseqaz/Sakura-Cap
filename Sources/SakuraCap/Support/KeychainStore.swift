import Foundation
import Security

/// 轻量 Keychain 存取（kSecClassGenericPassword），用于 API Key 等敏感值。
///
/// 注意：应用为 ad-hoc 签名，每次重新构建签名都会变化，首次访问上次构建创建的
/// 条目时 macOS 可能弹一次系统授权框（选「始终允许」后不再提示）。属已知开发期
/// 现象，详见 docs/DEVELOPMENT.md。
enum KeychainStore {
    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let code): return "Keychain error (\(code))"
            }
        }
    }

    private static let service = (Bundle.main.bundleIdentifier ?? "com.sakura.sakuracap") + ".secrets"

    /// 读；不存在或失败返回 nil
    static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// 写（条目存在则更新）
    static func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var status: OSStatus
        if SecItemCopyMatching(baseQuery(account: account) as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        } else {
            var add = baseQuery(account: account)
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// 删除（不存在不算错）
    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // 仅本机、解锁后可读：API Key 不随 iCloud 钥匙串同步
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }
}
