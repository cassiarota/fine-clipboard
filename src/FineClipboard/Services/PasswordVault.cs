using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using FineClipboard.Models;

namespace FineClipboard.Services;

/// <summary>
/// Encrypted password store. Secrets are AES-256-GCM encrypted with a key derived from the
/// user's master password via PBKDF2 (SHA-256). The master password is never stored — only a
/// random salt and a verifier token. The derived key lives in memory only while unlocked.
/// Blob layout per entry: nonce(12) || tag(16) || ciphertext.
/// </summary>
public sealed class PasswordVault
{
    private const int NonceLen = 12;
    private const int TagLen = 16;
    private const int KeyLen = 32;
    private const int SaltLen = 16;
    private const int Iterations = 200_000;
    private static readonly byte[] CheckToken = Encoding.UTF8.GetBytes("FineClipboard-vault-v1");

    private readonly HistoryStore _store;
    private byte[]? _key;

    public PasswordVault(HistoryStore store) => _store = store;

    public bool IsConfigured => !string.IsNullOrEmpty(_store.GetSetting(HistoryStore.PwSaltKey));
    public bool IsUnlocked => _key != null;

    /// <summary>First-time setup: choose the master password (also unlocks the session).</summary>
    public void SetMasterPassword(string password)
    {
        byte[] salt = RandomNumberGenerator.GetBytes(SaltLen);
        byte[] key = Derive(password, salt);
        _store.SetSetting(HistoryStore.PwSaltKey, Convert.ToBase64String(salt));
        _store.SetSetting(HistoryStore.PwCheckKey, Convert.ToBase64String(Encrypt(key, CheckToken)));
        ReplaceKey(key);
    }

    public bool Unlock(string password)
    {
        byte[]? key = DeriveAndVerify(password);
        if (key == null)
        {
            return false;
        }
        ReplaceKey(key);
        return true;
    }

    public void Lock() => ReplaceKey(null);

    /// <summary>Re-encrypts every entry under a new master password. Returns false if old is wrong.</summary>
    public bool ChangeMasterPassword(string oldPassword, string newPassword)
    {
        byte[]? oldKey = DeriveAndVerify(oldPassword);
        if (oldKey == null)
        {
            return false;
        }

        var decrypted = new List<(long Id, string Name, byte[] Secret)>();
        foreach (var row in _store.GetPasswordRows())
        {
            byte[]? secret = TryDecrypt(oldKey, row.Blob);
            if (secret != null)
            {
                decrypted.Add((row.Id, row.Name, secret));
            }
        }

        byte[] newSalt = RandomNumberGenerator.GetBytes(SaltLen);
        byte[] newKey = Derive(newPassword, newSalt);
        _store.SetSetting(HistoryStore.PwSaltKey, Convert.ToBase64String(newSalt));
        _store.SetSetting(HistoryStore.PwCheckKey, Convert.ToBase64String(Encrypt(newKey, CheckToken)));

        foreach (var item in decrypted)
        {
            _store.UpdatePassword(item.Id, item.Name, Encrypt(newKey, item.Secret));
            CryptographicOperations.ZeroMemory(item.Secret);
        }

        CryptographicOperations.ZeroMemory(oldKey);
        ReplaceKey(newKey);
        return true;
    }

    public List<PasswordEntry> GetEntries() => _store.GetPasswordEntries();

    public long AddEntry(string name, string secret)
    {
        EnsureUnlocked();
        return _store.InsertPassword(name, Encrypt(_key!, Encoding.UTF8.GetBytes(secret)));
    }

    public void UpdateEntry(long id, string name, string secret)
    {
        EnsureUnlocked();
        _store.UpdatePassword(id, name, Encrypt(_key!, Encoding.UTF8.GetBytes(secret)));
    }

    public void DeleteEntry(long id) => _store.DeletePassword(id);

    /// <summary>Decrypts a secret (requires an unlocked vault); null if locked or on failure.</summary>
    public string? Reveal(long id)
    {
        if (_key == null)
        {
            return null;
        }
        byte[]? blob = _store.GetPasswordBlob(id);
        if (blob == null)
        {
            return null;
        }
        byte[]? plain = TryDecrypt(_key, blob);
        if (plain == null)
        {
            return null;
        }
        string secret = Encoding.UTF8.GetString(plain);
        CryptographicOperations.ZeroMemory(plain);
        return secret;
    }

    private void EnsureUnlocked()
    {
        if (_key == null)
        {
            throw new InvalidOperationException("Password vault is locked.");
        }
    }

    private byte[]? DeriveAndVerify(string password)
    {
        string? saltB64 = _store.GetSetting(HistoryStore.PwSaltKey);
        string? checkB64 = _store.GetSetting(HistoryStore.PwCheckKey);
        if (string.IsNullOrEmpty(saltB64) || string.IsNullOrEmpty(checkB64))
        {
            return null;
        }
        byte[] key = Derive(password, Convert.FromBase64String(saltB64));
        byte[]? decrypted = TryDecrypt(key, Convert.FromBase64String(checkB64));
        if (decrypted != null && CryptographicOperations.FixedTimeEquals(decrypted, CheckToken))
        {
            return key;
        }
        CryptographicOperations.ZeroMemory(key);
        return null;
    }

    private void ReplaceKey(byte[]? newKey)
    {
        if (_key != null)
        {
            CryptographicOperations.ZeroMemory(_key);
        }
        _key = newKey;
    }

    private static byte[] Derive(string password, byte[] salt) =>
        Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(password), salt, Iterations, HashAlgorithmName.SHA256, KeyLen);

    private static byte[] Encrypt(byte[] key, byte[] plaintext)
    {
        byte[] nonce = RandomNumberGenerator.GetBytes(NonceLen);
        byte[] cipher = new byte[plaintext.Length];
        byte[] tag = new byte[TagLen];
        using var aes = new AesGcm(key, TagLen);
        aes.Encrypt(nonce, plaintext, cipher, tag);

        byte[] blob = new byte[NonceLen + TagLen + cipher.Length];
        Buffer.BlockCopy(nonce, 0, blob, 0, NonceLen);
        Buffer.BlockCopy(tag, 0, blob, NonceLen, TagLen);
        Buffer.BlockCopy(cipher, 0, blob, NonceLen + TagLen, cipher.Length);
        return blob;
    }

    private static byte[]? TryDecrypt(byte[] key, byte[] blob)
    {
        if (blob.Length < NonceLen + TagLen)
        {
            return null;
        }
        byte[] nonce = blob[..NonceLen];
        byte[] tag = blob[NonceLen..(NonceLen + TagLen)];
        byte[] cipher = blob[(NonceLen + TagLen)..];
        byte[] plain = new byte[cipher.Length];
        try
        {
            using var aes = new AesGcm(key, TagLen);
            aes.Decrypt(nonce, cipher, tag, plain);
            return plain;
        }
        catch (CryptographicException)
        {
            return null;
        }
    }
}
