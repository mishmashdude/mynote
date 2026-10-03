import Foundation

// MARK: - Lines

enum LineKind: Hashable, Sendable {
    case text
    /// Level 1 to 3 ("#", "##", "###"; deeper levels show as level 3).
    case heading(Int)
    case bullet
    /// The number as typed. `NoteLine.ordinal` holds the number to show.
    case numbered(Int)
    case todo(checked: Bool)
    case quote
    case divider
    case blank
}

/// One line of a note. `id` is the line's index in the raw text, which is
/// what toggle intents use to find it again.
struct NoteLine: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: LineKind
    /// The text after the marker. It can still hold inline Markdown such as `**bold**`.
    let content: String
    /// Everything in front of the content: indentation plus the marker, e.g. "  - [ ] ".
    let prefix: String
    /// How deeply a list item is nested (0 = not nested).
    var indent: Int = 0
    /// For numbered items: the number to show. "1. 1. 1." reads 1, 2, 3.
    var ordinal: Int? = nil

    var isTodo: Bool { if case .todo = kind { true } else { false } }
    var isChecked: Bool { if case .todo(true) = kind { true } else { false } }
    var isHeading: Bool { if case .heading = kind { true } else { false } }
    var isListItem: Bool {
        switch kind {
        case .bullet, .numbered, .todo: true
        default: false
        }
    }

    /// The words a reader sees, without any Markdown symbols.
    var plainContent: String { InlineMarkdown.plain(content) }
}

/// mynote notes are Markdown, one block per line:
///   `# Title`, `## Section`, `### Small`        → headings
///   `- item`, `* item`, `+ item`, `• item`      → bullets (indent with two spaces to nest)
///   `1. item`, `1) item`                        → numbered items
///   `- [ ] task`, `- [x] done`, `[ ] task`      → checkboxes
///   `> words`                                   → quote
///   `---`, `***`, `___`                         → divider
/// Inside a line: `**bold**`, `*italic*`, `~~strike~~`, `==highlight==`, `` `code` `` and `[links](https://…)`.
enum NoteParser {
    static let characterLimit = 280
    static let maxIndent = 3

    static func rawLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    static func parse(_ text: String) -> [NoteLine] {
        number(rawLines(text).enumerated().map { parseLine($0.element, index: $0.offset) })
    }

    /// Lines worth showing: drops empty items, repeated blank lines and blank lines at either end.
    static func visibleLines(_ text: String) -> [NoteLine] {
        var lines: [NoteLine] = []
        for line in parse(text) {
            if isEmptyItem(line) { continue }
            if line.kind == .blank, lines.last?.kind == .blank { continue }
            lines.append(line)
        }
        while let last = lines.last, last.kind == .blank { lines.removeLast() }
        while let first = lines.first, first.kind == .blank { lines.removeFirst() }
        return number(lines)
    }

    /// A list item, quote or heading with nothing written in it yet.
    static func isEmptyItem(_ line: NoteLine) -> Bool {
        guard line.isListItem || line.isHeading || line.kind == .quote else { return false }
        return line.plainContent.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Cleans up after editing: removes empty formatting pairs left by the formatting bar
    /// (e.g. a lone "****", which would read as a divider), then trailing empty items and blank lines.
    static func tidy(_ text: String) -> String {
        var lines = rawLines(text).map { raw -> String in
            let line = parseLine(raw, index: 0)
            let pairs: Set<String> = ["****", "**", "~~~~", "====", "``", "______", "__"]
            guard line.kind == .divider || line.kind == .text || line.isListItem || line.isHeading || line.kind == .quote,
                  pairs.contains(line.kind == .divider ? raw.trimmingCharacters(in: .whitespaces) : line.content)
            else { return raw }
            return line.kind == .divider || line.kind == .text ? "" : line.prefix
        }
        while let last = lines.last {
            let parsed = parseLine(last, index: 0)
            if parsed.kind == .blank || isEmptyItem(parsed) {
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
        var columns = 0
        while i < chars.count, chars[i] == " " || chars[i] == "\t" {
            columns += chars[i] == "\t" ? 2 : 1
            i += 1
        }
        if i == chars.count {
            return NoteLine(id: index, kind: .blank, content: "", prefix: raw)
        }
        let indent = min(columns / 2, maxIndent)

        func item(_ kind: LineKind, contentFrom start: Int) -> NoteLine {
            NoteLine(id: index, kind: kind, content: String(chars[start...]), prefix: String(chars[..<start]), indent: indent)
        }

        if isDivider(chars[i...]) {
            return NoteLine(id: index, kind: .divider, content: "", prefix: raw)
        }

        // Heading: "# " up to "###### ".
        if chars[i] == "#" {
            var k = i
            while k < chars.count, chars[k] == "#" { k += 1 }
            let level = k - i
            if level <= 6, k < chars.count, chars[k] == " " {
                return NoteLine(id: index, kind: .heading(min(level, 3)), content: String(chars[(k + 1)...]),
                                prefix: String(chars[...k]))
            }
        }

        // Quote: "> words".
        if chars[i] == ">" {
            var k = i + 1
            if k < chars.count, chars[k] == " " { k += 1 }
            return NoteLine(id: index, kind: .quote, content: String(chars[k...]), prefix: String(chars[..<k]))
        }

        // Optional bullet marker.
        var j = i
        var hasBullet = false
        if j + 1 < chars.count, "-*+•".contains(chars[j]), chars[j + 1] == " " {
            hasBullet = true
            j += 2
            while j < chars.count, chars[j] == " " { j += 1 }
        }

        // Checkbox: "[ ]", "[x]", "[X]", "[]".
        if j < chars.count, chars[j] == "[" {
            var k = j + 1
            var mark: Character? = nil
            if k < chars.count, chars[k] == " " || chars[k] == "x" || chars[k] == "X" {
                mark = chars[k]
                k += 1
            }
            // "[x](https://…)" is a link, not a ticked box.
            if k < chars.count, chars[k] == "]", !(k + 1 < chars.count && chars[k + 1] == "(") {
                k += 1
                if k < chars.count, chars[k] == " " { k += 1 }
                return item(.todo(checked: mark == "x" || mark == "X"), contentFrom: k)
            }
        }

        if hasBullet {
            return item(.bullet, contentFrom: j)
        }

        // Numbered: "1. " or "1) ".
        if chars[i].isASCII, chars[i].isNumber {
            var k = i
            while k < chars.count, k - i < 9, chars[k].isASCII, chars[k].isNumber { k += 1 }
            if k + 1 < chars.count, chars[k] == "." || chars[k] == ")", chars[k + 1] == " " {
                var start = k + 2
                while start < chars.count, chars[start] == " " { start += 1 }
                return item(.numbered(Int(String(chars[i..<k])) ?? 1), contentFrom: start)
            }
        }

        return NoteLine(id: index, kind: .text, content: String(chars[i...]), prefix: String(chars[..<i]))
    }

    /// Three or more of the same `-`, `*` or `_`, and nothing else.
    private static func isDivider(_ chars: ArraySlice<Character>) -> Bool {
        let marks = chars.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// Works out the number to show for each numbered item: a list counts on from
    /// its first number, nested lists count on their own, and anything that isn't
    /// part of a list starts the count again.
    static func number(_ lines: [NoteLine]) -> [NoteLine] {
        var next: [Int: Int] = [:]
        return lines.map { line in
            var line = line
            switch line.kind {
            case .numbered(let typed):
                let value = next[line.indent] ?? typed
                line.ordinal = value
                next = next.filter { $0.key < line.indent }
                next[line.indent] = value + 1
            case .bullet, .todo:
                next = next.filter { $0.key < line.indent }
            case .blank:
                break
            default:
                next.removeAll()
            }
            return line
        }
    }

    // MARK: Checkboxes

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

    static func progress(_ text: String) -> (done: Int, total: Int) {
        let todos = visibleLines(text).filter(\.isTodo)
        return (todos.filter(\.isChecked).count, todos.count)
    }

    // MARK: Counting and sharing

    /// Characters that count toward the limit: the words you can see plus line
    /// breaks. Markdown symbols like "- [ ] " or "**" are free.
    static func countedLength(_ text: String) -> Int {
        let lines = rawLines(text)
        let content = lines.enumerated().reduce(0) { $0 + parseLine($1.element, index: $1.offset).plainContent.count }
        return content + max(0, lines.count - 1)
    }

    /// Marker to start the next line with when pressing return on a list line.
    static func continuationPrefix(for line: NoteLine) -> String? {
        switch line.kind {
        case .todo:
            guard let open = line.prefix.firstIndex(of: "["), let close = line.prefix.lastIndex(of: "]") else { return nil }
            return line.prefix.replacingCharacters(in: open...close, with: "[ ]")
        case .bullet, .quote:
            return line.prefix
        case .numbered(let typed):
            let leading = line.prefix.prefix { $0 == " " || $0 == "\t" }
            let style = line.prefix.contains(")") ? ")" : "."
            return "\(leading)\(typed + 1)\(style) "
        default:
            return nil
        }
    }

    /// The note as VoiceOver should read it: just the words, with ticked items marked done.
    static func spokenText(_ text: String) -> String {
        visibleLines(text).compactMap { line in
            switch line.kind {
            case .blank, .divider: return nil
            case .todo(let checked): return line.plainContent + (checked ? ", done" : "")
            default: return line.plainContent
            }
        }.joined(separator: ". ")
    }

    /// The note as sent to the Live Activity, whose data has to stay under 4 KB. Links can't
    /// be tapped there, so their addresses are dropped; anything still too long is cut at a line.
    static func compactForLiveActivity(_ text: String, byteLimit: Int = 3_000) -> String {
        var compact = text.replacingOccurrences(of: #"\]\([^)\s]*\)"#, with: "](#)", options: .regularExpression)
        while compact.utf8.count > byteLimit, let cut = compact.lastIndex(of: "\n") {
            compact = String(compact[..<cut])
        }
        if compact.utf8.count > byteLimit {
            compact = String(decoding: compact.utf8.prefix(byteLimit), as: UTF8.self)
        }
        return compact
    }

    /// A plain-text version that reads well when shared.
    static func shareText(_ text: String) -> String {
        parse(text).map { line in
            let pad = String(repeating: "  ", count: line.indent)
            let words = line.plainContent
            switch line.kind {
            case .todo(let checked): return pad + (checked ? "☑︎ " : "☐ ") + words
            case .bullet: return pad + "• " + words
            case .numbered: return pad + "\(line.ordinal ?? 1). " + words
            case .heading: return words.uppercased()
            case .quote: return "> " + words
            case .divider: return "───"
            case .blank: return ""
            case .text: return words
            }
        }.joined(separator: "\n")
    }
}
