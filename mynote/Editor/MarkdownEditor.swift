import SwiftUI
import UIKit

/// The Markdown editor: the note's plain text with its symbols shown (dimmed) and the
/// formatting drawn on top. Enforces the character limit and continues lists on return.
struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var theme: Theme
    var font: NoteFont
    var size: CGFloat
    var controller: EditorController
    var onLimitHit: () -> Void
    var onEndEditing: () -> Void
    /// Whether the view shows any text at all (including text still being composed).
    var onVisibleTextChange: (Bool) -> Void = { _ in }
    var onFormatState: (FormatState) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> NoteUITextView {
        let tv = NoteUITextView()
        EditorLayout.configure(tv)
        tv.delegate = context.coordinator
        context.coordinator.setTextFromOutside(text, in: tv)
        context.coordinator.textView = tv
        controller.editor = context.coordinator
        context.coordinator.restyle(tv)
        return tv
    }

    func updateUIView(_ tv: NoteUITextView, context: Context) {
        let coordinator = context.coordinator
        let styleChanged = coordinator.parent.theme != theme || coordinator.parent.font != font || coordinator.parent.size != size
        coordinator.parent = self
        controller.editor = coordinator
        if tv.text != text, tv.markedTextRange == nil {
            coordinator.setTextFromOutside(text, in: tv)
            coordinator.acceptExternalText(text)
            coordinator.restyle(tv)
        } else if styleChanged {
            coordinator.restyle(tv)
        }
        EditorLayout.syncFocus(tv, wantsFocus: isFocused)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, NoteEditing {
        var parent: MarkdownEditor
        weak var textView: NoteUITextView?
        private var isProgrammatic = false
        /// The last committed text that was within the limit.
        private var lastValidText: String

        init(parent: MarkdownEditor) {
            self.parent = parent
            self.lastValidText = parent.text
        }

        // MARK: Delegate

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
            if isProgrammatic { return true }
            // While composing (pinyin, kana…) let the keyboard work. The marked letters
            // aren't the final text, so the limit is checked once the text is committed.
            if tv.markedTextRange != nil { return true }

            if string == "\n", handleReturn(in: tv, range: range) {
                return false
            }

            let current = tv.text as NSString
            let proposed = current.replacingCharacters(in: range, with: string)
            let limit = NoteParser.characterLimit
            let proposedLength = NoteParser.countedLength(proposed)
            if proposedLength > limit, proposedLength > NoteParser.countedLength(tv.text) {
                // A real paste keeps as much as fits; anything else is simply refused.
                if (tv as? NoteUITextView)?.isPasting == true {
                    let fitted = fittedPaste(string, into: current, range: range)
                    if !fitted.isEmpty { replace(in: tv, range: range, with: fitted) }
                }
                parent.onLimitHit()
                return false
            }
            return true
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.onVisibleTextChange(!tv.text.isEmpty)
            // Our own edits sync themselves and were checked against the limit beforehand.
            guard !isProgrammatic else { return }
            if tv.markedTextRange == nil, tv.undoManager?.isUndoing != true, tv.undoManager?.isRedoing != true {
                let length = NoteParser.countedLength(tv.text)
                if length > NoteParser.characterLimit, length > NoteParser.countedLength(lastValidText) {
                    // Something bypassed shouldChangeText (a committed IME phrase, dictation): roll it back.
                    rollBack(tv)
                    parent.onLimitHit()
                }
            }
            sync(tv)
        }

        /// Puts back the text from before the change, editing only the part that changed so the
        /// system's undo history still matches the text.
        private func rollBack(_ tv: UITextView) {
            let old = lastValidText as NSString
            let new = tv.text as NSString
            var prefix = 0
            while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
            var suffix = 0
            while suffix < old.length - prefix, suffix < new.length - prefix,
                  old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
            let original = old.substring(with: NSRange(location: prefix, length: old.length - prefix - suffix))
            replace(in: tv, range: NSRange(location: prefix, length: new.length - prefix - suffix), with: original)
            tv.selectedRange = NSRange(location: prefix + (original as NSString).length, length: 0)
        }

        /// Text from outside (first load, Siri, the Lock Screen). Setting `text` doesn't fire the
        /// change callbacks we care about, but it does leave the undo history describing old text.
        func setTextFromOutside(_ text: String, in tv: UITextView) {
            isProgrammatic = true
            tv.text = text
            isProgrammatic = false
            DispatchQueue.main.async { [weak tv] in tv?.undoManager?.removeAllActions() }
        }

        /// Whether an edit made by the formatting bar stays within the character limit.
        private func fits(replacing range: NSRange, with string: String, in tv: UITextView) -> Bool {
            let proposed = (tv.text as NSString).replacingCharacters(in: range, with: string)
            let length = NoteParser.countedLength(proposed)
            if length <= NoteParser.characterLimit || length <= NoteParser.countedLength(tv.text) { return true }
            parent.onLimitHit()
            return false
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard !isProgrammatic else { return }
            reportFormatState(tv)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
            reportFormatState(textView)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if EditorLayout.lostFocusToPresentedSheet(tv) { return }
            if parent.isFocused { parent.isFocused = false }
            parent.onEndEditing()
        }

        /// Text set from outside (Siri, the Lock Screen, archive/restore) becomes the new baseline.
        func acceptExternalText(_ text: String) {
            if NoteParser.countedLength(text) <= NoteParser.characterLimit {
                lastValidText = text
            }
        }

        func commitComposition() {
            guard let tv = textView, tv.markedTextRange != nil else { return }
            tv.unmarkText()
            sync(tv)
        }

        /// Longest prefix of `string` that fits under the limit (binary search, so huge pastes stay fast).
        private func fittedPaste(_ string: String, into current: NSString, range: NSRange) -> String {
            let chars = Array(string.prefix(4_000))
            var low = 0
            var high = chars.count
            while low < high {
                let mid = (low + high + 1) / 2
                let candidate = current.replacingCharacters(in: range, with: String(chars[..<mid]))
                if NoteParser.countedLength(candidate) <= NoteParser.characterLimit {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            return String(chars[..<low])
        }

        // MARK: Lists

        /// Return on a list line continues the list; return on an empty item ends it.
        private func handleReturn(in tv: UITextView, range: NSRange) -> Bool {
            let ns = tv.text as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            var lineText = ns.substring(with: lineRange)
            if lineText.hasSuffix("\n") { lineText.removeLast() }
            let line = NoteParser.parseLine(lineText, index: 0)
            guard let continuation = NoteParser.continuationPrefix(for: line) else { return false }
            let prefixLength = (line.prefix as NSString).length
            guard range.location >= lineRange.location + prefixLength else { return false }

            if line.content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty item: step out of the nesting first, then drop the marker.
                let replacement = line.indent > 0 && line.isListItem
                    ? String(line.prefix.dropFirst(min(2, line.prefix.prefix { $0 == " " || $0 == "\t" }.count)))
                    : ""
                replace(in: tv, range: NSRange(location: lineRange.location, length: prefixLength), with: replacement)
                tv.selectedRange = NSRange(location: lineRange.location + (replacement as NSString).length, length: 0)
                return true
            }

            let insert = "\n" + continuation
            let proposed = ns.replacingCharacters(in: range, with: insert)
            if NoteParser.countedLength(proposed) > NoteParser.characterLimit {
                parent.onLimitHit()
                return true
            }
            replace(in: tv, range: range, with: insert)
            tv.selectedRange = NSRange(location: range.location + (insert as NSString).length, length: 0)
            return true
        }

        func replace(in tv: UITextView, range: NSRange, with string: String) {
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: start, offset: range.length),
                  let textRange = tv.textRange(from: start, to: end)
            else { return }
            isProgrammatic = true
            tv.replace(textRange, withText: string)
            isProgrammatic = false
            sync(tv)
        }

        private func sync(_ tv: UITextView) {
            // Don't save or broadcast half-composed IME text.
            guard tv.markedTextRange == nil else { return }
            restyle(tv)
            if NoteParser.countedLength(tv.text) <= NoteParser.characterLimit {
                lastValidText = tv.text
            }
            if parent.text != tv.text { parent.text = tv.text }
            reportFormatState(tv)
        }

        // MARK: Formatting bar

        func perform(_ action: FormatAction) {
            guard let tv = textView, tv.markedTextRange == nil else { return }
            switch action {
            case .inline(let style): toggleInline(style, in: tv)
            case .block(let block): toggleBlock(block, in: tv)
            case .heading: cycleHeading(in: tv)
            case .indent: shiftIndent(by: 1, in: tv)
            case .outdent: shiftIndent(by: -1, in: tv)
            case .divider: insertDivider(in: tv)
            }
            reportFormatState(tv)
        }

        /// The lines the selection touches, as ranges without their line breaks.
        private func touchedLines(_ tv: UITextView) -> [NSRange] {
            let ns = tv.text as NSString
            let selection = tv.selectedRange
            var ranges: [NSRange] = []
            var location = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
            repeat {
                let line = ns.lineRange(for: NSRange(location: location, length: 0))
                var content = line
                if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
                ranges.append(content)
                location = NSMaxRange(line)
            } while location < NSMaxRange(selection) && location < ns.length
            return ranges
        }

        /// Rewrites the touched lines. `transform` gets each line and returns its new text,
        /// or nil to leave it alone. The selection keeps its place in the words.
        private func rewriteLines(in tv: UITextView, _ transform: (NoteLine, Int) -> String?) {
            let ns = tv.text as NSString
            let ranges = touchedLines(tv)
            guard let first = ranges.first, let last = ranges.last else { return }
            let selection = tv.selectedRange
            var output: [String] = []
            // For each line: where it started, where it starts now, and how long its marker was and is.
            var layout: [(oldStart: Int, oldPrefix: Int, newStart: Int, newPrefix: Int, newLength: Int)] = []
            var cursor = first.location
            for (offset, range) in ranges.enumerated() {
                let raw = ns.substring(with: range)
                let line = NoteParser.parseLine(raw, index: 0)
                let updated = transform(line, offset) ?? raw
                let rawLength = (raw as NSString).length
                let updatedLength = (updated as NSString).length
                let oldPrefix = line.kind == .blank ? rawLength : (line.prefix as NSString).length
                let newPrefix = max(0, updatedLength - (rawLength - oldPrefix))
                layout.append((range.location, oldPrefix, cursor, newPrefix, updatedLength))
                output.append(updated)
                cursor += updatedLength + 1
            }
            func moved(_ position: Int) -> Int {
                guard let entry = layout.last(where: { $0.oldStart <= position }) else { return position }
                let intoWords = max(0, position - entry.oldStart - entry.oldPrefix)
                return min(entry.newStart + entry.newPrefix + intoWords, entry.newStart + entry.newLength)
            }
            let start = moved(selection.location)
            let end = moved(NSMaxRange(selection))
            let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            replace(in: tv, range: whole, with: output.joined(separator: "\n"))
            tv.selectedRange = NSRange(location: start, length: max(0, end - start))
        }

        private static func indentation(of line: NoteLine) -> String {
            line.isListItem ? String(line.prefix.prefix { $0 == " " || $0 == "\t" }) : ""
        }

        private static func isBlock(_ line: NoteLine, _ block: BlockFormat) -> Bool {
            switch (block, line.kind) {
            case (.todo, .todo), (.bullet, .bullet), (.numbered, .numbered), (.quote, .quote): true
            default: false
            }
        }

        private func toggleBlock(_ block: BlockFormat, in tv: UITextView) {
            let ns = tv.text as NSString
            let lines = touchedLines(tv).map { NoteParser.parseLine(ns.substring(with: $0), index: 0) }
            let several = lines.count > 1
            let removing = lines.filter { !(several && $0.kind == .blank) }.allSatisfy { Self.isBlock($0, block) }
            var number = 1
            rewriteLines(in: tv) { line, _ in
                if line.kind == .divider || (several && line.kind == .blank) { return nil }
                let words = line.kind == .blank ? "" : line.content
                if removing { return Self.indentation(of: line) + words }
                let marker: String
                switch block {
                case .todo: marker = line.isTodo ? String(line.prefix.drop { $0 == " " || $0 == "\t" }) : "- [ ] "
                case .bullet: marker = "- "
                case .numbered:
                    marker = "\(number). "
                    number += 1
                case .quote: marker = "> "
                }
                return (block == .quote ? "" : Self.indentation(of: line)) + marker + words
            }
        }

        private func cycleHeading(in tv: UITextView) {
            let ns = tv.text as NSString
            guard let first = touchedLines(tv).first else { return }
            let current = NoteParser.parseLine(ns.substring(with: first), index: 0)
            let level: Int = if case .heading(let l) = current.kind { l } else { 0 }
            let next = (level + 1) % 4
            rewriteLines(in: tv) { line, _ in
                if line.kind == .divider { return nil }
                let words = line.kind == .blank ? "" : line.content
                return next == 0 ? words : String(repeating: "#", count: next) + " " + words
            }
        }

        private func shiftIndent(by step: Int, in tv: UITextView) {
            rewriteLines(in: tv) { line, _ in
                guard line.isListItem else { return nil }
                let leading = line.prefix.prefix { $0 == " " || $0 == "\t" }
                let marker = line.prefix.dropFirst(leading.count)
                let level = max(0, min(NoteParser.maxIndent, line.indent + step))
                return String(repeating: "  ", count: level) + marker + line.content
            }
        }

        private func insertDivider(in tv: UITextView) {
            let ns = tv.text as NSString
            guard let line = touchedLines(tv).last else { return }
            let lineText = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
            if lineText.isEmpty {
                let insert = NSMaxRange(line) < ns.length ? "---" : "---\n"
                guard fits(replacing: line, with: insert, in: tv) else { return }
                replace(in: tv, range: line, with: insert)
                tv.selectedRange = NSRange(location: line.location + 4, length: 0)
            } else {
                let at = NSRange(location: NSMaxRange(line), length: 0)
                guard fits(replacing: at, with: "\n---\n", in: tv) else { return }
                replace(in: tv, range: at, with: "\n---\n")
                tv.selectedRange = NSRange(location: NSMaxRange(line) + 5, length: 0)
            }
        }

        /// Wraps the selection in Markdown symbols, or unwraps it when it's already styled.
        private func toggleInline(_ style: InlineStyle, in tv: UITextView) {
            let marker: String
            switch style {
            case .bold: marker = "**"
            case .italic: marker = "*"
            case .strike: marker = "~~"
            case .code: marker = "`"
            case .highlight: marker = "=="
            default: return
            }
            let ns = tv.text as NSString
            let selection = tv.selectedRange
            let markerLength = (marker as NSString).length

            if let span = styledSpan(style, at: selection, in: tv) {
                // Remove the closing symbols first so the opening range stays valid.
                replace(in: tv, range: span.close, with: "")
                replace(in: tv, range: span.open, with: "")
                let shift = { (location: Int) -> Int in
                    var l = location
                    if l > span.close.location { l -= min(span.close.length, l - span.close.location) }
                    if l > span.open.location { l -= min(span.open.length, l - span.open.location) }
                    return l
                }
                let start = shift(selection.location)
                tv.selectedRange = NSRange(location: start, length: max(0, shift(NSMaxRange(selection)) - start))
                return
            }

            if selection.length == 0 {
                guard fits(replacing: selection, with: marker + marker, in: tv) else { return }
                replace(in: tv, range: selection, with: marker + marker)
                tv.selectedRange = NSRange(location: selection.location + markerLength, length: 0)
                return
            }
            // Wrap the words of each touched line on their own, leaving list markers and line
            // breaks outside, and spaces at either end too (Markdown wouldn't read them).
            var wraps: [NSRange] = []
            for line in touchedLines(tv) {
                let parsed = NoteParser.parseLine(ns.substring(with: line), index: 0)
                guard parsed.kind != .blank, parsed.kind != .divider else { continue }
                let words = NSRange(location: line.location + (parsed.prefix as NSString).length,
                                    length: line.length - (parsed.prefix as NSString).length)
                var part = NSIntersectionRange(words, selection)
                guard part.length > 0 || (selection.length == 0 && part.location == selection.location) else { continue }
                while part.length > 0, Self.isSpace(ns.character(at: part.location)) {
                    part.location += 1
                    part.length -= 1
                }
                while part.length > 0, Self.isSpace(ns.character(at: NSMaxRange(part) - 1)) {
                    part.length -= 1
                }
                if part.length > 0 { wraps.append(part) }
            }
            guard let firstWrap = wraps.first, let lastWrap = wraps.last else { return }
            for part in wraps.reversed() {
                let words = ns.substring(with: part)
                replace(in: tv, range: part, with: marker + words + marker)
            }
            let added = 2 * markerLength * wraps.count
            tv.selectedRange = NSRange(location: firstWrap.location + markerLength,
                                       length: NSMaxRange(lastWrap) + added - markerLength * 2 - firstWrap.location)
        }

        private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 }

        /// The symbols around the styled run under the cursor, in document offsets.
        private func styledSpan(_ style: InlineStyle, at selection: NSRange, in tv: UITextView) -> (open: NSRange, close: NSRange)? {
            guard let map = InlineMap(tv: tv, at: selection.location) else { return nil }
            let local = selection.location - map.contentStart
            let candidates = selection.length > 0 ? [local] : [local - 1, local]
            guard let hit = candidates.first(where: { map.has(style, at: $0) && !map.syntax[$0] }) else { return nil }
            var low = hit
            var high = hit + 1
            while low > 0, map.has(style, at: low - 1) { low -= 1 }
            while high < map.styles.count, map.has(style, at: high) { high += 1 }
            // Italic uses one symbol, code any number of backticks, the rest two.
            let maxLength = style == .italic ? 1 : style == .code ? .max : 2
            let open = map.delimiter(endingAt: low, maxLength: maxLength)
            let close = map.delimiter(startingAt: high, maxLength: maxLength)
            guard open.length > 0, close.length > 0 else { return nil }
            return (NSRange(location: map.contentStart + open.location, length: open.length),
                    NSRange(location: map.contentStart + close.location, length: close.length))
        }

        func reportFormatState(_ tv: UITextView) {
            let ns = tv.text as NSString
            let lineRange = ns.lineRange(for: NSRange(location: min(tv.selectedRange.location, ns.length), length: 0))
            var lineText = ns.substring(with: lineRange)
            if lineText.hasSuffix("\n") { lineText.removeLast() }
            let line = NoteParser.parseLine(lineText, index: 0)
            var state = FormatState()
            switch line.kind {
            case .todo: state.block = .todo
            case .bullet: state.block = .bullet
            case .numbered: state.block = .numbered
            case .quote: state.block = .quote
            case .heading(let level): state.headingLevel = level
            default: break
            }
            state.canIndent = line.isListItem && line.indent < NoteParser.maxIndent
            state.canOutdent = line.isListItem && line.indent > 0
            if let map = InlineMap(tv: tv, at: tv.selectedRange.location) {
                let local = tv.selectedRange.location - map.contentStart
                let index = tv.selectedRange.length > 0 ? local : local - 1
                if index >= 0, index < map.styles.count, !map.syntax[index] {
                    state.inline = map.styles[index].subtracting(.link)
                }
            }
            parent.onFormatState(state)
        }

        // MARK: Styling

        private var baseAttributes: [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = EditorLayout.lineSpacing
            return [
                .font: parent.font.uiFont(size: parent.size),
                .foregroundColor: UIColor(hex: parent.theme.text),
                .paragraphStyle: paragraph,
            ]
        }

        func restyle(_ tv: UITextView) {
            let theme = parent.theme
            tv.tintColor = UIColor(hex: theme.editorCaret)
            tv.keyboardAppearance = theme.isDark ? .dark : .light
            let accent = UIColor(hex: theme.main)
            let sub = UIColor(hex: theme.sub)
            let textColor = UIColor(hex: theme.text)
            let base = baseAttributes
            let storage = tv.textStorage
            let length = (tv.text as NSString).length
            storage.beginEditing()
            storage.setAttributes(base, range: NSRange(location: 0, length: length))
            var location = 0
            for (index, raw) in NoteParser.rawLines(tv.text).enumerated() {
                let line = NoteParser.parseLine(raw, index: index)
                let lineLength = (raw as NSString).length
                let prefixLength = (line.prefix as NSString).length
                let prefixRange = NSRange(location: location, length: prefixLength)
                let contentStart = location + prefixLength
                var size = parent.size
                var bold = false
                var color = textColor
                switch line.kind {
                case .todo(let checked):
                    storage.addAttribute(.foregroundColor, value: accent, range: prefixRange)
                    if checked {
                        color = sub
                        storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: sub],
                                              range: NSRange(location: contentStart, length: lineLength - prefixLength))
                    }
                case .bullet, .numbered:
                    storage.addAttribute(.foregroundColor, value: accent, range: prefixRange)
                case .quote:
                    storage.addAttribute(.foregroundColor, value: accent, range: prefixRange)
                    color = textColor.withAlphaComponent(0.8)
                case .heading(let level):
                    size = parent.size * HeadingScale.factor(level: level, compact: false)
                    bold = true
                    storage.addAttributes([.foregroundColor: sub, .font: parent.font.uiFont(size: size)], range: prefixRange)
                case .divider:
                    storage.addAttribute(.foregroundColor, value: sub, range: NSRange(location: location, length: lineLength))
                default:
                    break
                }
                for piece in InlineMarkdown.pieces(line.content) {
                    let range = NSRange(location: contentStart + piece.range.location, length: piece.range.length)
                    let style = piece.style
                    var attributes: [NSAttributedString.Key: Any] = [:]
                    if piece.isSyntax {
                        attributes[.font] = parent.font.uiFont(size: size)
                        attributes[.foregroundColor] = sub
                    } else {
                        attributes[.font] = style.contains(.code)
                            ? NoteFont.codeUIFont(size: size, bold: bold || style.contains(.bold), italic: style.contains(.italic))
                            : parent.font.uiFont(size: size, bold: bold || style.contains(.bold), italic: style.contains(.italic))
                        attributes[.foregroundColor] = style.contains(.link) ? accent : color
                        if style.contains(.strike) {
                            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            attributes[.strikethroughColor] = color
                        }
                        if style.contains(.code) { attributes[.backgroundColor] = textColor.withAlphaComponent(0.12) }
                        if style.contains(.highlight) { attributes[.backgroundColor] = accent.highlighterTint }
                        if style.contains(.link) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    }
                    storage.addAttributes(attributes, range: range)
                }
                location += lineLength + 1
            }
            storage.endEditing()
            tv.typingAttributes = base
        }
    }
}

/// Where each character of the cursor's line sits in the inline Markdown:
/// its styles and whether it's a symbol.
private struct InlineMap {
    let contentStart: Int
    var styles: [InlineStyle]
    var syntax: [Bool]
    private let source: NSString

    init?(tv: UITextView, at location: Int) {
        let ns = tv.text as NSString
        guard location <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
        var lineText = ns.substring(with: lineRange)
        if lineText.hasSuffix("\n") { lineText.removeLast() }
        let line = NoteParser.parseLine(lineText, index: 0)
        guard line.kind != .blank, line.kind != .divider else { return nil }
        contentStart = lineRange.location + (line.prefix as NSString).length
        source = line.content as NSString
        styles = Array(repeating: [], count: source.length)
        syntax = Array(repeating: false, count: source.length)
        for piece in InlineMarkdown.pieces(line.content) {
            for i in piece.range.location..<NSMaxRange(piece.range) {
                styles[i] = piece.style
                syntax[i] = piece.isSyntax
            }
        }
    }

    func has(_ style: InlineStyle, at i: Int) -> Bool {
        i >= 0 && i < styles.count && styles[i].contains(style)
    }

    /// The run of matching symbols that ends right before `index`.
    func delimiter(endingAt index: Int, maxLength: Int) -> NSRange {
        guard index > 0, syntax[index - 1] else { return NSRange(location: index, length: 0) }
        let char = source.character(at: index - 1)
        var start = index - 1
        while start > 0, syntax[start - 1], source.character(at: start - 1) == char, index - start < maxLength { start -= 1 }
        return NSRange(location: start, length: index - start)
    }

    /// The run of matching symbols that starts at `index`.
    func delimiter(startingAt index: Int, maxLength: Int) -> NSRange {
        guard index < syntax.count, syntax[index] else { return NSRange(location: index, length: 0) }
        let char = source.character(at: index)
        var end = index + 1
        while end < syntax.count, syntax[end], source.character(at: end) == char, end - index < maxLength { end += 1 }
        return NSRange(location: index, length: end - index)
    }
}
