import Foundation

/// Text styles that can be mixed inside a line.
struct InlineStyle: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let strike = InlineStyle(rawValue: 1 << 2)
    static let code = InlineStyle(rawValue: 1 << 3)
    static let highlight = InlineStyle(rawValue: 1 << 4)
    static let link = InlineStyle(rawValue: 1 << 5)
}

/// A slice of a line's content. Syntax pieces are the Markdown symbols themselves:
/// hidden when the note is shown, dimmed in the Markdown editor.
struct InlinePiece: Hashable, Sendable {
    /// UTF-16 range inside the content string (what UIKit's NSRange uses).
    var range: NSRange
    var text: String
    var style: InlineStyle
    var url: String?
    var isSyntax: Bool
}

/// Reads the inline part of mynote's Markdown. It follows CommonMark's rules for
/// matching `*` and `_` (so `***a**b*` and `snake_case` behave like everywhere
/// else) and adds `~~strike~~`, `==highlight==`, `` `code` `` and `[links](url)`.
enum InlineMarkdown {
    static func pieces(_ content: String) -> [InlinePiece] {
        guard !content.isEmpty else { return [] }
        return InlineScanner(content).run()
    }

    /// The visible text in runs of the same style (syntax removed).
    static func runs(_ content: String) -> [InlinePiece] {
        var merged: [InlinePiece] = []
        for piece in pieces(content) where !piece.isSyntax {
            if let last = merged.last, last.style == piece.style, last.url == piece.url {
                merged[merged.count - 1].text += piece.text
                merged[merged.count - 1].range = NSUnionRange(last.range, piece.range)
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// The words a reader sees.
    static func plain(_ content: String) -> String {
        // Most lines have no Markdown at all; skip the parser for them.
        if !content.contains(where: { InlineScanner.specials.contains($0) }) { return content }
        return runs(content).map(\.text).joined()
    }
}

// MARK: - Scanner

private final class InlineScanner {
    static let specials: Set<Character> = ["\\", "`", "*", "_", "~", "=", "["]

    private static let backslash: UInt16 = 92
    private static let backtick: UInt16 = 96
    private static let star: UInt16 = 42
    private static let underscore: UInt16 = 95
    private static let tilde: UInt16 = 126
    private static let equals: UInt16 = 61
    private static let openBracket: UInt16 = 91
    private static let closeBracket: UInt16 = 93
    private static let openParen: UInt16 = 40
    private static let closeParen: UInt16 = 41

    private let source: NSString
    private let u: [UInt16]
    private var syntax: [Bool]
    private var styles: [InlineStyle]
    private var urls: [String?]

    init(_ content: String) {
        source = content as NSString
        u = Array(content.utf16)
        syntax = Array(repeating: false, count: u.count)
        styles = Array(repeating: [], count: u.count)
        urls = Array(repeating: nil, count: u.count)
    }

    func run() -> [InlinePiece] {
        parse(0, u.count, inLink: false)
        var pieces: [InlinePiece] = []
        var start = 0
        for i in 1...u.count {
            if i < u.count, syntax[i] == syntax[start], styles[i] == styles[start], urls[i] == urls[start] { continue }
            let range = NSRange(location: start, length: i - start)
            pieces.append(InlinePiece(range: range, text: source.substring(with: range), style: styles[start],
                                      url: urls[start], isSyntax: syntax[start]))
            start = i
        }
        return pieces
    }

    // MARK: Character classes

    private func isWhitespace(_ i: Int) -> Bool {
        guard i >= 0, i < u.count else { return true }   // line edges count as whitespace
        let c = u[i]
        if c < 128 { return c == 32 || c == 9 || c == 10 || c == 13 }
        guard let scalar = Unicode.Scalar(c) else { return false }
        return scalar.properties.isWhitespace
    }

    private func isPunctuation(_ i: Int) -> Bool {
        guard i >= 0, i < u.count else { return false }
        let c = u[i]
        if c < 128 { return Self.isASCIIPunctuation(c) }
        guard let scalar = Unicode.Scalar(c) else { return false }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    private static func isASCIIPunctuation(_ c: UInt16) -> Bool {
        (33...47).contains(c) || (58...64).contains(c) || (91...96).contains(c) || (123...126).contains(c)
    }

    /// Characters a backslash can turn into plain text.
    private static func isEscapable(_ c: UInt16) -> Bool {
        isASCIIPunctuation(c) || c == 0x2022   // "•" starts a bullet in mynote
    }

    private func runLength(at i: Int, limit: Int) -> Int {
        var j = i
        while j < limit, u[j] == u[i] { j += 1 }
        return j - i
    }

    // MARK: Parsing

    private struct Delimiter {
        let char: UInt16
        var start: Int
        var count: Int
        let originalCount: Int
        let canOpen: Bool
        let canClose: Bool
    }

    private func mark(_ start: Int, _ end: Int, syntax isSyntax: Bool = false, adding style: InlineStyle = [], url: String? = nil) {
        guard end > start else { return }
        for i in start..<end {
            if isSyntax { syntax[i] = true }
            styles[i].formUnion(style)
            if let url { urls[i] = url }
        }
    }

    private func parse(_ from: Int, _ to: Int, inLink: Bool) {
        var delimiters: [Delimiter] = []
        var i = from
        while i < to {
            let c = u[i]
            if c == Self.backslash, i + 1 < to, Self.isEscapable(u[i + 1]) {
                mark(i, i + 1, syntax: true)
                i += 2
                continue
            }
            if c == Self.backtick {
                let n = runLength(at: i, limit: to)
                if let close = closingBackticks(n, from: i + n, to: to) {
                    mark(i, i + n, syntax: true)
                    mark(i + n, close, adding: .code)
                    mark(close, close + n, syntax: true)
                    i = close + n
                } else {
                    i += n
                }
                continue
            }
            if c == Self.openBracket, !inLink, let link = matchLink(at: i, to: to) {
                mark(i, i + 1, syntax: true)
                mark(i + 1, link.textEnd, adding: .link, url: link.url)
                parse(i + 1, link.textEnd, inLink: true)
                mark(link.textEnd, link.end, syntax: true)
                i = link.end
                continue
            }
            if c == Self.star || c == Self.underscore || c == Self.tilde || c == Self.equals {
                let n = runLength(at: i, limit: to)
                // "*️⃣" is an emoji, not a delimiter.
                if i + n < u.count, u[i + n] == 0xFE0F || u[i + n] == 0x20E3 {
                    i += n
                    continue
                }
                let leftFlanking = !isWhitespace(i + n)
                    && (!isPunctuation(i + n) || isWhitespace(i - 1) || isPunctuation(i - 1))
                let rightFlanking = !isWhitespace(i - 1)
                    && (!isPunctuation(i - 1) || isWhitespace(i + n) || isPunctuation(i + n))
                let canOpen: Bool
                let canClose: Bool
                if c == Self.underscore {
                    canOpen = leftFlanking && (!rightFlanking || isPunctuation(i - 1))
                    canClose = rightFlanking && (!leftFlanking || isPunctuation(i + n))
                } else {
                    canOpen = leftFlanking
                    canClose = rightFlanking
                }
                if canOpen || canClose {
                    delimiters.append(Delimiter(char: c, start: i, count: n, originalCount: n, canOpen: canOpen, canClose: canClose))
                }
                i += n
                continue
            }
            i += 1
        }
        processEmphasis(&delimiters)
    }

    /// CommonMark's "process emphasis": each closer looks back for the nearest opener.
    private func processEmphasis(_ stack: inout [Delimiter]) {
        var closerIndex = 0
        while closerIndex < stack.count {
            let closer = stack[closerIndex]
            guard closer.canClose, closer.count > 0 else {
                closerIndex += 1
                continue
            }
            var openerIndex = closerIndex - 1
            var found: Int?
            while openerIndex >= 0 {
                let opener = stack[openerIndex]
                if opener.char == closer.char, opener.canOpen, opener.count > 0, compatible(opener, closer) {
                    found = openerIndex
                    break
                }
                openerIndex -= 1
            }
            guard let openerAt = found else {
                if closer.canOpen {
                    closerIndex += 1
                } else {
                    stack.remove(at: closerIndex)
                }
                continue
            }

            let opener = stack[openerAt]
            let use: Int
            let style: InlineStyle
            switch closer.char {
            case Self.tilde:
                use = 2
                style = .strike
            case Self.equals:
                use = 2
                style = .highlight
            default:
                use = opener.count >= 2 && closer.count >= 2 ? 2 : 1
                style = use == 2 ? .bold : .italic
            }
            // The opener gives up its last characters, the closer its first ones.
            let openEnd = opener.start + opener.count
            mark(openEnd - use, openEnd, syntax: true)
            mark(closer.start, closer.start + use, syntax: true)
            mark(openEnd, closer.start, adding: style)

            stack[openerAt].count -= use
            stack[closerIndex].count -= use
            stack[closerIndex].start += use
            // Delimiters between the pair can no longer match anything.
            stack.removeSubrange((openerAt + 1)..<closerIndex)
            closerIndex = openerAt + 1
            if stack[openerAt].count == 0 {
                stack.remove(at: openerAt)
                closerIndex -= 1
            }
            if stack[closerIndex].count == 0 {
                stack.remove(at: closerIndex)
            }
        }
    }

    private func compatible(_ opener: Delimiter, _ closer: Delimiter) -> Bool {
        if opener.char == Self.tilde || opener.char == Self.equals {
            return opener.count >= 2 && closer.count >= 2
        }
        // CommonMark's "rule of 3".
        if (opener.canOpen && opener.canClose) || (closer.canOpen && closer.canClose) {
            let sum = opener.originalCount + closer.originalCount
            if sum % 3 == 0, !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0) {
                return false
            }
        }
        return true
    }

    private func closingBackticks(_ n: Int, from start: Int, to: Int) -> Int? {
        var j = start
        while j < to {
            if u[j] == Self.backtick {
                let m = runLength(at: j, limit: to)
                if m == n { return j }
                j += m
            } else {
                j += 1
            }
        }
        return nil
    }

    /// `[text](url)` starting at `i`.
    private func matchLink(at i: Int, to: Int) -> (textEnd: Int, end: Int, url: String)? {
        var depth = 0
        var j = i + 1
        while j < to {
            let d = u[j]
            if d == Self.backslash {
                j += 2
                continue
            }
            if d == Self.openBracket {
                depth += 1
            } else if d == Self.closeBracket {
                if depth == 0 { break }
                depth -= 1
            }
            j += 1
        }
        guard j < to, u[j] == Self.closeBracket, j > i + 1 else { return nil }
        let textEnd = j
        guard textEnd + 1 < to, u[textEnd + 1] == Self.openParen else { return nil }
        let urlStart = textEnd + 2
        var k = urlStart
        while k < to, u[k] != Self.closeParen, !isWhitespace(k) { k += 1 }
        guard k < to, u[k] == Self.closeParen, k > urlStart else { return nil }
        let url = source.substring(with: NSRange(location: urlStart, length: k - urlStart))
        return (textEnd, k + 1, url)
    }
}
