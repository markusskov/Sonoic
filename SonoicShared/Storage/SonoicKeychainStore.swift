import Foundation
import Security

struct SonoicKeychainStore {
    enum KeychainError: LocalizedError {
        case encodingFailed
        case decodingFailed
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                "Sonoic couldn't encode the secure item."
            case .decodingFailed:
                "Sonoic couldn't read the secure item."
            case let .unexpectedStatus(status):
                "Keychain returned status \(status)."
            }
        }
    }

    private let service = "com.markusskov.Sonoic.sonos-control-api"
    private let sonosTokenAccount = "sonos-oauth-token-set"

    func loadSonosTokenSet() throws -> SonosOAuthTokenSet? {
        var query = baseQuery(account: sonosTokenAccount)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let tokenSet = try? JSONDecoder().decode(SonosOAuthTokenSet.self, from: data)
        else {
            throw KeychainError.decodingFailed
        }

        return tokenSet
    }

    func saveSonosTokenSet(_ tokenSet: SonosOAuthTokenSet) throws {
        guard let data = try? JSONEncoder().encode(tokenSet) else {
            throw KeychainError.encodingFailed
        }

        var query = baseQuery(account: sonosTokenAccount)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        attributes.forEach { query[$0.key] = $0.value }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func deleteSonosTokenSet() throws {
        let status = SecItemDelete(baseQuery(account: sonosTokenAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
