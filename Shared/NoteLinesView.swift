import AppIntents
import SwiftUI

// MARK: - Inline text

extension InlineMarkdown {
    /// One line's content as styled text. Every style is baked into the attributed string:
    /// widgets and Live Activities drop view modifiers like `.strikethrough` when they archive
    /// the view, but keep (most) attributes.
    ///
    /// `onWidget`: drawn by a widget or Live Activity, where a plain `.single` strikethrough and
    /// underline survive but coloured lines and background colours are dropped. Highlights
    /// show in the accent colour there instead of as a coloured wash.
    static func attributed(_ content: String, font: NoteFont, size: CGFloat, color: Color, accent: Color,
                           bold baseBold: Bool = false, struck: Bool = false, onWidget: Bool = false,
                           tappableLinks: Bool = false) -> AttributedString {
        var result = AttributedString()
        for run in runs(content) {
            var piece = AttributedString(run.text)
            let style = run.style
            // On widgets a highlight can't have its wash, and in themes whose accent matches
            // the text the colour alone wouldn't show, so it's bold there as well.
            let bold = baseBold || style.contains(.bold) || (onWidget && style.contains(.highlight))
            let italic = style.contains(.italic)
            piece.swiftUI.font = style.contains(.code)
                ? NoteFont.codeFont(size: size, bold: bold, italic: italic)
                : font.font(size: size, bold: bold, italic: italic)
            let tinted = style.contains(.link) || (onWidget && style.contains(.highlight))
            piece.swiftUI.foregroundColor = tinted ? accent : color
            if struck || style.contains(.strike) {
                // The line takes the text's own colour.
                piece.swiftUI.strikethroughStyle = .single
            }
            if style.contains(.link) {
                piece.swiftUI.underlineStyle = .single
                if tappableLinks, let url = run.url.flatMap(URL.init(string:)), url.scheme != nil {
                    piece.link = url
                }
            }
            if !onWidget {
                if style.contains(.code) { piece.swiftUI.backgroundColor = color.opacity(0.12) }
                if style.contains(.highlight) { piece.swiftUI.backgroundColor = accent.highlighterTint }
            }
            result += piece
        }
        return result
    }
}

// MARK: - Lines

/// Draws a parsed note: paragraphs, headings, lists, checkboxes, quotes and dividers.
struct NoteLinesView: View {
    enum Interaction {
        case none
        /// Checkboxes run `ToggleItemIntent` (widgets, Live Activity).
        case intents
        /// Checkboxes call back into the app.
        case action((Int) -> Void)
    }

    let lines: [NoteLine]
    let font: NoteFont
    let size: CGFloat
    let text: Color
    let sub: Color
    let accent: Color
    var spacing: CGFloat = 5
    var interaction: Interaction = .none
    var lineLimit: Int? = 3
    /// Drawn on a widget or the Lock Screen: flatter headings, and only the styles that survive there.
    var compact = false
    var tappableLinks = false

    /// Width of the column that holds bullets, numbers and checkboxes.
    private var markerWidth: CGFloat { size * 1.4 }
    private var indentStep: CGFloat { size * 1.15 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(lines) { line in
                row(line)
                    .padding(.leading, CGFloat(line.indent) * indentStep)
            }
        }
    }

    private func inline(_ line: NoteLine, size: CGFloat? = nil, bold: Bool = false, color: Color? = nil,
                        struck: Bool = false) -> AttributedString {
        InlineMarkdown.attributed(line.content, font: font, size: size ?? self.size, color: color ?? text, accent: accent,
                                  bold: bold, struck: struck, onWidget: compact, tappableLinks: tappableLinks)
    }

    @ViewBuilder
    private func row(_ line: NoteLine) -> some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: size * 0.35)
        case .divider:
            Capsule()
                .fill(sub.opacity(0.45))
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, size * 0.3)
                .accessibilityHidden(true)
        case .heading(let level):
            Text(inline(line, size: size * HeadingScale.factor(level: level, compact: compact), bold: true))
                .lineLimit(lineLimit)
                .accessibilityAddTraits(.isHeader)
        case .text:
            Text(inline(line))
                .lineLimit(lineLimit)
        case .quote:
            Text(inline(line, color: text.opacity(0.8)))
                .lineLimit(lineLimit)
                .padding(.leading, size * 0.75)
                .overlay(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.6)).frame(width: 3)
                }
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                bulletMarker(level: line.indent)
                    .frame(width: markerWidth, alignment: .leading)
                    .accessibilityHidden(true)
                Text(inline(line)).lineLimit(lineLimit)
            }
        case .numbered:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(line.ordinal ?? 1).")
                    .font(font.font(size: size, bold: true))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .fixedSize()
                    .frame(minWidth: markerWidth, alignment: .leading)
                    .padding(.trailing, line.ordinal ?? 1 >= 10 ? size * 0.3 : 0)
                Text(inline(line)).lineLimit(lineLimit)
            }
        case .todo(let checked):
            todoRow(line, checked: checked)
        }
    }

    @ViewBuilder
    private func bulletMarker(level: Int) -> some View {
        switch level {
        case 0:
            Text("•").font(font.font(size: size, bold: true)).foregroundStyle(accent)
        case 1:
            Text("◦").font(font.font(size: size, bold: true)).foregroundStyle(accent)
        default:
            Text("▪︎").font(font.font(size: size * 0.8)).foregroundStyle(accent)
        }
    }

    @ViewBuilder
    private func todoRow(_ line: NoteLine, checked: Bool) -> some View {
        let state = checked ? "Checked" : "Unchecked"
        let label = Text(inline(line, color: checked ? sub : text, struck: checked))
            .lineLimit(lineLimit)
            .contentTransition(.opacity)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            switch interaction {
            case .none:
                checkboxIcon(checked)
                    .frame(width: markerWidth, alignment: .leading)
                    .accessibilityHidden(true)
                label
                    .accessibilityLabel(line.plainContent)
                    .accessibilityValue(state)
            case .intents:
                // Only the box ticks. The text is left alone so a tap there opens the app,
                // like the Reminders widget.
                Button(intent: ToggleItemIntent(line: line.id, content: line.content, wasChecked: checked)) {
                    checkboxIcon(checked)
                        .frame(width: markerWidth, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(line.plainContent)
                .accessibilityValue(state)
                .accessibilityAddTraits(.isToggle)
                label.accessibilityHidden(true)
            case .action(let toggle):
                // In the app only the box toggles; tapping the text edits the note.
                Button { toggle(line.id) } label: {
                    checkboxIcon(checked)
                        .frame(width: markerWidth, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .padding(.vertical, -8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(line.plainContent)
                .accessibilityValue(state)
                .accessibilityAddTraits(.isToggle)
                label.accessibilityHidden(true)
            }
        }
    }

    private func checkboxIcon(_ checked: Bool) -> some View {
        Image(systemName: checked ? "checkmark.square.fill" : "square")
            .font(.system(size: size * 0.98, weight: .semibold))
            .foregroundStyle(checked ? accent : accent.opacity(0.85))
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Splits long, short-itemed lists into two columns so more fits on small surfaces.
struct FittedNoteLines: View {
    let lines: [NoteLine]
    let maxLines: Int
    let font: NoteFont
    let size: CGFloat
    let text: Color
    let sub: Color
    let accent: Color
    var spacing: CGFloat = 4
    var interaction: NoteLinesView.Interaction = .none
    /// Two columns only make sense where there's horizontal room (not small widgets / Watch).
    var allowsColumns = true
    /// A line that was just ticked; it isn't hidden with the other finished items yet.
    var justTicked: Int? = nil

    var body: some View {
        let useColumns = allowsColumns
            && lines.count > maxLines
            && lines.count <= maxLines * 2
            && lines.allSatisfy { ($0.isListItem || $0.kind == .text) && $0.indent == 0 && $0.plainContent.count <= 18 }
        if useColumns {
            let half = (lines.count + 1) / 2
            HStack(alignment: .top, spacing: 14) {
                column(Array(lines.prefix(half)))
                column(Array(lines.dropFirst(half)))
            }
        } else if lines.count > maxLines {
            let withoutSpacers = lines.filter { $0.kind != .blank && $0.kind != .divider }
            if withoutSpacers.count <= maxLines {
                // Dropping blank lines and dividers is enough; no "+N more" needed.
                column(withoutSpacers)
            } else {
                let fitted = Self.fit(lines, into: maxLines - 1, keeping: justTicked)
                VStack(alignment: .leading, spacing: spacing) {
                    column(fitted.shown)
                    if !fitted.summary.isEmpty {
                        Text(fitted.summary)
                            .font(font.font(size: size * 0.85))
                            .foregroundStyle(sub)
                    }
                }
            }
        } else {
            column(lines)
        }
    }

    /// When space runs out, hide ticked-off items first so open tasks stay visible.
    /// `keeping` is a just-ticked line that stays put so the tick can be seen.
    static func fit(_ lines: [NoteLine], into slots: Int, keeping kept: Int? = nil) -> (shown: [NoteLine], summary: String) {
        var shown = lines
        var hiddenDone = 0
        while shown.count > slots, let index = shown.lastIndex(where: { $0.isChecked && $0.id != kept }) {
            shown.remove(at: index)
            hiddenDone += 1
        }
        while shown.count > slots, let index = shown.lastIndex(where: { $0.kind == .blank || $0.kind == .divider }) {
            shown.remove(at: index)
        }
        let hiddenOther = max(0, shown.count - slots)
        shown = Array(shown.prefix(slots))
        var parts: [String] = []
        if hiddenOther > 0 { parts.append("+\(hiddenOther) more") }
        if hiddenDone > 0 { parts.append("\(hiddenDone) done") }
        return (shown, parts.joined(separator: " · "))
    }

    private func column(_ lines: [NoteLine]) -> some View {
        NoteLinesView(lines: lines, font: font, size: size, text: text, sub: sub, accent: accent,
                      spacing: spacing, interaction: interaction, lineLimit: 1, compact: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Live Activity (Lock Screen) content

/// Colours for the Lock Screen presentation, depending on the chosen style.
///
/// iOS draws the Lock Screen view once for light and once for dark, but it can show the text
/// from one pass on top of the background tint from the other. So anything that changes
/// between light and dark is painted inside the view (`card`), where it always matches the
/// text, and only colours that never change go to iOS (`platterTint`, `systemActionColor`).
struct LivePalette {
    /// Painted behind the list inside the Live Activity's own view.
    let card: Color?
    /// Handed to iOS for the card it draws behind the view (nil = the system's own background).
    let platterTint: Color?
    /// Text on the buttons iOS adds to the card, such as "Allow Live Activities?" (nil = system default).
    let systemActionColor: Color?
    let text: Color
    let sub: Color
    let accent: Color

    init(style: LiveStyle, theme: Theme) {
        switch style {
        case .theme:
            card = theme.bgColor
            platterTint = nil
            systemActionColor = nil
            text = theme.textColor
            sub = theme.subColor
            accent = theme.mainColor
        case .glass:
            card = nil
            platterTint = Color.black.opacity(0.42)
            systemActionColor = .white
            text = .white
            sub = .white.opacity(0.55)
            accent = theme.islandAccent
        case .clear:
            card = nil
            platterTint = .clear
            systemActionColor = .white
            text = .white
            sub = .white.opacity(0.6)
            accent = theme.islandAccent
        }
    }
}

/// The Lock Screen Live Activity. Shared so Settings can show a faithful preview.
struct LiveNoteView: View {
    let state: NoteActivityAttributes.ContentState
    var isStale: Bool = false
    var interactive: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = state.theme(for: scheme)
        let palette = LivePalette(style: state.style, theme: theme)
        let lines = NoteParser.visibleLines(state.text)
        let size = state.textSize.livePointSize
        let maxLines = [7, 6, 5][state.textSize.rawValue]

        Group {
            if isStale && state.relaying {
                refreshBar(palette: palette, size: size)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if lines.isEmpty {
                        Text("Your list is empty. Open mynote to add something.")
                            .font(state.font.font(size: size))
                            .foregroundStyle(palette.sub)
                    } else {
                        FittedNoteLines(
                            lines: lines,
                            maxLines: isStale ? maxLines - 1 : maxLines,
                            font: state.font,
                            size: size,
                            text: palette.text,
                            sub: palette.sub,
                            accent: palette.accent,
                            spacing: 3,
                            interaction: interactive ? .intents : .none,
                            justTicked: state.justTicked
                        )
                    }
                    if isStale {
                        refreshBar(palette: palette, size: size * 0.9)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .shadow(color: state.style == .clear ? .black.opacity(0.35) : .clear, radius: 3, y: 1)
    }

    @ViewBuilder
    private func refreshBar(palette: LivePalette, size: CGFloat) -> some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: size * 1.15, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text("Tap to refresh your list")
                .font(state.font.font(size: size))
                .foregroundStyle(palette.text)
            Spacer(minLength: 0)
        }
        if isStale && state.relaying {
            Group {
                if interactive {
                    Button(intent: KeepOnLockScreenIntent()) { label }.buttonStyle(.plain)
                } else {
                    label
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        } else if interactive {
            Button(intent: KeepOnLockScreenIntent()) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

// MARK: - Widget content

/// The home-screen widget's note. Shared so Settings can preview it.
struct WidgetNoteContent: View {
    let text: String
    let theme: Theme
    let font: NoteFont
    let size: CGFloat
    let maxLines: Int
    var interactive: Bool = true
    var allowsColumns: Bool = true

    var body: some View {
        let lines = NoteParser.visibleLines(text)
        if lines.isEmpty {
            Text("Tap to write your list")
                .font(font.font(size: size))
                .foregroundStyle(theme.subColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            FittedNoteLines(
                lines: lines,
                maxLines: maxLines,
                font: font,
                size: size,
                text: theme.textColor,
                sub: theme.subColor,
                accent: theme.mainColor,
                spacing: 3,
                interaction: interactive ? .intents : .none,
                allowsColumns: allowsColumns
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
