import SwiftUI
import UIKit

/// Something the formatting bar can do to the note.
enum FormatAction: Hashable {
    case inline(InlineStyle)
    case block(BlockFormat)
    /// Cycles the current line: Heading 1, Heading 2, Heading 3, back to normal text.
    case heading
    case indent
    case outdent
    case divider
}

enum BlockFormat: Hashable {
    case todo, bullet, numbered, quote
}

/// What the cursor is sitting in, so the formatting bar can light up the right buttons.
struct FormatState: Equatable {
    var inline: InlineStyle = []
    var block: BlockFormat?
    var headingLevel = 0
    var canIndent = false
    var canOutdent = false
}

/// The two editors (Rich Text and Markdown) both answer to this.
@MainActor
protocol NoteEditing: AnyObject {
    func perform(_ action: FormatAction)
    /// Finishes any in-progress IME composition so it's saved before leaving the editor.
    func commitComposition()
}

/// Lets SwiftUI buttons reach whichever editor is on screen.
@MainActor
final class EditorController {
    weak var editor: NoteEditing?

    func perform(_ action: FormatAction) { editor?.perform(action) }
    func commitComposition() { editor?.commitComposition() }
}

/// A UITextView that knows when the text change comes from a real paste.
class NoteUITextView: UITextView {
    private(set) var isPasting = false

    override func paste(_ sender: Any?) {
        isPasting = true
        super.paste(sender)
        isPasting = false
    }
}

/// Settings both editors share.
enum EditorLayout {
    static let lineSpacing: CGFloat = 4
    static let insets = UIEdgeInsets(top: 2, left: 0, bottom: 44, right: 0)

    static func configure(_ tv: UITextView) {
        tv.backgroundColor = .clear
        tv.textContainerInset = insets
        tv.textContainer.lineFragmentPadding = 0
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.autocapitalizationType = .sentences
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
    }

    /// Keeps keyboard focus in sync with the SwiftUI `isFocused` binding.
    static func syncFocus(_ tv: UITextView, wantsFocus: Bool) {
        let somethingPresented = tv.window?.rootViewController?.presentedViewController != nil
        if wantsFocus, !tv.isFirstResponder, !somethingPresented {
            DispatchQueue.main.async {
                tv.becomeFirstResponder()
                let end = (tv.text as NSString).length
                tv.selectedRange = NSRange(location: end, length: 0)
            }
        } else if !wantsFocus, tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    /// True when a share sheet or alert from the edit menu took focus: stay in edit mode then.
    static func lostFocusToPresentedSheet(_ tv: UITextView) -> Bool {
        if let presented = tv.window?.rootViewController?.presentedViewController, !presented.isBeingDismissed {
            return true
        }
        return false
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
