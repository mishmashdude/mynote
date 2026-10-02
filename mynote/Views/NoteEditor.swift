import SwiftUI
import UIKit

/// Lets SwiftUI buttons (checkbox / bullet) act on the text view's current line.
@MainActor
final class EditorController {
    enum Marker { case todo, bullet }

    fileprivate weak var textView: UITextView?
    fileprivate weak var coordinator: NoteTextView.Coordinator?

    /// Finishes any in-progress IME composition so it's saved before leaving the editor.
    func commitComposition() {
        guard let tv = textView, tv.markedTextRange != nil else { return }
        tv.unmarkText()
        coordinator?.syncNow(tv)
    }

    /// Adds, swaps or removes the list marker at the start of the current line.
    func toggle(_ marker: Marker) {
        guard let tv = textView, let coordinator else { return }
        let ns = tv.text as NSString
        let selection = tv.selectedRange
        let lineRange = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
        var lineText = ns.substring(with: lineRange)
        if lineText.hasSuffix("\n") { lineText.removeLast() }
        let parsed = NoteParser.parseLine(lineText, index: 0)
        let oldPrefixLength = (parsed.prefix as NSString).length

        let newPrefix: String = switch (marker, parsed.kind) {
        case (.todo, .todo), (.bullet, .bullet): ""
        case (.todo, _): "[ ] "
        case (.bullet, _): "- "
        }
        coordinator.replace(in: tv, range: NSRange(location: lineRange.location, length: oldPrefixLength), with: newPrefix)
        let newPrefixLength = (newPrefix as NSString).length
        let cursor = max(lineRange.location + newPrefixLength, selection.location + newPrefixLength - oldPrefixLength)
        tv.selectedRange = NSRange(location: min(cursor, (tv.text as NSString).length), length: 0)
    }
}

/// A UITextView wrapper: themed, enforces the character limit, highlights list
/// markers and continues checklists / bullets when you press return.
struct NoteTextView: UIViewRepresentable {
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

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = NoteUITextView()
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 44, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.autocapitalizationType = .sentences
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.text = text
        controller.textView = tv
        controller.coordinator = context.coordinator
        context.coordinator.restyle(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let coordinator = context.coordinator
        let styleChanged = coordinator.parent.theme != theme || coordinator.parent.font != font || coordinator.parent.size != size
        coordinator.parent = self
        controller.textView = tv
        controller.coordinator = coordinator
        if tv.text != text, tv.markedTextRange == nil {
            tv.text = text
            coordinator.acceptExternalText(text)
            coordinator.restyle(tv)
        } else if styleChanged {
            coordinator.restyle(tv)
        }
        let somethingPresented = tv.window?.rootViewController?.presentedViewController != nil
        if isFocused, !tv.isFirstResponder, !somethingPresented {
            DispatchQueue.main.async {
                tv.becomeFirstResponder()
                let end = (tv.text as NSString).length
                tv.selectedRange = NSRange(location: end, length: 0)
            }
        } else if !isFocused, tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextView
        private var isProgrammatic = false
        /// The last committed text that was within the limit.
        private var lastValidText: String

        init(parent: NoteTextView) {
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
            if tv.markedTextRange == nil {
                let length = NoteParser.countedLength(tv.text)
                if length > NoteParser.characterLimit, length > NoteParser.countedLength(lastValidText) {
                    // Something bypassed shouldChangeText (a committed IME phrase, dictation): roll it back.
                    tv.text = lastValidText
                    parent.onLimitHit()
                }
            }
            sync(tv)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            // A share sheet or alert from the edit menu took focus — stay in edit mode.
            if let presented = tv.window?.rootViewController?.presentedViewController, !presented.isBeingDismissed {
                return
            }
            if parent.isFocused { parent.isFocused = false }
            parent.onEndEditing()
        }

        /// Text set from outside (Siri, the Lock Screen, archive/restore) becomes the new baseline.
        func acceptExternalText(_ text: String) {
            if NoteParser.countedLength(text) <= NoteParser.characterLimit {
                lastValidText = text
            }
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
                // Empty item: drop the marker instead of adding another line.
                replace(in: tv, range: NSRange(location: lineRange.location, length: prefixLength), with: "")
                tv.selectedRange = NSRange(location: lineRange.location, length: 0)
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

        func syncNow(_ tv: UITextView) { sync(tv) }

        private func sync(_ tv: UITextView) {
            // Don't save or broadcast half-composed IME text.
            guard tv.markedTextRange == nil else { return }
            restyle(tv)
            if NoteParser.countedLength(tv.text) <= NoteParser.characterLimit {
                lastValidText = tv.text
            }
            if parent.text != tv.text { parent.text = tv.text }
        }

        // MARK: Styling

        private var baseAttributes: [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
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
                let contentRange = NSRange(location: location + prefixLength, length: lineLength - prefixLength)
                switch line.kind {
                case .todo(let checked):
                    storage.addAttribute(.foregroundColor, value: UIColor(hex: theme.main), range: prefixRange)
                    if checked {
                        storage.addAttribute(.foregroundColor, value: UIColor(hex: theme.sub), range: contentRange)
                    }
                case .bullet:
                    storage.addAttribute(.foregroundColor, value: UIColor(hex: theme.main), range: prefixRange)
                case .heading:
                    storage.addAttribute(.foregroundColor, value: UIColor(hex: theme.sub), range: prefixRange)
                    storage.addAttribute(.font, value: parent.font.uiFont(size: parent.size * 1.12, bold: true), range: contentRange)
                default:
                    break
                }
                location += lineLength + 1
            }
            storage.endEditing()
            tv.typingAttributes = base
        }
    }
}

/// Small progress ring that counts down the last few characters.
struct CharacterRing: View {
    let count: Int
    let limit: Int
    let theme: Theme

    private var remaining: Int { limit - count }
    private var color: Color {
        if remaining <= 0 {
            return theme.readableErrorColor
        }
        return remaining <= 20 ? Color(hex: theme.editorCaret) : theme.subColor
    }

    var body: some View {
        ZStack {
            Circle().stroke(theme.subColor.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(1, CGFloat(count) / CGFloat(limit)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if remaining <= 20 {
                Text("\(remaining)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(remaining)))
            }
        }
        .frame(width: 24, height: 24)
        .animation(.snappy, value: count)
        .accessibilityLabel("\(max(remaining, 0)) characters left")
    }
}

/// A UITextView that knows when the text change comes from a real paste.
final class NoteUITextView: UITextView {
    private(set) var isPasting = false

    override func paste(_ sender: Any?) {
        isPasting = true
        super.paste(sender)
        isPasting = false
    }
}
