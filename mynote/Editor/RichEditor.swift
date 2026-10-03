import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Rich Text editor: formatting shows as you type and the Markdown symbols stay
/// hidden. The note is still saved as Markdown, so widgets and the Live Activity
/// draw it exactly the same either way.
struct RichEditor: UIViewRepresentable {
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

    func makeUIView(context: Context) -> RichUITextView {
        let tv = RichUITextView()
        EditorLayout.configure(tv)
        tv.textDragInteraction?.isEnabled = false
        // Writing Tools would rewrite markers and formatting behind the editor's back.
        tv.writingToolsBehavior = .none
        let coordinator = context.coordinator
        tv.delegate = coordinator
        tv.coordinator = coordinator
        coordinator.textView = tv
        controller.editor = coordinator

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.checkboxTapped(_:)))
        tap.delegate = coordinator
        tv.addGestureRecognizer(tap)
        coordinator.checkboxTap = tap

        coordinator.load(text, into: tv)
        return tv
    }

    func updateUIView(_ tv: RichUITextView, context: Context) {
        let coordinator = context.coordinator
        let styleChanged = coordinator.parent.theme != theme || coordinator.parent.font != font || coordinator.parent.size != size
        coordinator.parent = self
        controller.editor = coordinator
        if text != coordinator.lastMarkdown, tv.markedTextRange == nil {
            coordinator.load(text, into: tv, keepSelection: true)
        } else if styleChanged, tv.markedTextRange == nil {
            coordinator.restyle(tv)
            coordinator.refreshTypingAttributes(tv)
        }
        EditorLayout.syncFocus(tv, wantsFocus: isFocused)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, NoteEditing {
        var parent: RichEditor
        weak var textView: RichUITextView?
        weak var checkboxTap: UITapGestureRecognizer?
        /// The Markdown this editor last wrote (or loaded).
        private(set) var lastMarkdown: String

        private var isProgrammatic = false
        /// The text when it was last within the character limit.
        private var lastValidText = ""
        private var lastValidAttributed = NSAttributedString()
        /// Styles picked on the formatting bar with no text selected, for the next letters typed.
        private var pendingInline: InlineStyle?
        private var pendingHeading: Int?
        /// Where the cursor lands after the edit in progress, to tell typing apart from moving.
        private var expectedCaret: Int?
        private var lastCaret = 0
        private var tappedMarker: Int?

        init(parent: RichEditor) {
            self.parent = parent
            self.lastMarkdown = parent.text
        }

        // MARK: Loading

        func load(_ markdown: String, into tv: UITextView, keepSelection: Bool = false) {
            let selection = tv.selectedRange
            isProgrammatic = true
            tv.attributedText = RichTextCodec.attributedString(from: markdown)
            isProgrammatic = false
            lastMarkdown = markdown
            restyle(tv)
            lastValidText = tv.text
            lastValidAttributed = NSAttributedString(attributedString: tv.textStorage)
            if keepSelection {
                let length = (tv.text as NSString).length
                let caret = min(selection.location, length)
                select(NSRange(location: caretOutsideMarker(caret, in: tv) ?? caret, length: 0), in: tv)
            }
            refreshTypingAttributes(tv)
            // The old undo steps describe text that no longer exists.
            DispatchQueue.main.async { [weak tv] in tv?.undoManager?.removeAllActions() }
        }

        // MARK: Delegate

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
            if isProgrammatic { return true }
            // While composing (pinyin, kana…) let the keyboard work; the limit is checked once it's committed.
            if tv.markedTextRange != nil { return true }

            if string == "\n", handleReturn(in: tv, range: range) { return false }
            if string.isEmpty, range.length == 1, handleBackspace(in: tv, range: range) { return false }

            let proposed = (tv.text as NSString).replacingCharacters(in: range, with: string)
            let proposedCount = RichTextCodec.visibleCount(proposed)
            if proposedCount > NoteParser.characterLimit, proposedCount > RichTextCodec.visibleCount(tv.text) {
                parent.onLimitHit()
                return false
            }
            expectedCaret = range.location + (string as NSString).length
            return true
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.onVisibleTextChange(!tv.text.isEmpty)
            guard !isProgrammatic, tv.markedTextRange == nil else { return }
            // The letters just typed already carry any style picked on the formatting bar.
            pendingInline = nil
            pendingHeading = nil
            if tv.undoManager?.isUndoing == true || tv.undoManager?.isRedoing == true {
                // The system may be halfway through putting text back: changing the text now
                // would throw its remaining steps off. Show and save as is, repair once it's done.
                restyle(tv)
                sync(tv)
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv, tv.markedTextRange == nil,
                          tv.undoManager?.isUndoing != true, tv.undoManager?.isRedoing != true else { return }
                    self.afterEdit(tv)
                }
                return
            }
            enforceLimit(tv)
            afterEdit(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard !isProgrammatic, tv.markedTextRange == nil else { return }
            let selection = tv.selectedRange
            if selection.length == 0, let fixed = caretOutsideMarker(selection.location, in: tv) {
                select(NSRange(location: fixed, length: 0), in: tv)
            }
            if tv.selectedRange.location != expectedCaret {
                pendingInline = nil
                pendingHeading = nil
            }
            expectedCaret = nil
            lastCaret = tv.selectedRange.location
            refreshTypingAttributes(tv)
            reportFormatState(tv)
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
            reportFormatState(tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if EditorLayout.lostFocusToPresentedSheet(tv) { return }
            if parent.isFocused { parent.isFocused = false }
            parent.onEndEditing()
        }

        func commitComposition() {
            guard let tv = textView, tv.markedTextRange != nil else { return }
            tv.unmarkText()
            afterEdit(tv)
        }

        func widthChanged(_ tv: UITextView) {
            guard tv.markedTextRange == nil else { return }
            restyle(tv)
        }

        /// The cursor never sits in front of a marker. Moving left from the start of the words
        /// hops to the line above instead.
        private func caretOutsideMarker(_ location: Int, in tv: UITextView) -> Int? {
            let ns = tv.text as NSString
            guard RichTextCodec.marker(in: tv.textStorage, at: location) != nil, isParagraphStart(location, ns) else { return nil }
            if lastCaret == location + 1, location > 0 { return location - 1 }
            return location + 1
        }

        private func isParagraphStart(_ location: Int, _ ns: NSString) -> Bool {
            location == 0 || (location <= ns.length && ns.character(at: location - 1) == 10)
        }

        // MARK: Edits

        private func afterEdit(_ tv: UITextView) {
            normalize(tv)
            restyle(tv)
            sync(tv)
            refreshTypingAttributes(tv)
            reportFormatState(tv)
        }

        /// Replaces text the way typing does, so the system's undo keeps working.
        private func replaceText(_ tv: UITextView, _ range: NSRange, _ string: String) {
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: start, offset: range.length),
                  let textRange = tv.textRange(from: start, to: end)
            else { return }
            isProgrammatic = true
            tv.replace(textRange, withText: string)
            isProgrammatic = false
        }

        private func select(_ range: NSRange, in tv: UITextView) {
            isProgrammatic = true
            tv.selectedRange = range
            isProgrammatic = false
            lastCaret = range.location
        }

        private func attach(_ block: RichBlock, at index: Int, in tv: UITextView) {
            tv.textStorage.addAttribute(.attachment, value: MarkerAttachment(block: block), range: NSRange(location: index, length: 1))
        }

        private func fitsLimit(adding count: Int, in tv: UITextView) -> Bool {
            if RichTextCodec.visibleCount(tv.text) + count <= NoteParser.characterLimit { return true }
            parent.onLimitHit()
            return false
        }

        /// Return in a list continues it, return on an empty item ends it (or steps out of the nesting).
        private func handleReturn(in tv: UITextView, range: NSRange) -> Bool {
            if range.length > 0 {
                // Like typing: the selection goes first, then Return acts on what's left. The text
                // has changed under UIKit, so the line break is always inserted here, never by it.
                replaceText(tv, range, "")
                let caret = NSRange(location: range.location, length: 0)
                select(caret, in: tv)
                afterEdit(tv)
                if !handleReturn(in: tv, range: caret), fitsLimit(adding: 1, in: tv) {
                    replaceText(tv, caret, "\n")
                    select(NSRange(location: caret.location + 1, length: 0), in: tv)
                    afterEdit(tv)
                }
                return true
            }
            let storage = tv.textStorage
            let ns = storage.string as NSString
            let paragraph = paragraph(at: range.location, in: ns)
            let marker = RichTextCodec.marker(in: storage, at: paragraph.location)
            let heading = RichTextCodec.headingLevel(in: storage, paragraph: paragraph)

            guard let marker else {
                guard heading > 0 else { return false }
                // After a heading the next line starts as normal text.
                guard fitsLimit(adding: 1, in: tv) else { return true }
                replaceText(tv, range, "\n")
                select(NSRange(location: range.location + 1, length: 0), in: tv)
                afterEdit(tv)
                return true
            }

            let block = marker.block
            let contentStart = paragraph.location + 1
            if block.kind == .divider {
                guard fitsLimit(adding: 1, in: tv) else { return true }
                replaceText(tv, NSRange(location: NSMaxRange(paragraph), length: 0), "\n")
                select(NSRange(location: NSMaxRange(paragraph) + 1, length: 0), in: tv)
                afterEdit(tv)
                return true
            }

            if NSMaxRange(paragraph) == contentStart {
                // Empty item.
                if block.indent > 0 {
                    setBlock(RichBlock(kind: block.kind, indent: block.indent - 1, checked: block.checked), at: paragraph.location, in: tv)
                } else {
                    replaceText(tv, NSRange(location: paragraph.location, length: 1), "")
                    select(NSRange(location: paragraph.location, length: 0), in: tv)
                }
                afterEdit(tv)
                return true
            }

            guard fitsLimit(adding: 1, in: tv) else { return true }
            let next = RichBlock(kind: block.kind, indent: block.indent)
            if range.length == 0, range.location <= contentStart {
                // Return at the start of the words: they move down and an empty item opens above.
                replaceText(tv, NSRange(location: paragraph.location, length: 0), "\u{FFFC}\n")
                attach(next, at: paragraph.location, in: tv)
                select(NSRange(location: contentStart + 2, length: 0), in: tv)
            } else {
                replaceText(tv, range, "\n\u{FFFC}")
                attach(next, at: range.location + 1, in: tv)
                select(NSRange(location: range.location + 2, length: 0), in: tv)
            }
            afterEdit(tv)
            return true
        }

        private func handleBackspace(in tv: UITextView, range: NSRange) -> Bool {
            let storage = tv.textStorage
            let ns = storage.string as NSString
            if let marker = RichTextCodec.marker(in: storage, at: range.location), isParagraphStart(range.location, ns) {
                // Backspace at the start of a nested item steps it out first.
                guard marker.block.indent > 0, marker.block.isListItem else { return false }
                let block = marker.block
                setBlock(RichBlock(kind: block.kind, indent: block.indent - 1, checked: block.checked), at: range.location, in: tv)
                afterEdit(tv)
                return true
            }
            if range.location < ns.length, ns.character(at: range.location) == 10 {
                // Joining a line onto a divider removes the divider instead.
                let above = paragraph(at: range.location, in: ns)
                if let marker = RichTextCodec.marker(in: storage, at: above.location), marker.block.kind == .divider {
                    replaceText(tv, NSRange(location: above.location, length: above.length + 1), "")
                    select(NSRange(location: above.location, length: 0), in: tv)
                    afterEdit(tv)
                    return true
                }
            }
            return false
        }

        private func setBlock(_ block: RichBlock, at index: Int, in tv: UITextView) {
            // A fresh attachment makes sure the new look is drawn.
            attach(block, at: index, in: tv)
        }

        /// Undoes text that slipped past the limit (a committed IME phrase, dictation).
        private func enforceLimit(_ tv: UITextView) {
            let count = RichTextCodec.visibleCount(tv.text)
            guard count > NoteParser.characterLimit, count > RichTextCodec.visibleCount(lastValidText) else { return }
            let old = lastValidText as NSString
            let new = tv.text as NSString
            var prefix = 0
            while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
            var suffix = 0
            while suffix < old.length - prefix, suffix < new.length - prefix,
                  old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
            let originalRange = NSRange(location: prefix, length: old.length - prefix - suffix)
            let original = old.substring(with: originalRange)
            replaceText(tv, NSRange(location: prefix, length: new.length - prefix - suffix), original)
            // Bring back the markers and styles that were there, not just the letters.
            if NSMaxRange(originalRange) <= lastValidAttributed.length {
                let storage = tv.textStorage
                lastValidAttributed.attributedSubstring(from: originalRange)
                    .enumerateAttributes(in: NSRange(location: 0, length: originalRange.length)) { attributes, range, _ in
                        storage.setAttributes(attributes, range: NSRange(location: prefix + range.location, length: range.length))
                    }
            }
            select(NSRange(location: prefix + (original as NSString).length, length: 0), in: tv)
            parent.onLimitHit()
        }

        /// Keeps the structure sound after any edit: markers only at the start of a line,
        /// nothing typed after a divider, and one heading level per line.
        private func normalize(_ tv: UITextView) {
            let storage = tv.textStorage
            let ns = storage.string as NSString
            var edits: [(range: NSRange, string: String)] = []
            for i in stride(from: ns.length - 1, through: 0, by: -1) where ns.character(at: i) == RichTextCodec.markerUnit {
                let startsLine = isParagraphStart(i, ns)
                let isMarker = storage.attribute(.attachment, at: i, effectiveRange: nil) is MarkerAttachment
                if !(startsLine && isMarker) { edits.append((NSRange(location: i, length: 1), "")) }
            }
            for paragraph in RichTextCodec.paragraphRanges(ns) where paragraph.length > 1 {
                if RichTextCodec.marker(in: storage, at: paragraph.location)?.block.kind == .divider {
                    edits.append((NSRange(location: paragraph.location + 1, length: 0), "\n"))
                }
            }
            if !edits.isEmpty {
                var selection = tv.selectedRange
                for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
                    replaceText(tv, edit.range, edit.string)
                    let delta = (edit.string as NSString).length - edit.range.length
                    func moved(_ location: Int) -> Int {
                        if location >= NSMaxRange(edit.range) { return location + delta }
                        if location > edit.range.location { return edit.range.location + (edit.string as NSString).length }
                        return location
                    }
                    let end = moved(NSMaxRange(selection))
                    selection.location = moved(selection.location)
                    selection.length = max(0, end - selection.location)
                }
                select(selection, in: tv)
            }

            // Headings: the first letter decides for the whole line; list lines are never headings.
            let text = storage.string as NSString
            storage.beginEditing()
            for paragraph in RichTextCodec.paragraphRanges(text) where paragraph.length > 0 {
                if RichTextCodec.marker(in: storage, at: paragraph.location) != nil {
                    storage.removeAttribute(.noteHeading, range: paragraph)
                } else if let level = storage.attribute(.noteHeading, at: paragraph.location, effectiveRange: nil) as? Int, level > 0 {
                    storage.addAttribute(.noteHeading, value: level, range: paragraph)
                } else {
                    storage.removeAttribute(.noteHeading, range: paragraph)
                }
            }
            storage.endEditing()
        }

        private func sync(_ tv: UITextView) {
            guard tv.markedTextRange == nil else { return }
            if RichTextCodec.visibleCount(tv.text) <= NoteParser.characterLimit {
                lastValidText = tv.text
                lastValidAttributed = NSAttributedString(attributedString: tv.textStorage)
            }
            var lossy = false
            let markdown = RichTextCodec.markdown(from: tv.textStorage, lossy: &lossy)
            lastMarkdown = markdown
            if parent.text != markdown { parent.text = markdown }
            if lossy {
                // Some formatting can't be written in Markdown (rare): show exactly what was saved.
                load(markdown, into: tv, keepSelection: true)
            }
        }

        // MARK: Checkboxes

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === checkboxTap, let tv = textView else { return true }
            tappedMarker = todoMarker(at: gesture.location(in: tv), in: tv)
            return tappedMarker != nil
        }

        /// The text view's own taps wait to see whether a tap was on a checkbox.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            gesture === checkboxTap && other is UITapGestureRecognizer && other !== gesture
        }

        @objc func checkboxTapped(_ gesture: UITapGestureRecognizer) {
            guard let tv = textView, tv.markedTextRange == nil, let index = tappedMarker,
                  let marker = RichTextCodec.marker(in: tv.textStorage, at: index), marker.block.kind == .todo
            else { return }
            var block = marker.block
            block.checked.toggle()
            setBlock(block, at: index, in: tv)
            UISelectionFeedbackGenerator().selectionChanged()
            afterEdit(tv)
        }

        private func todoMarker(at point: CGPoint, in tv: UITextView) -> Int? {
            guard let position = tv.closestPosition(to: point) else { return nil }
            let offset = tv.offset(from: tv.beginningOfDocument, to: position)
            for candidate in [offset, offset - 1] {
                guard let marker = RichTextCodec.marker(in: tv.textStorage, at: candidate), marker.block.kind == .todo,
                      let start = tv.position(from: tv.beginningOfDocument, offset: candidate),
                      let end = tv.position(from: start, offset: 1),
                      let range = tv.textRange(from: start, to: end)
                else { continue }
                if tv.firstRect(for: range).insetBy(dx: -10, dy: -6).contains(point) { return candidate }
            }
            return nil
        }

        // MARK: Copy and paste

        /// Copies the selection as plain text for other apps and as Markdown for mynote.
        func copySelection(_ tv: UITextView) -> Bool {
            let selection = tv.selectedRange
            guard selection.length > 0 else { return false }
            let markdown = RichTextCodec.markdown(from: tv.textStorage.attributedSubstring(from: selection))
            UIPasteboard.general.items = [[
                UTType.utf8PlainText.identifier: markdown,
                RichTextCodec.markdownPasteboardType: markdown,
            ]]
            return true
        }

        func deleteSelection(_ tv: UITextView) {
            let selection = tv.selectedRange
            guard selection.length > 0 else { return }
            replaceText(tv, selection, "")
            select(NSRange(location: selection.location, length: 0), in: tv)
            afterEdit(tv)
        }

        /// Pasted text is read as Markdown, so lists and bold carry over.
        func paste(into tv: UITextView) -> Bool {
            let board = UIPasteboard.general
            let markdown: String
            if let value = board.value(forPasteboardType: RichTextCodec.markdownPasteboardType) as? String {
                markdown = value
            } else if let data = board.data(forPasteboardType: RichTextCodec.markdownPasteboardType),
                      let value = String(data: data, encoding: .utf8) {
                markdown = value
            } else if let value = board.string {
                markdown = value
            } else {
                return false
            }
            insert(markdown: markdown.replacingOccurrences(of: "\r\n", with: "\n"), in: tv)
            return true
        }

        private func insert(markdown: String, in tv: UITextView) {
            let storage = tv.textStorage
            let selection = tv.selectedRange
            let selected = (tv.text as NSString).substring(with: selection)
            let room = NoteParser.characterLimit - RichTextCodec.visibleCount(tv.text) + RichTextCodec.visibleCount(selected)
            var pasted = RichTextCodec.attributedString(from: markdown)
            if RichTextCodec.visibleCount(pasted.string) > room {
                pasted = Self.truncated(pasted, toVisible: max(0, room))
                parent.onLimitHit()
            }
            guard pasted.length > 0 else { return }
            // Pasted lines that start with their own list marker begin on a line of their own.
            let ns = tv.text as NSString
            let current = paragraph(at: selection.location, in: ns)
            let wordsStart = RichTextCodec.marker(in: storage, at: current.location) == nil ? current.location : current.location + 1
            if selection.location > wordsStart, RichTextCodec.marker(in: pasted, at: 0) != nil,
               RichTextCodec.visibleCount(tv.text) + RichTextCodec.visibleCount(pasted.string) < NoteParser.characterLimit {
                pasted.insert(NSAttributedString(string: "\n"), at: 0)
            }
            replaceText(tv, selection, pasted.string)
            pasted.enumerateAttributes(in: NSRange(location: 0, length: pasted.length)) { attributes, range, _ in
                storage.setAttributes(attributes, range: NSRange(location: selection.location + range.location, length: range.length))
            }
            select(NSRange(location: selection.location + pasted.length, length: 0), in: tv)
            afterEdit(tv)
        }

        private static func truncated(_ text: NSMutableAttributedString, toVisible limit: Int) -> NSMutableAttributedString {
            let ns = text.string as NSString
            var visible = 0
            var index = 0
            while index < ns.length {
                let character = ns.rangeOfComposedCharacterSequence(at: index)
                let isMarker = character.length == 1 && ns.character(at: index) == RichTextCodec.markerUnit
                if !isMarker {
                    if visible == limit { break }
                    visible += 1
                }
                index = NSMaxRange(character)
            }
            return NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: index)))
        }

        // MARK: Formatting bar

        func perform(_ action: FormatAction) {
            guard let tv = textView, tv.markedTextRange == nil else { return }
            switch action {
            case .inline(let style): toggleInline(style, in: tv)
            case .block(let format): toggleBlock(format, in: tv)
            case .heading: cycleHeading(in: tv)
            case .indent: shiftIndent(by: 1, in: tv)
            case .outdent: shiftIndent(by: -1, in: tv)
            case .divider: insertDivider(in: tv)
            }
        }

        private func paragraph(at location: Int, in ns: NSString) -> NSRange {
            var range = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
            if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
            return range
        }

        /// The paragraphs the selection touches (without their line breaks).
        private func touchedParagraphs(_ tv: UITextView) -> [NSRange] {
            let ns = tv.text as NSString
            let selection = tv.selectedRange
            let all = RichTextCodec.paragraphRanges(ns)
            let touched = all.filter { p in
                if selection.length == 0 { return selection.location >= p.location && selection.location <= NSMaxRange(p) }
                return NSMaxRange(selection) > p.location && selection.location <= NSMaxRange(p)
                    && !(NSMaxRange(selection) == p.location && p.location > selection.location)
            }
            return touched.isEmpty ? [paragraph(at: selection.location, in: ns)] : touched
        }

        private func toggleInline(_ style: InlineStyle, in tv: UITextView) {
            let storage = tv.textStorage
            let selection = tv.selectedRange
            if selection.length == 0 {
                let current = InlineStyle(rawValue: tv.typingAttributes[.noteInline] as? Int ?? 0)
                pendingInline = current.symmetricDifference(style)
                refreshTypingAttributes(tv)
                reportFormatState(tv)
                return
            }
            let ns = storage.string as NSString
            var everywhere = true
            storage.enumerateAttribute(.noteInline, in: selection) { value, range, _ in
                guard Self.hasWords(ns.substring(with: range)) else { return }
                if !InlineStyle(rawValue: value as? Int ?? 0).contains(style) { everywhere = false }
            }
            storage.beginEditing()
            storage.enumerateAttribute(.noteInline, in: selection) { value, range, _ in
                var updated = InlineStyle(rawValue: value as? Int ?? 0)
                if everywhere { updated.remove(style) } else { updated.insert(style) }
                if updated.isEmpty {
                    storage.removeAttribute(.noteInline, range: range)
                } else {
                    storage.addAttribute(.noteInline, value: updated.rawValue, range: range)
                }
            }
            storage.endEditing()
            afterEdit(tv)
        }

        private static func hasWords(_ text: String) -> Bool {
            text.contains { $0 != RichTextCodec.markerCharacter && $0 != "\n" }
        }

        private static func kind(for format: BlockFormat) -> RichBlock.Kind {
            switch format {
            case .todo: .todo
            case .bullet: .bullet
            case .numbered: .numbered
            case .quote: .quote
            }
        }

        private func toggleBlock(_ format: BlockFormat, in tv: UITextView) {
            let storage = tv.textStorage
            let kind = Self.kind(for: format)
            let paragraphs = touchedParagraphs(tv)
            let several = paragraphs.count > 1
            let relevant = paragraphs.filter { p in
                !(several && p.length == 0) && RichTextCodec.marker(in: storage, at: p.location)?.block.kind != .divider
            }
            guard !relevant.isEmpty else { return }
            let removing = relevant.allSatisfy { RichTextCodec.marker(in: storage, at: $0.location)?.block.kind == kind }
            var selection = tv.selectedRange
            for paragraph in relevant.reversed() {
                if let marker = RichTextCodec.marker(in: storage, at: paragraph.location) {
                    if removing {
                        replaceText(tv, NSRange(location: paragraph.location, length: 1), "")
                        selection = Self.shifted(selection, at: paragraph.location, by: -1)
                    } else if marker.block.kind != kind {
                        setBlock(RichBlock(kind: kind, indent: kind == .quote ? 0 : marker.block.indent), at: paragraph.location, in: tv)
                    }
                } else if !removing {
                    storage.removeAttribute(.noteHeading, range: paragraph)
                    replaceText(tv, NSRange(location: paragraph.location, length: 0), "\u{FFFC}")
                    attach(RichBlock(kind: kind), at: paragraph.location, in: tv)
                    selection = Self.shifted(selection, at: paragraph.location, by: 1)
                }
            }
            select(selection, in: tv)
            afterEdit(tv)
        }

        /// Moves a selection to make up for text added (positive) or removed (negative) at `index`.
        private static func shifted(_ selection: NSRange, at index: Int, by delta: Int) -> NSRange {
            func move(_ location: Int) -> Int {
                if delta > 0 { return location >= index ? location + delta : location }
                return location > index ? max(index, location + delta) : location
            }
            let start = move(selection.location)
            let end = move(NSMaxRange(selection))
            return NSRange(location: start, length: max(0, end - start))
        }

        private func cycleHeading(in tv: UITextView) {
            let storage = tv.textStorage
            let paragraphs = touchedParagraphs(tv)
            guard let first = paragraphs.first else { return }
            let current = pendingHeading ?? RichTextCodec.headingLevel(in: storage, paragraph: first)
            let next = (current + 1) % 4
            var selection = tv.selectedRange
            for paragraph in paragraphs.reversed() {
                var words = paragraph
                if let marker = RichTextCodec.marker(in: storage, at: paragraph.location) {
                    if marker.block.kind == .divider { continue }
                    replaceText(tv, NSRange(location: paragraph.location, length: 1), "")
                    selection = Self.shifted(selection, at: paragraph.location, by: -1)
                    words = NSRange(location: paragraph.location, length: paragraph.length - 1)
                }
                guard words.length > 0 else { continue }
                if next == 0 {
                    storage.removeAttribute(.noteHeading, range: words)
                } else {
                    storage.addAttribute(.noteHeading, value: next, range: words)
                }
            }
            select(selection, in: tv)
            let firstNow = paragraph(at: selection.location, in: tv.text as NSString)
            if firstNow.length == 0 { pendingHeading = next }
            afterEdit(tv)
        }

        private func shiftIndent(by step: Int, in tv: UITextView) {
            for paragraph in touchedParagraphs(tv) {
                guard let marker = RichTextCodec.marker(in: tv.textStorage, at: paragraph.location), marker.block.isListItem else { continue }
                var block = marker.block
                block.indent = max(0, min(NoteParser.maxIndent, block.indent + step))
                if block != marker.block { setBlock(block, at: paragraph.location, in: tv) }
            }
            afterEdit(tv)
        }

        private func insertDivider(in tv: UITextView) {
            let ns = tv.text as NSString
            let current = paragraph(at: tv.selectedRange.location, in: ns)
            if current.length == 0 {
                guard fitsLimit(adding: 1, in: tv) else { return }
                replaceText(tv, NSRange(location: current.location, length: 0), "\u{FFFC}\n")
                attach(RichBlock(kind: .divider), at: current.location, in: tv)
                select(NSRange(location: current.location + 2, length: 0), in: tv)
            } else {
                guard fitsLimit(adding: 2, in: tv) else { return }
                let end = NSMaxRange(current)
                replaceText(tv, NSRange(location: end, length: 0), "\n\u{FFFC}\n")
                attach(RichBlock(kind: .divider), at: end + 1, in: tv)
                select(NSRange(location: end + 3, length: 0), in: tv)
            }
            afterEdit(tv)
        }

        private func reportFormatState(_ tv: UITextView) {
            let storage = tv.textStorage
            let ns = storage.string as NSString
            let selection = tv.selectedRange
            let current = paragraph(at: selection.location, in: ns)
            var state = FormatState()
            if let block = RichTextCodec.marker(in: storage, at: current.location)?.block {
                switch block.kind {
                case .todo: state.block = .todo
                case .bullet: state.block = .bullet
                case .numbered: state.block = .numbered
                case .quote: state.block = .quote
                case .divider: break
                }
                state.canIndent = block.isListItem && block.indent < NoteParser.maxIndent
                state.canOutdent = block.isListItem && block.indent > 0
            } else {
                state.headingLevel = pendingHeading ?? RichTextCodec.headingLevel(in: storage, paragraph: current)
            }
            if selection.length > 0 {
                var common: InlineStyle?
                storage.enumerateAttribute(.noteInline, in: selection) { value, range, _ in
                    guard Self.hasWords(ns.substring(with: range)) else { return }
                    let style = InlineStyle(rawValue: value as? Int ?? 0)
                    common = common.map { $0.intersection(style) } ?? style
                }
                state.inline = common ?? []
            } else {
                state.inline = InlineStyle(rawValue: tv.typingAttributes[.noteInline] as? Int ?? 0)
            }
            parent.onFormatState(state)
        }

        // MARK: Look

        private var markerWidth: CGFloat { parent.size * 1.4 }
        private var indentStep: CGFloat { parent.size * 1.15 }

        private func baseFont(heading: Int = 0) -> UIFont {
            heading > 0
                ? parent.font.uiFont(size: parent.size * HeadingScale.factor(level: heading, compact: false), bold: true)
                : parent.font.uiFont(size: parent.size)
        }

        private func paragraphStyle(block: RichBlock?, heading: Int, markerSize: CGFloat, isFirst: Bool) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = EditorLayout.lineSpacing
            if let block, block.kind != .divider {
                let indent = CGFloat(block.indent) * indentStep
                style.firstLineHeadIndent = indent
                style.headIndent = indent + markerSize
            }
            if heading > 0, !isFirst {
                style.paragraphSpacingBefore = parent.size * 0.3
            }
            return style
        }

        /// Fonts and colours for the words of a line, plus the meaning they carry.
        private func wordAttributes(block: RichBlock?, heading: Int, inline: InlineStyle, link: String?,
                                    paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
            let theme = parent.theme
            let textColor = UIColor(hex: theme.text)
            let sub = UIColor(hex: theme.sub)
            let accent = UIColor(hex: theme.main)
            var size = parent.size
            var bold = inline.contains(.bold)
            if heading > 0 {
                size *= HeadingScale.factor(level: heading, compact: false)
                bold = true
            }
            var color = textColor
            var struck = inline.contains(.strike)
            var strikeColor = textColor
            if block?.kind == .todo, block?.checked == true {
                color = sub
                strikeColor = sub
                struck = true
            } else if block?.kind == .quote {
                color = textColor.withAlphaComponent(0.8)
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: inline.contains(.code)
                    ? NoteFont.codeUIFont(size: size, bold: bold, italic: inline.contains(.italic))
                    : parent.font.uiFont(size: size, bold: bold, italic: inline.contains(.italic)),
                .foregroundColor: link == nil ? color : accent,
                .paragraphStyle: paragraphStyle,
            ]
            if struck {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = strikeColor
            }
            if inline.contains(.code) { attributes[.backgroundColor] = textColor.withAlphaComponent(0.12) }
            if inline.contains(.highlight) { attributes[.backgroundColor] = accent.highlighterTint }
            if let link {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.noteLink] = link
            }
            if !inline.isEmpty { attributes[.noteInline] = inline.rawValue }
            if heading > 0 { attributes[.noteHeading] = heading }
            return attributes
        }

        /// Repaints everything from the meaning stored in the text: markers, fonts, colours, numbers.
        func restyle(_ tv: UITextView) {
            let theme = parent.theme
            tv.tintColor = UIColor(hex: theme.editorCaret)
            tv.keyboardAppearance = theme.isDark ? .dark : .light
            let storage = tv.textStorage
            let ns = storage.string as NSString
            let paragraphs = RichTextCodec.paragraphRanges(ns)
            let numbers = RichTextCodec.ordinals(for: paragraphs.map { RichTextCodec.role(in: storage, paragraph: $0) })
            let width = max(40, tv.bounds.width - tv.textContainerInset.left - tv.textContainerInset.right
                - tv.textContainer.lineFragmentPadding * 2)
            let art = MarkerArt.Palette(accent: UIColor(hex: theme.main), sub: UIColor(hex: theme.sub))

            storage.beginEditing()
            for (index, paragraph) in paragraphs.enumerated() {
                let marker = RichTextCodec.marker(in: storage, at: paragraph.location)
                let block = marker?.block
                let heading = block == nil ? RichTextCodec.headingLevel(in: storage, paragraph: paragraph) : 0
                let font = baseFont(heading: heading)
                var markerSize = markerWidth
                if let marker, let block {
                    marker.ordinal = numbers[index] ?? 1
                    let drawn = MarkerArt.image(for: block, ordinal: marker.ordinal, font: font, width: markerWidth,
                                                lineWidth: width - CGFloat(block.indent) * indentStep, palette: art)
                    marker.image = drawn.image
                    marker.bounds = drawn.bounds
                    markerSize = drawn.bounds.width
                }
                let style = paragraphStyle(block: block, heading: heading, markerSize: markerSize, isFirst: index == 0)
                if let marker {
                    storage.setAttributes([.attachment: marker, .paragraphStyle: style, .font: font],
                                          range: NSRange(location: paragraph.location, length: 1))
                }
                let wordsStart = marker == nil ? paragraph.location : paragraph.location + 1
                let words = NSRange(location: wordsStart, length: NSMaxRange(paragraph) - wordsStart)
                if words.length > 0 {
                    storage.enumerateAttributes(in: words) { attributes, range, _ in
                        let inline = InlineStyle(rawValue: attributes[.noteInline] as? Int ?? 0)
                        let link = attributes[.noteLink] as? String
                        storage.setAttributes(self.wordAttributes(block: block, heading: heading, inline: inline, link: link,
                                                                  paragraphStyle: style), range: range)
                    }
                }
                if NSMaxRange(paragraph) < ns.length {
                    storage.setAttributes([.paragraphStyle: style, .font: font, .foregroundColor: UIColor(hex: theme.text)],
                                          range: NSRange(location: NSMaxRange(paragraph), length: 1))
                }
            }
            storage.endEditing()
        }

        /// What the next typed letters look like: the style of the letter before the cursor,
        /// or what was just picked on the formatting bar.
        func refreshTypingAttributes(_ tv: UITextView) {
            let storage = tv.textStorage
            let ns = storage.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            let current = paragraph(at: caret, in: ns)
            let block = RichTextCodec.marker(in: storage, at: current.location)?.block
            let wordsStart = block == nil ? current.location : current.location + 1
            var inline: InlineStyle = []
            var heading = block == nil ? RichTextCodec.headingLevel(in: storage, paragraph: current) : 0
            if caret > wordsStart {
                inline = InlineStyle(rawValue: storage.attribute(.noteInline, at: caret - 1, effectiveRange: nil) as? Int ?? 0)
            } else if caret < NSMaxRange(current) {
                inline = InlineStyle(rawValue: storage.attribute(.noteInline, at: caret, effectiveRange: nil) as? Int ?? 0)
            }
            if let pendingInline { inline = pendingInline }
            if let pendingHeading { heading = pendingHeading }
            let style = paragraphStyle(block: block, heading: heading, markerSize: markerWidth, isFirst: current.location == 0)
            // Links are only made in Markdown, so typing never stretches one.
            tv.typingAttributes = wordAttributes(block: block, heading: heading, inline: inline, link: nil, paragraphStyle: style)
        }
    }
}

/// The rich editor's text view: copies and pastes Markdown, and repaints dividers when its width changes.
final class RichUITextView: NoteUITextView {
    weak var coordinator: RichEditor.Coordinator?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            // Not during layout: repainting changes the text storage.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.coordinator?.widthChanged(self)
            }
        }
    }

    override func copy(_ sender: Any?) {
        if coordinator?.copySelection(self) != true { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        if coordinator?.copySelection(self) == true {
            coordinator?.deleteSelection(self)
        } else {
            super.cut(sender)
        }
    }

    override func paste(_ sender: Any?) {
        if coordinator?.paste(into: self) != true { super.paste(sender) }
    }
}

/// Draws list markers, checkboxes, quote bars and dividers as small images.
@MainActor
enum MarkerArt {
    struct Palette {
        let accent: UIColor
        let sub: UIColor
    }

    private static var cache: [String: UIImage] = [:]

    static func image(for block: RichBlock, ordinal: Int, font: UIFont, width: CGFloat, lineWidth: CGFloat,
                      palette: Palette) -> (image: UIImage, bounds: CGRect) {
        let height = ceil(font.ascender - font.descender)
        let numberFont = UIFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold)
        let numberText = "\(ordinal)." as NSString
        var boxWidth = width
        switch block.kind {
        case .divider:
            boxWidth = max(20, lineWidth)
        case .numbered:
            let textWidth = numberText.size(withAttributes: [.font: numberFont]).width
            boxWidth = max(width, ceil(textWidth + font.pointSize * 0.45))
        default:
            break
        }
        let bounds = CGRect(x: 0, y: font.descender, width: boxWidth, height: height)
        let key = [block.kind.rawValue, "\(block.indent)", "\(block.checked)", "\(ordinal)", font.fontName,
                   "\(font.pointSize)", "\(boxWidth)", palette.accent.description, palette.sub.description].joined(separator: "|")
        if let cached = cache[key] { return (cached, bounds) }

        let baseline = font.ascender
        let image = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            switch block.kind {
            case .bullet:
                let centerY = baseline - font.xHeight / 2
                let x = font.pointSize * 0.3
                switch block.indent {
                case 0:
                    let r = font.pointSize * 0.16
                    palette.accent.setFill()
                    UIBezierPath(ovalIn: CGRect(x: x - r, y: centerY - r, width: r * 2, height: r * 2)).fill()
                case 1:
                    let r = font.pointSize * 0.15
                    palette.accent.setStroke()
                    let path = UIBezierPath(ovalIn: CGRect(x: x - r, y: centerY - r, width: r * 2, height: r * 2))
                    path.lineWidth = 1.4
                    path.stroke()
                default:
                    let side = font.pointSize * 0.26
                    palette.accent.setFill()
                    UIBezierPath(rect: CGRect(x: x - side / 2, y: centerY - side / 2, width: side, height: side)).fill()
                }
            case .numbered:
                numberText.draw(at: CGPoint(x: 0, y: baseline - numberFont.ascender),
                                withAttributes: [.font: numberFont, .foregroundColor: palette.accent])
            case .todo:
                let configuration = UIImage.SymbolConfiguration(pointSize: font.pointSize * 0.98, weight: .semibold)
                let color = block.checked ? palette.accent : palette.accent.withAlphaComponent(0.85)
                if let symbol = UIImage(systemName: block.checked ? "checkmark.square.fill" : "square", withConfiguration: configuration)?
                    .withTintColor(color, renderingMode: .alwaysOriginal) {
                    let y = baseline - font.capHeight / 2 - symbol.size.height / 2
                    symbol.draw(at: CGPoint(x: 0, y: y))
                }
            case .quote:
                palette.accent.withAlphaComponent(0.6).setFill()
                UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 3, height: height - 2), cornerRadius: 1.5).fill()
            case .divider:
                palette.sub.withAlphaComponent(0.45).setFill()
                UIBezierPath(roundedRect: CGRect(x: 0, y: height / 2 - 0.75, width: boxWidth, height: 1.5), cornerRadius: 0.75).fill()
            }
        }
        if cache.count > 400 { cache.removeAll() }
        cache[key] = image
        return (image, bounds)
    }
}
