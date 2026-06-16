import Foundation

/// The three content kinds we capture, mirroring the Windows app.
enum ClipKind: Int {
    case text = 0
    case image = 1
    case files = 2
}

/// One clipboard history entry.
struct ClipItem: Identifiable, Equatable {
    var id: Int64
    var kind: ClipKind
    /// Text content (text kind) or newline-joined paths (files kind); nil for images.
    var text: String?
    /// PNG bytes for image kind; nil otherwise.
    var data: Data?
    /// Short display preview.
    var preview: String
    var pinned: Bool
    var listId: Int64?
    /// Frontmost app name when captured (for exclusion rules).
    var source: String?
    var createdAt: Double
    var lastUsed: Double

    static func == (a: ClipItem, b: ClipItem) -> Bool { a.id == b.id }
}

struct Snippet: Identifiable, Equatable {
    var id: Int64
    var name: String
    var content: String
}

struct PasswordEntry: Identifiable, Equatable {
    var id: Int64
    var name: String
}

struct ClipList: Identifiable, Equatable {
    var id: Int64
    var name: String
}
