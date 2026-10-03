import UIKit

extension NSAttributedString.Key {
    /// Bold, italic and friends as an `InlineStyle` raw value. The rich editor draws fonts
    /// and colours from this and turns it back into Markdown.
    static let noteInline = NSAttributedString.Key("mynote.inline")
    /// The address of a link.
    static let noteLink = NSAttributedString.Key("mynote.link")
    /// Heading level (1 to 3) on every character of a heading line.
    static let noteHeading = NSAttributedString.Key("mynote.heading")
}

/// What kind of line a rich paragraph is, when it starts with a marker.
struct RichBlock: Hashable {
    enum Kind: String {
        case bullet, numbered, todo, quote, divider
    }

    var kind: Kind
    var indent = 0
    var checked = false
    /// For numbered lists that came from Markdown starting at another number ("3. ").
    var start: Int? = nil

    var isListItem: Bool { kind == .bullet || kind == .numbered || kind == .todo }

    var encoded: String { "\(kind.rawValue)|\(indent)|\(checked ? 1 : 0)|\(start ?? 0)" }

    init(kind: Kind, indent: Int = 0, checked: Bool = false, start: Int? = nil) {
        self.kind = kind
        self.indent = indent
        self.checked = checked
        self.start = start
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: "|").map(String.init)
        guard parts.count == 4, let kind = Kind(rawValue: parts[0]) else { return nil }
        self.init(kind: kind, indent: Int(parts[1]) ?? 0, checked: parts[2] == "1", start: Int(parts[3]).flatMap { $0 > 0 ? $0 : nil })
    }
}

/// The bullet, number, checkbox, quote bar or divider at the start of a rich paragraph.
/// It's a single character in the text, so the cursor and line breaks behave naturally.
final class MarkerAttachment: NSTextAttachment {
    let block: RichBlock
    /// The number drawn for numbered items, worked out on every edit.
    var ordinal = 1

    init(block: RichBlock) {
        self.block = block
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        let raw = coder.decodeObject(of: NSString.self, forKey: "mynote.block") as String?
        block = raw.flatMap(RichBlock.init(encoded:)) ?? RichBlock(kind: .bullet)
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(block.encoded as NSString, forKey: "mynote.block")
    }

    override class var supportsSecureCoding: Bool { true }
}

/// Converts between the note's Markdown and the rich editor's attributed text.
///
/// The attributed text only holds meaning (`noteInline`, `noteLink`, `noteHeading` and
/// marker attachments). Fonts and colours are added by the editor, so a theme change
/// never touches the note itself.
enum RichTextCodec {
    static let markerCharacter: Character = "\u{FFFC}"
    static let markerUnit: unichar = 0xFFFC
    static let markdownPasteboardType = "net.daringfireball.markdown"

    // MARK: Markdown → rich

    static func attributedString(from markdown: String) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for (n, line) in NoteParser.parse(markdown).enumerated() {
            if n > 0 { result.append(NSAttributedString(string: "\n")) }
            var block: RichBlock?
            switch line.kind {
            case .bullet: block = RichBlock(kind: .bullet, indent: line.indent)
            case .numbered: block = RichBlock(kind: .numbered, indent: line.indent, start: line.ordinal)
            case .todo(let checked): block = RichBlock(kind: .todo, indent: line.indent, checked: checked)
            case .quote: block = RichBlock(kind: .quote)
            case .divider: block = RichBlock(kind: .divider)
            case .text, .heading, .blank: break
            }
            if let block {
                result.append(NSAttributedString(attachment: MarkerAttachment(block: block)))
            }
            if line.kind == .divider || line.kind == .blank { continue }
            var base: [NSAttributedString.Key: Any] = [:]
            if case .heading(let level) = line.kind { base[.noteHeading] = level }
            for run in InlineMarkdown.runs(line.content) {
                var attributes = base
                let style = run.style.subtracting(.link)
                if !style.isEmpty { attributes[.noteInline] = style.rawValue }
                if run.style.contains(.link), let url = run.url { attributes[.noteLink] = url }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
        }
        return result
    }

    // MARK: Rich → Markdown

    enum ParagraphRole: Equatable {
        case numbered(indent: Int, start: Int?)
        case listItem(indent: Int)
        case blank
        case other
    }

    /// The number shown on each numbered paragraph, with the same rules as `NoteParser.number`.
    static func ordinals(for roles: [ParagraphRole]) -> [Int?] {
        var next: [Int: Int] = [:]
        return roles.map { role in
            switch role {
            case .numbered(let indent, let start):
                let value = next[indent] ?? start ?? 1
                next = next.filter { $0.key < indent }
                next[indent] = value + 1
                return value
            case .listItem(let indent):
                next = next.filter { $0.key < indent }
                return nil
            case .blank:
                return nil
            case .other:
                next.removeAll()
                return nil
            }
        }
    }

    /// Paragraph ranges (without their line breaks), in order.
    static func paragraphRanges(_ ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var start = 0
        while true {
            let found = ns.range(of: "\n", options: .literal, range: NSRange(location: start, length: ns.length - start))
            if found.location == NSNotFound {
                result.append(NSRange(location: start, length: ns.length - start))
                return result
            }
            result.append(NSRange(location: start, length: found.location - start))
            start = found.location + 1
        }
    }

    static func marker(in text: NSAttributedString, at index: Int) -> MarkerAttachment? {
        guard index >= 0, index < text.length, (text.string as NSString).character(at: index) == markerUnit else { return nil }
        return text.attribute(.attachment, at: index, effectiveRange: nil) as? MarkerAttachment
    }

    static func headingLevel(in text: NSAttributedString, paragraph: NSRange) -> Int {
        guard paragraph.length > 0 else { return 0 }
        return text.attribute(.noteHeading, at: paragraph.location, effectiveRange: nil) as? Int ?? 0
    }

    static func role(in text: NSAttributedString, paragraph: NSRange) -> ParagraphRole {
        if let block = marker(in: text, at: paragraph.location)?.block {
            switch block.kind {
            case .numbered: return .numbered(indent: block.indent, start: block.start)
            case .bullet, .todo: return .listItem(indent: block.indent)
            case .quote, .divider: return .other
            }
        }
        return paragraph.length == 0 ? .blank : .other
    }

    static func markdown(from text: NSAttributedString) -> String {
        var lossy = false
        return markdown(from: text, lossy: &lossy)
    }

    /// `lossy` turns true when some formatting couldn't be written as Markdown and was left out,
    /// so the editor can show what was really saved.
    static func markdown(from text: NSAttributedString, lossy: inout Bool) -> String {
        let paragraphs = paragraphRanges(text.string as NSString)
        let numbers = ordinals(for: paragraphs.map { role(in: text, paragraph: $0) })
        var lines: [String] = []
        for (paragraph, number) in zip(paragraphs, numbers) {
            lines.append(line(for: paragraph, number: number, in: text, lossy: &lossy))
        }
        return lines.joined(separator: "\n")
    }

    private static func line(for paragraph: NSRange, number: Int?, in text: NSAttributedString, lossy: inout Bool) -> String {
        if let block = marker(in: text, at: paragraph.location)?.block {
            let content = NSRange(location: paragraph.location + 1, length: paragraph.length - 1)
            let words = keepingLeadingSpaces(inlineMarkdown(text, in: content, lossy: &lossy))
            let pad = String(repeating: "  ", count: block.indent)
            switch block.kind {
            case .bullet:
                return safeLine(prefix: pad + "- ", words: words) { $0.kind == .bullet }
            case .numbered:
                return safeLine(prefix: pad + "\(number ?? 1). ", words: words) { if case .numbered = $0.kind { true } else { false } }
            case .todo:
                return safeLine(prefix: pad + (block.checked ? "- [x] " : "- [ ] "), words: words) { $0.kind == .todo(checked: block.checked) }
            case .quote:
                return safeLine(prefix: "> ", words: words) { $0.kind == .quote }
            case .divider:
                return "---"
            }
        }
        let words = keepingLeadingSpaces(inlineMarkdown(text, in: paragraph, lossy: &lossy))
        let level = min(headingLevel(in: text, paragraph: paragraph), 3)
        if level > 0, !words.isEmpty {
            return safeLine(prefix: String(repeating: "#", count: level) + " ", words: words) { $0.kind == .heading(level) }
        }
        return safeLine(prefix: "", words: words) { $0.kind == .text || ($0.kind == .blank && words.isEmpty) }
    }

    /// Builds a line and checks it reads back as the same kind of line with the same words.
    /// If the words would be taken for Markdown (a list, a heading, a divider…), the symbol
    /// that causes it is escaped.
    private static func safeLine(prefix: String, words: String, expecting isExpected: (NoteLine) -> Bool) -> String {
        func readsBack(_ candidate: String) -> Bool {
            let parsed = NoteParser.parseLine(prefix + candidate, index: 0)
            return isExpected(parsed) && InlineMarkdown.plain(parsed.content) == InlineMarkdown.plain(candidate)
        }
        if readsBack(words) { return prefix + words }
        let escaped = escapeLineStart(words)
        if escaped != words, readsBack(escaped) { return prefix + escaped }
        if let first = words.first, first.isPunctuation || first.isSymbol, readsBack("\\" + words) {
            return prefix + "\\" + words
        }
        return prefix + words
    }

    /// Markdown drops spaces at the start of a line, so they're kept as no-break spaces.
    private static func keepingLeadingSpaces(_ words: String) -> String {
        guard let first = words.first, first == " " || first == "\t" else { return words }
        let leading = words.prefix { $0 == " " || $0 == "\t" }
        let kept = leading.map { $0 == "\t" ? "\u{00A0}\u{00A0}" : "\u{00A0}" }.joined()
        return kept + words.dropFirst(leading.count)
    }

    // MARK: Inline

    private struct Glyph {
        var character: Character
        var style: InlineStyle
        var url: String?
    }

    static func inlineMarkdown(_ text: NSAttributedString, in range: NSRange) -> String {
        var lossy = false
        return inlineMarkdown(text, in: range, lossy: &lossy)
    }

    /// The Markdown for one paragraph's words. Tries a few spellings and keeps the first one
    /// that reads back exactly as written. In the rare case none does (say, bold that starts
    /// on a bracket right after a letter), the fewest styles that can't be written are left
    /// out, rather than saving something that looks different from the editor.
    static func inlineMarkdown(_ text: NSAttributedString, in range: NSRange, lossy: inout Bool) -> String {
        guard range.length > 0 else { return "" }
        var glyphs: [Glyph] = []
        text.enumerateAttributes(in: range) { attributes, run, _ in
            let style = InlineStyle(rawValue: attributes[.noteInline] as? Int ?? 0).subtracting(.link)
            let url = attributes[.noteLink] as? String
            let fullStyle = url == nil ? style : style.union(.link)
            for character in (text.string as NSString).substring(with: run) where character != markerCharacter {
                glyphs.append(Glyph(character: character, style: fullStyle, url: url))
            }
        }
        trimStylesAtSpaces(&glyphs)
        if let spelled = spelling(of: glyphs) { return spelled }

        lossy = true
        var remaining = glyphs
        while true {
            let spans = styleSpans(in: remaining)
            guard let first = spans.first else { break }
            // Prefer dropping a single style run that fixes the line.
            for span in spans {
                var candidate = remaining
                remove(span, from: &candidate)
                if let spelled = spelling(of: candidate) { return spelled }
            }
            remove(first, from: &remaining)
            if let spelled = spelling(of: remaining) { return spelled }
        }
        return emit(remaining, italic: "*", bold: "**")
    }

    /// The first way of writing these glyphs that reads back exactly the same.
    private static func spelling(of glyphs: [Glyph]) -> String? {
        for spelling in [("*", "**"), ("_", "**"), ("*", "__"), ("_", "__")] {
            let candidate = emit(glyphs, italic: spelling.0, bold: spelling.1)
            if readsBack(candidate, as: glyphs) { return candidate }
        }
        return nil
    }

    private struct StyleSpan {
        let flag: InlineStyle
        let range: Range<Int>
    }

    private static func styleSpans(in glyphs: [Glyph]) -> [StyleSpan] {
        var spans: [StyleSpan] = []
        for flag in [InlineStyle.link, .code, .highlight, .strike, .italic, .bold] {
            var i = 0
            while i < glyphs.count {
                guard glyphs[i].style.contains(flag) else {
                    i += 1
                    continue
                }
                var end = i
                while end < glyphs.count, glyphs[end].style.contains(flag), glyphs[end].url == glyphs[i].url { end += 1 }
                spans.append(StyleSpan(flag: flag, range: i..<end))
                i = end
            }
        }
        return spans
    }

    private static func remove(_ span: StyleSpan, from glyphs: inout [Glyph]) {
        for i in span.range {
            glyphs[i].style.remove(span.flag)
            if span.flag == .link { glyphs[i].url = nil }
        }
    }

    /// Markdown can't start or end emphasis on a space ("** bold**" isn't bold), so styles
    /// are pulled in off the spaces at either end of a styled run.
    private static func trimStylesAtSpaces(_ glyphs: inout [Glyph]) {
        for flag in [InlineStyle.bold, .italic, .strike, .highlight] {
            var i = 0
            while i < glyphs.count {
                guard glyphs[i].style.contains(flag) else {
                    i += 1
                    continue
                }
                var end = i
                while end < glyphs.count, glyphs[end].style.contains(flag) { end += 1 }
                var low = i
                while low < end, glyphs[low].character.isWhitespace {
                    glyphs[low].style.remove(flag)
                    low += 1
                }
                var high = end - 1
                while high >= low, glyphs[high].character.isWhitespace {
                    glyphs[high].style.remove(flag)
                    high -= 1
                }
                i = end
            }
        }
    }

    private enum Token: Hashable {
        case link(String)
        case style(InlineStyle)
    }

    private static func tokens(of glyph: Glyph) -> [Token] {
        var result: [Token] = []
        if glyph.style.contains(.link), let url = glyph.url { result.append(.link(url)) }
        for flag in [InlineStyle.highlight, .strike, .bold, .italic] where glyph.style.contains(flag) {
            result.append(.style(flag))
        }
        return result
    }

    private static func emit(_ glyphs: [Glyph], italic: String, bold: String) -> String {
        // Group into runs of the same look.
        var runs: [(text: [Character], style: InlineStyle, url: String?)] = []
        for glyph in glyphs {
            if let last = runs.last, last.style == glyph.style, last.url == glyph.url {
                runs[runs.count - 1].text.append(glyph.character)
            } else {
                runs.append(([glyph.character], glyph.style, glyph.url))
            }
        }
        let runTokens = runs.map { tokens(of: Glyph(character: " ", style: $0.style, url: $0.url)) }

        func opener(_ token: Token) -> String {
            switch token {
            case .link: return "["
            case .style(let flag):
                switch flag {
                case .bold: return bold
                case .italic: return italic
                case .strike: return "~~"
                default: return "=="
                }
            }
        }
        func closer(_ token: Token) -> String {
            switch token {
            case .link(let url): return "](" + escapeURL(url) + ")"
            case .style: return opener(token)
            }
        }
        /// How many runs from `index` on keep this token: longer spans open first (outside).
        func reach(_ token: Token, from index: Int) -> Int {
            var end = index
            while end < runTokens.count, runTokens[end].contains(token) { end += 1 }
            return end
        }

        var output = ""
        var stack: [Token] = []
        let allCharacters = glyphs.map(\.character)
        var position = 0
        for (index, run) in runs.enumerated() {
            let wanted = runTokens[index]
            var keep = 0
            while keep < stack.count, wanted.contains(stack[keep]) { keep += 1 }
            for token in stack[keep...].reversed() { output += closer(token) }
            stack.removeLast(stack.count - keep)
            let rank: [Token: Int] = Dictionary(uniqueKeysWithValues: wanted.enumerated().map { ($1, $0) })
            let opening = wanted.filter { !stack.contains($0) }.sorted {
                let a = reach($0, from: index), b = reach($1, from: index)
                return a != b ? a > b : rank[$0, default: 0] < rank[$1, default: 0]
            }
            for token in opening {
                output += opener(token)
                stack.append(token)
            }
            if run.style.contains(.code) {
                output += codeSpan(String(run.text))
            } else {
                for (offset, character) in run.text.enumerated() {
                    let at = position + offset
                    let previous = at > 0 ? allCharacters[at - 1] : nil
                    let next = at + 1 < allCharacters.count ? allCharacters[at + 1] : nil
                    output += escape(character, previous: previous, next: next,
                                     atRunEdge: offset == 0 || offset == run.text.count - 1)
                }
            }
            position += run.text.count
        }
        for token in stack.reversed() { output += closer(token) }
        return output
    }

    private static func escape(_ c: Character, previous: Character?, next: Character?, atRunEdge: Bool) -> String {
        switch c {
        case "\\", "*", "`", "[", "]":
            return "\\" + String(c)
        case "_":
            let inWord = (previous.map(isWordCharacter) ?? false) && (next.map(isWordCharacter) ?? false)
            return inWord ? "_" : "\\_"
        case "~", "=":
            return previous == c || next == c || atRunEdge ? "\\" + String(c) : String(c)
        default:
            return String(c)
        }
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }

    private static func codeSpan(_ text: String) -> String {
        var longest = 0
        var current = 0
        for c in text {
            current = c == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        let fence = String(repeating: "`", count: longest + 1)
        return fence + text + fence
    }

    private static func escapeURL(_ url: String) -> String {
        url.replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    /// Stops the words of a line from being read as a list, heading, quote or divider.
    static func escapeLineStart(_ words: String) -> String {
        guard let first = words.first else { return words }
        let chars = Array(words)
        let second = chars.count > 1 ? chars[1] : " "
        if "-+•".contains(first), second == " " { return "\\" + words }
        if first == ">" { return "\\" + words }
        if first == "#" {
            let hashes = chars.prefix { $0 == "#" }.count
            if hashes < chars.count, chars[hashes] == " " { return "\\" + words }
        }
        if first.isASCII, first.isNumber {
            let digits = chars.prefix { $0.isASCII && $0.isNumber }.count
            if digits + 1 < chars.count, chars[digits] == "." || chars[digits] == ")", chars[digits + 1] == " " {
                return String(chars[..<digits]) + "\\" + String(chars[digits...])
            }
        }
        let marks = chars.filter { $0 != " " }
        if marks.count >= 3, let mark = marks.first, "-_".contains(mark), marks.allSatisfy({ $0 == mark }) {
            return "\\" + words
        }
        return words
    }

    /// True when `markdown` reads back as exactly these characters and styles.
    private static func readsBack(_ markdown: String, as glyphs: [Glyph]) -> Bool {
        var parsed: [Glyph] = []
        for run in InlineMarkdown.runs(markdown) {
            for character in run.text {
                parsed.append(Glyph(character: character, style: run.style, url: run.url))
            }
        }
        guard parsed.count == glyphs.count else { return false }
        // Addresses are written with brackets and spaces encoded, so compare them that way.
        for (a, b) in zip(parsed, glyphs) where a.character != b.character || a.style != b.style || a.url != b.url.map(escapeURL) {
            return false
        }
        return true
    }

    // MARK: Counting

    /// Characters that count toward the limit: everything except markers.
    static func visibleCount(_ string: String) -> Int {
        string.reduce(0) { $1 == markerCharacter ? $0 : $0 + 1 }
    }
}
