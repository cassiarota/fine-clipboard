import Foundation
import CryptoKit
import CommonCrypto
import CArgon2

/// Encrypted password vault — AES-256-GCM with an **Argon2id** derived key (new vaults);
/// legacy PBKDF2-SHA256/200k vaults stay readable and upgrade to Argon2id on the next
/// master-password change. The master password is never stored; only a random salt, a KDF
/// tag and an encrypted check token are persisted. Mirrors the Windows `PasswordVault`.
final class Vault {
    private static let keyLen = 32
    private static let saltLen = 16
    private static let checkToken = "FineClipboard-vault-v1".data(using: .utf8)!

    // Legacy PBKDF2.
    private static let pbkdf2Iterations = 200_000
    // Argon2id parameters (memory-hard): 64 MiB, 3 passes, 4 lanes.
    private static let kdfArgon2 = "argon2id"
    private static let a2TimeCost: UInt32 = 3
    private static let a2MemoryKiB: UInt32 = 65_536
    private static let a2Lanes: UInt32 = 4

    private let store: Store
    private var key: SymmetricKey?

    init(_ store: Store) { self.store = store }

    var isConfigured: Bool { (store.setting(Store.pwSaltKey) ?? "").isEmpty == false }
    var isUnlocked: Bool { key != nil }

    func lock() { key = nil }

    // MARK: - master password

    func setMasterPassword(_ password: String) {
        let salt = Vault.randomSalt()
        let k = Vault.deriveArgon2(password, salt: salt)
        store.setSetting(Store.pwSaltKey, salt.base64EncodedString())
        store.setSetting(Store.pwKdfKey, Vault.kdfArgon2)
        store.setSetting(Store.pwCheckKey, Vault.encrypt(Vault.checkToken, key: k).base64EncodedString())
        key = k
    }

    @discardableResult
    func unlock(_ password: String) -> Bool {
        guard let saltB64 = store.setting(Store.pwSaltKey), let salt = Data(base64Encoded: saltB64),
              let checkB64 = store.setting(Store.pwCheckKey), let check = Data(base64Encoded: checkB64) else {
            return false
        }
        let k = derive(password, salt: salt)
        guard let decrypted = Vault.decrypt(check, key: k), decrypted == Vault.checkToken else { return false }
        key = k
        return true
    }

    /// Derive using whichever KDF this vault was created with (defaults to legacy PBKDF2).
    private func derive(_ password: String, salt: Data) -> SymmetricKey {
        if store.setting(Store.pwKdfKey) == Vault.kdfArgon2 { return Vault.deriveArgon2(password, salt: salt) }
        return Vault.derivePBKDF2(password, salt: salt)
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
        let salt = Vault.randomSalt()
        let newKey = Vault.deriveArgon2(new, salt: salt) // re-encrypt under Argon2id
        for (id, plain) in plaintexts {
            store.updatePasswordBlob(id, blob: Vault.encrypt(plain, key: newKey))
        }
        store.setSetting(Store.pwSaltKey, salt.base64EncodedString())
        store.setSetting(Store.pwKdfKey, Vault.kdfArgon2)
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

    private static func randomSalt() -> Data {
        var salt = Data(count: saltLen)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLen, $0.baseAddress!) }
        return salt
    }

    /// Argon2id (memory-hard) via the vendored PHC reference implementation.
    private static func deriveArgon2(_ password: String, salt: Data) -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: keyLen)
        let pw = [UInt8](password.utf8)
        let saltBytes = [UInt8](salt)
        let rc = argon2id_hash_raw(a2TimeCost, a2MemoryKiB, a2Lanes,
                                   pw, pw.count, saltBytes, saltBytes.count, &out, keyLen)
        precondition(rc == 0, "argon2id_hash_raw failed: \(rc)")
        return SymmetricKey(data: Data(out))
    }

    /// Legacy PBKDF2-SHA256 (kept so pre-Argon2id vaults still open).
    private static func derivePBKDF2(_ password: String, salt: Data) -> SymmetricKey {
        var derived = Data(count: keyLen)
        let pw = Data(password.utf8)
        _ = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                pw.withUnsafeBytes { pwPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.bindMemory(to: Int8.self).baseAddress, pw.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(pbkdf2Iterations),
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
