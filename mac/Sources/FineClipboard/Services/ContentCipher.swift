import Foundation
import CryptoKit

/// Transparent at-rest encryption for clipboard history content. The key is random and
/// kept in the Keychain (see `Keychain`); the user never types anything. Text/blobs are
/// AES-256-GCM (nonce||tag||ciphertext); the dedup hash is a keyed HMAC so it stays
/// deterministic but cannot be brute-forced back to the content.
final class ContentCipher {
    private let key: SymmetricKey
    private let macKey: SymmetricKey

    init(keyData: Data) {
        key = SymmetricKey(data: keyData)
        // Separate, derived key for the dedup HMAC.
        macKey = SymmetricKey(data: Data(SHA256.hash(data: keyData + Data("fineclipboard-hash".utf8))))
    }

    func encryptText(_ s: String?) -> String? {
        guard let s else { return nil }
        return seal(Data(s.utf8)).base64EncodedString()
    }

    func decryptText(_ stored: String?) -> String? {
        guard let stored, let blob = Data(base64Encoded: stored), let plain = open(blob) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    func encryptBlob(_ d: Data?) -> Data? {
        guard let d, !d.isEmpty else { return nil }
        return seal(d)
    }

    func decryptBlob(_ blob: Data?) -> Data? {
        guard let blob, !blob.isEmpty else { return nil }
        return open(blob)
    }

    /// Keyed, deterministic hash for de-duplication.
    func dedupHash(_ canonical: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: macKey)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    private func seal(_ plain: Data) -> Data {
        (try? AES.GCM.seal(plain, using: key).combined) ?? Data()
    }

    private func open(_ blob: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: blob) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}
