import Foundation
import Security

enum PINKeychainError: Error {
    case saveFailed
    case readFailed
    case deleteFailed
}

/// Stores only a salted PBKDF2 verifier — never the raw PIN.
enum PINKeychainStore {
    private static let service = "com.optimized.budgettracker.app-lock"
    private static let account = "pin-verifier-v1"

    struct Verifier: Equatable {
        let salt: Data
        let hash: Data
    }

    static func hasVerifier() -> Bool {
        (try? load()) != nil
    }

    static func save(verifier: Verifier) throws {
        var payload = Data()
        payload.append(UInt8(verifier.salt.count))
        payload.append(verifier.salt)
        payload.append(verifier.hash)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: payload
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PINKeychainError.saveFailed }
    }

    static func load() throws -> Verifier? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw PINKeychainError.readFailed
        }
        return parsePayload(data)
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PINKeychainError.deleteFailed
        }
    }

    private static func parsePayload(_ data: Data) -> Verifier? {
        guard data.count > 1 else { return nil }
        let saltLength = Int(data[0])
        let saltEnd = 1 + saltLength
        guard saltLength == PINHasher.saltLength,
              data.count == saltEnd + PINHasher.derivedKeyLength else {
            return nil
        }
        let salt = data.subdata(in: 1..<saltEnd)
        let hash = data.subdata(in: saltEnd..<data.count)
        return Verifier(salt: salt, hash: hash)
    }
}
