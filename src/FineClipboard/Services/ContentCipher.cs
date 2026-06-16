using System;
using System.Security.Cryptography;
using System.Text;

namespace FineClipboard.Services;

/// <summary>
/// Transparent at-rest encryption for clipboard history content. A random 256-bit key is
/// sealed with DPAPI (<see cref="DataProtectionScope.CurrentUser"/>) so only this Windows
/// account can read it — no password prompt, so background capture stays always-on.
/// Content uses AES-256-GCM; the dedup hash is a keyed HMAC (deterministic but not
/// reversible to the content).
/// </summary>
internal sealed class ContentCipher
{
    private const int NonceLen = 12;
    private const int TagLen = 16;

    private readonly byte[] _key;
    private readonly byte[] _macKey;

    private ContentCipher(byte[] key)
    {
        _key = key;
        _macKey = SHA256.HashData(Concat(key, Encoding.UTF8.GetBytes("fineclipboard-hash")));
    }

    /// <summary>Loads the DPAPI-sealed key from the store, creating one on first use.</summary>
    public static ContentCipher Load(HistoryStore store)
    {
        string? stored = store.GetSetting(HistoryStore.DbKeyKey);
        if (!string.IsNullOrEmpty(stored))
        {
            try
            {
                byte[] key = ProtectedData.Unprotect(Convert.FromBase64String(stored), null, DataProtectionScope.CurrentUser);
                return new ContentCipher(key);
            }
            catch
            {
                // Unreadable (e.g. copied from another account) — regenerate below.
            }
        }
        byte[] fresh = RandomNumberGenerator.GetBytes(32);
        byte[] protectedKey = ProtectedData.Protect(fresh, null, DataProtectionScope.CurrentUser);
        store.SetSetting(HistoryStore.DbKeyKey, Convert.ToBase64String(protectedKey));
        return new ContentCipher(fresh);
    }

    public string? EncryptText(string? value) =>
        value == null ? null : Convert.ToBase64String(Encrypt(Encoding.UTF8.GetBytes(value)));

    public string? DecryptText(string? stored)
    {
        if (string.IsNullOrEmpty(stored))
        {
            return null;
        }
        try
        {
            return Encoding.UTF8.GetString(Decrypt(Convert.FromBase64String(stored)));
        }
        catch
        {
            return null;
        }
    }

    public byte[]? EncryptBlob(byte[]? value) =>
        value == null || value.Length == 0 ? null : Encrypt(value);

    public byte[]? DecryptBlob(byte[]? blob)
    {
        if (blob == null || blob.Length == 0)
        {
            return null;
        }
        try
        {
            return Decrypt(blob);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Keyed, deterministic hash for de-duplication.</summary>
    public string DedupHash(string canonical) =>
        Convert.ToHexString(HMACSHA256.HashData(_macKey, Encoding.UTF8.GetBytes(canonical)));

    private byte[] Encrypt(byte[] plain)
    {
        byte[] nonce = RandomNumberGenerator.GetBytes(NonceLen);
        byte[] cipher = new byte[plain.Length];
        byte[] tag = new byte[TagLen];
        using var aes = new AesGcm(_key, TagLen);
        aes.Encrypt(nonce, plain, cipher, tag);

        byte[] blob = new byte[NonceLen + TagLen + cipher.Length];
        Buffer.BlockCopy(nonce, 0, blob, 0, NonceLen);
        Buffer.BlockCopy(tag, 0, blob, NonceLen, TagLen);
        Buffer.BlockCopy(cipher, 0, blob, NonceLen + TagLen, cipher.Length);
        return blob;
    }

    private byte[] Decrypt(byte[] blob)
    {
        byte[] nonce = new byte[NonceLen];
        byte[] tag = new byte[TagLen];
        Buffer.BlockCopy(blob, 0, nonce, 0, NonceLen);
        Buffer.BlockCopy(blob, NonceLen, tag, 0, TagLen);
        byte[] cipher = new byte[blob.Length - NonceLen - TagLen];
        Buffer.BlockCopy(blob, NonceLen + TagLen, cipher, 0, cipher.Length);

        byte[] plain = new byte[cipher.Length];
        using var aes = new AesGcm(_key, TagLen);
        aes.Decrypt(nonce, cipher, tag, plain);
        return plain;
    }

    private static byte[] Concat(byte[] a, byte[] b)
    {
        byte[] r = new byte[a.Length + b.Length];
        Buffer.BlockCopy(a, 0, r, 0, a.Length);
        Buffer.BlockCopy(b, 0, r, a.Length, b.Length);
        return r;
    }
}
