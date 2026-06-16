import Foundation
import SQLite3
import CryptoKit

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed storage for history, settings, snippets, passwords and lists.
/// Mirrors the Windows `HistoryStore`. All access is on the main thread.
final class Store {
    // Settings keys (mirror the Windows app).
    static let expiryDaysKey = "expiry_days"
    static let exclusionsKey = "exclusions"
    static let hotkeyPopupKey = "hotkey_popup"
    static let hotkeyPlainKey = "hotkey_plain"
    static let soundEnabledKey = "sound_enabled"
    static let maxItemsKey = "max_items"
    static let themeKey = "theme"
    static let popupSizeKey = "popup_size"
    static let firstRunKey = "first_run"
    static let pwSaltKey = "pw_salt"
    static let pwCheckKey = "pw_check"

    private var db: OpaquePointer?

    /// `~/Library/Application Support/FineClipboard/history.db`
    static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FineClipboard", isDirectory: true)
    }

    init() {
        let dir = Store.dataDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("history.db").path
        sqlite3_open(path, &db)
        exec("PRAGMA journal_mode=WAL;")
        migrate()
    }

    deinit { if db != nil { sqlite3_close(db) } }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind INTEGER NOT NULL,
            text TEXT,
            data BLOB,
            preview TEXT NOT NULL DEFAULT '',
            hash TEXT NOT NULL DEFAULT '',
            pinned INTEGER NOT NULL DEFAULT 0,
            list_id INTEGER,
            source TEXT,
            created_at REAL NOT NULL,
            last_used REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS snippets (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, content TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS passwords (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, blob BLOB NOT NULL, sort INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS lists (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS idx_items_hash ON items(hash);
        """)
    }

    // MARK: - low-level helpers

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return nil }
        return stmt
    }

    private func bindText(_ stmt: OpaquePointer?, _ i: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, i, value, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, i) }
    }

    private func bindBlob(_ stmt: OpaquePointer?, _ i: Int32, _ value: Data?) {
        if let value, !value.isEmpty {
            _ = value.withUnsafeBytes { sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32(value.count), SQLITE_TRANSIENT) }
        } else { sqlite3_bind_null(stmt, i) }
    }

    private func columnText(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ i: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, i) else { return nil }
        let n = Int(sqlite3_column_bytes(stmt, i))
        if n == 0 { return nil }
        return Data(bytes: ptr, count: n)
    }

    // MARK: - settings

    func setting(_ key: String) -> String? {
        let stmt = prepare("SELECT value FROM meta WHERE key=?")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key)
        if sqlite3_step(stmt) == SQLITE_ROW { return columnText(stmt, 0) }
        return nil
    }

    func setSetting(_ key: String, _ value: String) {
        let stmt = prepare("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key); bindText(stmt, 2, value)
        sqlite3_step(stmt)
    }

    // MARK: - items

    private func rowToItem(_ stmt: OpaquePointer?) -> ClipItem {
        ClipItem(
            id: sqlite3_column_int64(stmt, 0),
            kind: ClipKind(rawValue: Int(sqlite3_column_int(stmt, 1))) ?? .text,
            text: columnText(stmt, 2),
            data: columnBlob(stmt, 3),
            preview: columnText(stmt, 4) ?? "",
            pinned: sqlite3_column_int(stmt, 5) != 0,
            listId: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 6),
            source: columnText(stmt, 7),
            createdAt: sqlite3_column_double(stmt, 8),
            lastUsed: sqlite3_column_double(stmt, 9))
    }

    private static let itemCols = "id,kind,text,data,preview,pinned,list_id,source,created_at,last_used"

    private func query(_ where_: String, bind: ((OpaquePointer?) -> Void)? = nil, limit: Int? = nil) -> [ClipItem] {
        var sql = "SELECT \(Store.itemCols) FROM items"
        if !where_.isEmpty { sql += " WHERE \(where_)" }
        sql += " ORDER BY pinned DESC, last_used DESC"
        if let limit { sql += " LIMIT \(limit)" }
        let stmt = prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind?(stmt)
        var out: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(rowToItem(stmt)) }
        return out
    }

    func allItems(limit: Int = 1000) -> [ClipItem] { query("", limit: limit) }
    func itemsByKind(_ kind: ClipKind, limit: Int = 1000) -> [ClipItem] {
        query("kind=?", bind: { sqlite3_bind_int($0, 1, Int32(kind.rawValue)) }, limit: limit)
    }
    func pinnedItems() -> [ClipItem] { query("pinned=1") }
    func itemsByList(_ listId: Int64) -> [ClipItem] {
        query("list_id=?", bind: { sqlite3_bind_int64($0, 1, listId) })
    }

    func searchItems(_ term: String, limit: Int = 500) -> [ClipItem] {
        let stmt = prepare("SELECT \(Store.itemCols) FROM items WHERE text LIKE ? OR preview LIKE ? ORDER BY pinned DESC, last_used DESC LIMIT \(limit)")
        defer { sqlite3_finalize(stmt) }
        let like = "%\(term)%"
        bindText(stmt, 1, like); bindText(stmt, 2, like)
        var out: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(rowToItem(stmt)) }
        return out
    }

    /// Hash used for de-duplication.
    static func hash(kind: ClipKind, text: String?, data: Data?) -> String {
        switch kind {
        case .text: return "t:" + (text ?? "")
        case .files: return "f:" + (text ?? "")
        case .image:
            let digest = SHA256.hash(data: data ?? Data())
            return "i:" + digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Insert a new item, or if identical content already exists bump it to the top.
    @discardableResult
    func add(kind: ClipKind, text: String?, data: Data?, preview: String, source: String?) -> Int64 {
        let h = Store.hash(kind: kind, text: text, data: data)
        let now = Date().timeIntervalSince1970
        // De-dup: bump existing identical content to the top.
        if let existing = prepare("SELECT id FROM items WHERE hash=? LIMIT 1") {
            defer { sqlite3_finalize(existing) }
            bindText(existing, 1, h)
            if sqlite3_step(existing) == SQLITE_ROW {
                let id = sqlite3_column_int64(existing, 0)
                touch(id)
                return id
            }
        }
        let stmt = prepare("INSERT INTO items(kind,text,data,preview,hash,pinned,list_id,source,created_at,last_used) VALUES(?,?,?,?,?,0,NULL,?,?,?)")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(kind.rawValue))
        bindText(stmt, 2, text)
        bindBlob(stmt, 3, data)
        bindText(stmt, 4, preview)
        bindText(stmt, 5, h)
        bindText(stmt, 6, source)
        sqlite3_bind_double(stmt, 7, now)
        sqlite3_bind_double(stmt, 8, now)
        sqlite3_step(stmt)
        return sqlite3_last_insert_rowid(db)
    }

    func touch(_ id: Int64) {
        let stmt = prepare("UPDATE items SET last_used=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func mostRecentText() -> ClipItem? {
        query("kind=?", bind: { sqlite3_bind_int($0, 1, Int32(ClipKind.text.rawValue)) }, limit: 1).first
    }

    func setPinned(_ id: Int64, _ pinned: Bool) {
        let stmt = prepare("UPDATE items SET pinned=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func delete(_ id: Int64) {
        let stmt = prepare("DELETE FROM items WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    func assignToList(_ id: Int64, listId: Int64?) {
        let stmt = prepare("UPDATE items SET list_id=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        if let listId { sqlite3_bind_int64(stmt, 1, listId) } else { sqlite3_bind_null(stmt, 1) }
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func count() -> Int {
        let stmt = prepare("SELECT COUNT(*) FROM items")
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    func clear(keepPinned: Bool) {
        exec(keepPinned ? "DELETE FROM items WHERE pinned=0" : "DELETE FROM items")
    }

    /// Remove non-pinned, non-listed items older than `days` (0 = never).
    func purgeExpired(days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
        let stmt = prepare("DELETE FROM items WHERE pinned=0 AND list_id IS NULL AND last_used < ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)
        sqlite3_step(stmt)
    }

    /// Keep at most `max` non-pinned, non-listed items.
    func trimOverflow(max: Int) {
        guard max > 0 else { return }
        let stmt = prepare("""
        DELETE FROM items WHERE id IN (
            SELECT id FROM items WHERE pinned=0 AND list_id IS NULL
            ORDER BY last_used DESC LIMIT -1 OFFSET ?)
        """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(max))
        sqlite3_step(stmt)
    }

    // MARK: - snippets

    func snippets() -> [Snippet] {
        let stmt = prepare("SELECT id,name,content FROM snippets ORDER BY sort, id")
        defer { sqlite3_finalize(stmt) }
        var out: [Snippet] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Snippet(id: sqlite3_column_int64(stmt, 0), name: columnText(stmt, 1) ?? "", content: columnText(stmt, 2) ?? ""))
        }
        return out
    }

    func addSnippet(name: String, content: String) {
        let stmt = prepare("INSERT INTO snippets(name,content,sort) VALUES(?,?,(SELECT COALESCE(MAX(sort),0)+1 FROM snippets))")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name); bindText(stmt, 2, content)
        sqlite3_step(stmt)
    }

    func updateSnippet(_ id: Int64, name: String, content: String) {
        let stmt = prepare("UPDATE snippets SET name=?, content=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name); bindText(stmt, 2, content); sqlite3_bind_int64(stmt, 3, id)
        sqlite3_step(stmt)
    }

    func deleteSnippet(_ id: Int64) {
        let stmt = prepare("DELETE FROM snippets WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    // MARK: - passwords (blobs are encrypted by Vault)

    func passwordEntries() -> [PasswordEntry] {
        let stmt = prepare("SELECT id,name FROM passwords ORDER BY sort, id")
        defer { sqlite3_finalize(stmt) }
        var out: [PasswordEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(PasswordEntry(id: sqlite3_column_int64(stmt, 0), name: columnText(stmt, 1) ?? ""))
        }
        return out
    }

    func passwordRows() -> [(id: Int64, name: String, blob: Data)] {
        let stmt = prepare("SELECT id,name,blob FROM passwords ORDER BY sort, id")
        defer { sqlite3_finalize(stmt) }
        var out: [(Int64, String, Data)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((sqlite3_column_int64(stmt, 0), columnText(stmt, 1) ?? "", columnBlob(stmt, 2) ?? Data()))
        }
        return out
    }

    func passwordBlob(_ id: Int64) -> Data? {
        let stmt = prepare("SELECT blob FROM passwords WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? columnBlob(stmt, 0) : nil
    }

    func insertPassword(name: String, blob: Data) {
        let stmt = prepare("INSERT INTO passwords(name,blob,sort) VALUES(?,?,(SELECT COALESCE(MAX(sort),0)+1 FROM passwords))")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name); bindBlob(stmt, 2, blob)
        sqlite3_step(stmt)
    }

    func updatePassword(_ id: Int64, name: String, blob: Data) {
        let stmt = prepare("UPDATE passwords SET name=?, blob=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name); bindBlob(stmt, 2, blob); sqlite3_bind_int64(stmt, 3, id)
        sqlite3_step(stmt)
    }

    func updatePasswordBlob(_ id: Int64, blob: Data) {
        let stmt = prepare("UPDATE passwords SET blob=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bindBlob(stmt, 1, blob); sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func deletePassword(_ id: Int64) {
        let stmt = prepare("DELETE FROM passwords WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    // MARK: - lists

    func lists() -> [ClipList] {
        let stmt = prepare("SELECT id,name FROM lists ORDER BY sort, id")
        defer { sqlite3_finalize(stmt) }
        var out: [ClipList] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(ClipList(id: sqlite3_column_int64(stmt, 0), name: columnText(stmt, 1) ?? ""))
        }
        return out
    }

    @discardableResult
    func addList(name: String) -> Int64 {
        let stmt = prepare("INSERT INTO lists(name,sort) VALUES(?,(SELECT COALESCE(MAX(sort),0)+1 FROM lists))")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name)
        sqlite3_step(stmt)
        return sqlite3_last_insert_rowid(db)
    }

    func renameList(_ id: Int64, name: String) {
        let stmt = prepare("UPDATE lists SET name=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name); sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func deleteList(_ id: Int64) {
        let clear = prepare("UPDATE items SET list_id=NULL WHERE list_id=?")
        sqlite3_bind_int64(clear, 1, id); sqlite3_step(clear); sqlite3_finalize(clear)
        let stmt = prepare("DELETE FROM lists WHERE id=?")
        sqlite3_bind_int64(stmt, 1, id); sqlite3_step(stmt); sqlite3_finalize(stmt)
    }
}
