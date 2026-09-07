import CryptoKit
import Foundation
import Security

/// AES-GCM encryption for on-disk storage (history.json, snippets.json), with
/// the symmetric key held in the macOS Keychain rather than embedded in the
/// binary or written alongside the data — meaningfully raises the bar above
/// plaintext JSON for a clipboard manager that can hold sensitive content.
enum SecureStorage {
    private static let keychainService = "com.hzla.paste.storagekey"
    private static let keychainAccount = "default"

    static func encrypt(_ data: Data) -> Data? {
        guard let sealed = try? AES.GCM.seal(data, using: key()) else { return nil }
        return sealed.combined
    }

    static func decrypt(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key())
    }

    private static func key() -> SymmetricKey {
        if let existing = readKeyFromKeychain() { return existing }
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        return newKey
    }

    private static func readKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary) // avoid duplicate-item errors on regeneration
        SecItemAdd(query as CFDictionary, nil)
    }
}
