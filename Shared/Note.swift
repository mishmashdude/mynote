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
        // Never silently throw notes away: keep the unreadable file next to the new one.
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("notes-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: backup)
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

// MARK: - Parsing

enum LineKind: Hashable, Sendable {
    case text
    case bullet
    case todo(checked: Bool)
    case heading
    case blank
}

/// One rendered line of a note. `id` is the line's index in the raw text, which
/// is what toggle intents use to find it again.
struct NoteLine: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: LineKind
    let content: String
    /// The raw marker in front of the content, e.g. "- [ ] ".
    let prefix: String

    var isTodo: Bool { if case .todo = kind { true } else { false } }
    var isChecked: Bool { if case .todo(true) = kind { true } else { false } }
}

/// mynote uses a tiny slice of Markdown:
///   `[ ] task`, `- [ ] task`, `[x] done`   → checkbox
///   `- item`, `* item`, `• item`           → bullet
///   `# Title`                              → heading
enum NoteParser {
    static let characterLimit = 280

    static func rawLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    static func parse(_ text: String) -> [NoteLine] {
        rawLines(text).enumerated().map { parseLine($0.element, index: $0.offset) }
    }

    /// Lines worth showing: drops empty list items and trailing blank lines.
    static func visibleLines(_ text: String) -> [NoteLine] {
        var lines = parse(text).filter { line in
            switch line.kind {
            case .todo, .bullet, .heading:
                return !line.content.trimmingCharacters(in: .whitespaces).isEmpty
            default:
                return true
            }
        }
        while let last = lines.last, last.kind == .blank { lines.removeLast() }
        while let first = lines.first, first.kind == .blank { lines.removeFirst() }
        return lines
    }

    /// Cleans up after editing: removes trailing empty list items and blank lines.
    static func tidy(_ text: String) -> String {
        var lines = rawLines(text)
        while let last = lines.last {
            let parsed = parseLine(last, index: 0)
            let isEmptyItem = (parsed.isTodo || parsed.kind == .bullet) && parsed.content.trimmingCharacters(in: .whitespaces).isEmpty
            if parsed.kind == .blank || isEmptyItem {
                lines.removeLast()
            } else {
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    static func parseLine(_ raw: String, index: Int) -> NoteLine {
        let chars = Array(raw)
        var i = 0
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        if i == chars.count {
            return NoteLine(id: index, kind: .blank, content: "", prefix: raw)
        }

        // Optional bullet marker.
        var j = i
        var hasBullet = false
        if j + 1 < chars.count, "-*•".contains(chars[j]), chars[j + 1] == " " {
            hasBullet = true
            j += 2
            while j < chars.count, chars[j] == " " { j += 1 }
        }

        // Checkbox: "[ ]", "[x]", "[X]", "[]"
        if j < chars.count, chars[j] == "[" {
            var k = j + 1
            var mark: Character? = nil
            if k < chars.count, chars[k] == " " || chars[k] == "x" || chars[k] == "X" {
                mark = chars[k]
                k += 1
            }
            if k < chars.count, chars[k] == "]" {
                k += 1
                if k < chars.count, chars[k] == " " { k += 1 }
                let checked = mark == "x" || mark == "X"
                return NoteLine(id: index, kind: .todo(checked: checked),
                                content: String(chars[k...]), prefix: String(chars[..<k]))
            }
        }

        if hasBullet {
            return NoteLine(id: index, kind: .bullet, content: String(chars[j...]), prefix: String(chars[..<j]))
        }

        // Heading: "# ", "## ", "### "
        if chars[i] == "#" {
            var k = i
            while k < chars.count, chars[k] == "#", k - i < 3 { k += 1 }
            if k < chars.count, chars[k] == " " {
                k += 1
                return NoteLine(id: index, kind: .heading, content: String(chars[k...]), prefix: String(chars[..<k]))
            }
        }

        return NoteLine(id: index, kind: .text, content: String(chars[i...]), prefix: String(chars[..<i]))
    }

    /// Flip the checkbox on `line`. Returns the text unchanged if it isn't a checkbox.
    static func toggle(_ text: String, line index: Int) -> String {
        var lines = rawLines(text)
        guard lines.indices.contains(index) else { return text }
        let parsed = parseLine(lines[index], index: index)
        guard case .todo(let checked) = parsed.kind,
              let open = parsed.prefix.firstIndex(of: "["),
              let close = parsed.prefix.lastIndex(of: "]")
        else { return text }
        let newPrefix = parsed.prefix.replacingCharacters(in: open...close, with: checked ? "[ ]" : "[x]")
        lines[index] = newPrefix + parsed.content
        return lines.joined(separator: "\n")
    }

    static func setAllTodos(_ text: String, checked: Bool) -> String {
        rawLines(text).enumerated().map { offset, raw in
            let parsed = parseLine(raw, index: offset)
            guard case .todo(let isChecked) = parsed.kind, isChecked != checked else { return raw }
            return toggle(raw, line: 0)
        }.joined(separator: "\n")
    }

    static func removeCheckedTodos(_ text: String) -> String {
        rawLines(text).enumerated().filter { offset, raw in
            !parseLine(raw, index: offset).isChecked
        }.map(\.element).joined(separator: "\n")
    }

    /// Characters that count toward the limit: the words you typed plus line
    /// breaks. List markers like "[ ] " are free.
    static func countedLength(_ text: String) -> Int {
        let lines = rawLines(text)
        let content = lines.enumerated().reduce(0) { $0 + parseLine($1.element, index: $1.offset).content.count }
        return content + max(0, lines.count - 1)
    }

    static func progress(_ text: String) -> (done: Int, total: Int) {
        let todos = visibleLines(text).filter(\.isTodo)
        return (todos.filter(\.isChecked).count, todos.count)
    }

    /// Marker to start the next line with when pressing return on a list line.
    static func continuationPrefix(for line: NoteLine) -> String? {
        switch line.kind {
        case .todo:
            guard let open = line.prefix.firstIndex(of: "["), let close = line.prefix.lastIndex(of: "]") else { return nil }
            return line.prefix.replacingCharacters(in: open...close, with: "[ ]")
        case .bullet:
            return line.prefix
        default:
            return nil
        }
    }

    /// A plain-text version that reads well when shared.
    static func shareText(_ text: String) -> String {
        parse(text).map { line in
            switch line.kind {
            case .todo(let checked): (checked ? "☑︎ " : "☐ ") + line.content
            case .bullet: "• " + line.content
            case .heading: line.content.uppercased()
            case .blank: ""
            case .text: line.content
            }
        }.joined(separator: "\n")
    }
}
