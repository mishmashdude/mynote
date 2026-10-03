import SwiftUI

/// The bar above the keyboard: lists, headings and text styles in a scrolling strip, then Done.
/// Buttons light up for the formatting under the cursor.
struct FormatBar: View {
    let theme: Theme
    let state: FormatState
    let perform: (FormatAction) -> Void
    let onDone: () -> Void

    @State private var tapTick = 0

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        tool("checklist", "Checkbox", active: state.block == .todo) { perform(.block(.todo)) }
                        tool("list.bullet", "Bulleted list", active: state.block == .bullet) { perform(.block(.bullet)) }
                        tool("list.number", "Numbered list", active: state.block == .numbered) { perform(.block(.numbered)) }
                        headingTool
                        tool("bold", "Bold", active: state.inline.contains(.bold)) { perform(.inline(.bold)) }
                        tool("italic", "Italic", active: state.inline.contains(.italic)) { perform(.inline(.italic)) }
                        tool("strikethrough", "Strikethrough", active: state.inline.contains(.strike)) { perform(.inline(.strike)) }
                        tool("highlighter", "Highlight", active: state.inline.contains(.highlight)) { perform(.inline(.highlight)) }
                        tool("chevron.left.forwardslash.chevron.right", "Code", active: state.inline.contains(.code)) {
                            perform(.inline(.code))
                        }
                        tool("text.quote", "Quote", active: state.block == .quote) { perform(.block(.quote)) }
                        tool("decrease.indent", "Move left", enabled: state.canOutdent) { perform(.outdent) }
                        tool("increase.indent", "Move right", enabled: state.canIndent) { perform(.indent) }
                        tool("minus", "Divider") { perform(.divider) }
                    }
                    .padding(.horizontal, 6)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                    }
                }
                .frame(height: 52)
                .glassEffect(.regular, in: .capsule)

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.onMainColor)
                        .frame(width: 84, height: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(theme.mainColor).interactive(), in: .capsule)
            }
        }
        .sensoryFeedback(.selection, trigger: tapTick)
    }

    private func tool(_ symbol: String, _ label: String, active: Bool = false, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button {
            tapTick += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? theme.mainColor : theme.textColor)
                .frame(width: 42, height: 42)
                .background(active ? theme.mainColor.opacity(0.18) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var headingTool: some View {
        let level = state.headingLevel
        return Button {
            tapTick += 1
            perform(.heading)
        } label: {
            Text(level > 0 ? "H\(level)" : "H")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(level > 0 ? theme.mainColor : theme.textColor)
                .frame(width: 42, height: 42)
                .background(level > 0 ? theme.mainColor.opacity(0.18) : .clear, in: Circle())
                .contentShape(Circle())
                .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Heading")
        .accessibilityValue(level > 0 ? "Level \(level)" : "Off")
        .accessibilityHint("Each tap makes the line a smaller heading, then normal text again.")
    }
}
