import Foundation
import CryptoKit
import CommonCrypto

/// Encrypted password vault — AES-256-GCM with a PBKDF2-SHA256 (200k) derived key.
/// The master password is never stored; only a random salt and an encrypted check token
/// are persisted. Mirrors the Windows `PasswordVault`.
final class Vault {
    private static let iterations = 200_000
    private static let keyLen = 32
    private static let saltLen = 16
    private static let checkToken = "FineClipboard-vault-v1".data(using: .utf8)!

    private let store: Store
    private var key: SymmetricKey?

    init(_ store: Store) { self.store = store }

    var isConfigured: Bool { (store.setting(Store.pwSaltKey) ?? "").isEmpty == false }
    var isUnlocked: Bool { key != nil }

    func lock() { key = nil }

    // MARK: - master password

    func setMasterPassword(_ password: String) {
        var salt = Data(count: Vault.saltLen)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, Vault.saltLen, $0.baseAddress!) }
        let k = Vault.deriveKey(password, salt: salt)
        store.setSetting(Store.pwSaltKey, salt.base64EncodedString())
        store.setSetting(Store.pwCheckKey, Vault.encrypt(Vault.checkToken, key: k).base64EncodedString())
        key = k
    }

    @discardableResult
    func unlock(_ password: String) -> Bool {
        guard let saltB64 = store.setting(Store.pwSaltKey), let salt = Data(base64Encoded: saltB64),
              let checkB64 = store.setting(Store.pwCheckKey), let check = Data(base64Encoded: checkB64) else {
            return false
        }
        let k = Vault.deriveKey(password, salt: salt)
        guard let decrypted = Vault.decrypt(check, key: k), decrypted == Vault.checkToken else { return false }
        key = k
        return true
    }

    /// Verify the old password, re-encrypt every stored secret under a new key, then swap.
    @discardableResult
    func changeMasterPassword(old: String, new: String) -> Bool {
        guard unlock(old), let oldKey = key else { return false }
        // Decrypt all secrets with the old key first.
        var plaintexts: [(Int64, Data)] = []
        for row in store.passwordRows() {
            guard let plain = Vault.decrypt(row.blob, key: oldKey) else { return false }
            plaintexts.append((row.id, plain))
        }
        var salt = Data(count: Vault.saltLen)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, Vault.saltLen, $0.baseAddress!) }
        let newKey = Vault.deriveKey(new, salt: salt)
        for (id, plain) in plaintexts {
            store.updatePasswordBlob(id, blob: Vault.encrypt(plain, key: newKey))
        }
        store.setSetting(Store.pwSaltKey, salt.base64EncodedString())
        store.setSetting(Store.pwCheckKey, Vault.encrypt(Vault.checkToken, key: newKey).base64EncodedString())
        key = newKey
        return true
    }

    // MARK: - entries

    func entries() -> [PasswordEntry] { store.passwordEntries() }

    func addEntry(name: String, secret: String) {
        guard let key else { return }
        store.insertPassword(name: name, blob: Vault.encrypt(Data(secret.utf8), key: key))
    }

    func updateEntry(_ id: Int64, name: String, secret: String) {
        guard let key else { return }
        store.updatePassword(id, name: name, blob: Vault.encrypt(Data(secret.utf8), key: key))
    }

    func deleteEntry(_ id: Int64) { store.deletePassword(id) }

    /// Decrypt and return a stored secret, or nil if locked / corrupt.
    func reveal(_ id: Int64) -> String? {
        guard let key, let blob = store.passwordBlob(id), let plain = Vault.decrypt(blob, key: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: - crypto primitives

    private static func deriveKey(_ password: String, salt: Data) -> SymmetricKey {
        var derived = Data(count: keyLen)
        let pw = Data(password.utf8)
        _ = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                pw.withUnsafeBytes { pwPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.bindMemory(to: Int8.self).baseAddress, pw.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress, keyLen)
                }
            }
        }
        return SymmetricKey(data: derived)
    }

    /// Returns nonce(12) || ciphertext || tag(16).
    private static func encrypt(_ plain: Data, key: SymmetricKey) -> Data {
        let sealed = try! AES.GCM.seal(plain, using: key)
        return sealed.combined!
    }

    private static func decrypt(_ blob: Data, key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: blob) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}
