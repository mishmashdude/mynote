import AppIntents
import SwiftUI

/// Draws a parsed note: plain lines, bullets, headings and checkboxes.
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

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(lines) { line in
                row(line)
            }
        }
    }

    @ViewBuilder
    private func row(_ line: NoteLine) -> some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: size * 0.35)
        case .heading:
            Text(line.content)
                .font(font.font(size: size * 1.12, bold: true))
                .foregroundStyle(text)
                .lineLimit(lineLimit)
        case .text:
            Text(line.content)
                .font(font.font(size: size))
                .foregroundStyle(text)
                .lineLimit(lineLimit)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
                Text("•")
                    .font(font.font(size: size, bold: true))
                    .foregroundStyle(accent)
                Text(line.content)
                    .font(font.font(size: size))
                    .foregroundStyle(text)
                    .lineLimit(lineLimit)
            }
        case .todo(let checked):
            todoRow(line, checked: checked)
        }
    }

    @ViewBuilder
    private func todoRow(_ line: NoteLine, checked: Bool) -> some View {
        let state = checked ? "Checked" : "Unchecked"
        switch interaction {
        case .none:
            HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
                checkboxIcon(checked)
                todoText(line, checked: checked)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.content)
            .accessibilityValue(state)
        case .intents:
            // On widgets and the Lock Screen the whole row is the tap target.
            Button(intent: ToggleItemIntent(line: line.id, content: line.content, wasChecked: checked)) {
                HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
                    checkboxIcon(checked)
                    todoText(line, checked: checked)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.content)
            .accessibilityValue(state)
            .accessibilityAddTraits(.isToggle)
        case .action(let toggle):
            // In the app only the box toggles; tapping the text edits the note.
            HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
                Button { toggle(line.id) } label: {
                    checkboxIcon(checked)
                        .padding(10)
                        .contentShape(Rectangle())
                        .padding(-10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(line.content)
                .accessibilityValue(state)
                .accessibilityAddTraits(.isToggle)
                todoText(line, checked: checked)
                    .accessibilityHidden(true)
            }
        }
    }

    private func checkboxIcon(_ checked: Bool) -> some View {
        Image(systemName: checked ? "checkmark.square.fill" : "square")
            .font(.system(size: size * 0.98, weight: .semibold))
            .foregroundStyle(checked ? accent : accent.opacity(0.85))
            .contentTransition(.symbolEffect(.replace))
    }

    private func todoText(_ line: NoteLine, checked: Bool) -> some View {
        // The strike is baked into the attributed string: widgets and Live Activities
        // drop the `.strikethrough` view modifier when archiving the view.
        var attributed = AttributedString(line.content)
        if checked {
            attributed.strikethroughStyle = .single
            attributed.strikethroughColor = UIColor(sub)
        }
        return Text(attributed)
            .font(font.font(size: size))
            .foregroundStyle(checked ? sub : text)
            .lineLimit(lineLimit)
            .contentTransition(.opacity)
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

    var body: some View {
        let useColumns = allowsColumns
            && lines.count > maxLines
            && lines.count <= maxLines * 2
            && lines.allSatisfy { $0.content.count <= 18 && $0.kind != .heading }
        if useColumns {
            let half = (lines.count + 1) / 2
            HStack(alignment: .top, spacing: 14) {
                column(Array(lines.prefix(half)))
                column(Array(lines.dropFirst(half)))
            }
        } else if lines.count > maxLines {
            let fitted = Self.fit(lines, into: maxLines - 1)
            VStack(alignment: .leading, spacing: spacing) {
                column(fitted.shown)
                Text(fitted.summary)
                    .font(font.font(size: size * 0.85))
                    .foregroundStyle(sub)
            }
        } else {
            column(lines)
        }
    }

    /// When space runs out, hide ticked-off items first so open tasks stay visible.
    static func fit(_ lines: [NoteLine], into slots: Int) -> (shown: [NoteLine], summary: String) {
        var shown = lines
        var hiddenDone = 0
        while shown.count > slots, let index = shown.lastIndex(where: \.isChecked) {
            shown.remove(at: index)
            hiddenDone += 1
        }
        while shown.count > slots, let index = shown.lastIndex(where: { $0.kind == .blank }) {
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
                      spacing: spacing, interaction: interaction, lineLimit: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Live Activity (Lock Screen) content

/// Colours for the Lock Screen presentation, depending on the chosen style.
struct LivePalette {
    let background: Color?
    let text: Color
    let sub: Color
    let accent: Color

    init(style: LiveStyle, theme: Theme) {
        switch style {
        case .theme:
            background = theme.bgColor
            text = theme.textColor
            sub = theme.subColor
            accent = theme.mainColor
        case .glass:
            background = Color.black.opacity(0.42)
            text = .white
            sub = .white.opacity(0.55)
            accent = theme.islandAccent
        case .clear:
            background = .clear
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
                            interaction: interactive ? .intents : .none
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
