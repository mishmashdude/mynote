import CryptoKit
import Foundation

struct Note: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var archivedAt: Date? = nil

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct NoteDocument: Codable, Equatable, Sendable {
    var current: Note = Note()
    var archived: [Note] = []
}

/// The note lives in one small JSON file inside the App Group so the app,
/// widgets and intents all read the same thing.
enum NoteFile {
    static var url: URL { AppGroup.containerURL.appendingPathComponent("notes.json") }

    static func load() -> NoteDocument {
        guard let data = try? Data(contentsOf: url) else { return NoteDocument() }
        if let doc = try? JSONDecoder().decode(NoteDocument.self, from: data) {
            return doc
        }
        // Never silently throw notes away: keep one copy of the unreadable file.
        let digest = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        let backup = url.deletingLastPathComponent().appendingPathComponent("notes-unreadable-\(digest).json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? data.write(to: backup, options: .atomic)
        }
        return NoteDocument()
    }

    /// The document on disk, or nil when there is no file or it can't be read.
    static func loadExisting() -> NoteDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NoteDocument.self, from: data)
    }

    static func save(_ doc: NoteDocument) {
        guard let data = try? JSONEncoder().encode(doc) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
