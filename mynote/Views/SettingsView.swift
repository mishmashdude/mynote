import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { EditorSettingsView() } label: {
                        SettingsRow(icon: "character.cursor.ibeam", title: "Editor", value: settings.editorMode.name)
                    }
                    NavigationLink { NoteTextSettingsView() } label: {
                        SettingsRow(icon: "textformat", title: "Note Text", value: settings.font.name)
                    }
                }
                .listRowBackground(theme.cardColor)

                Section {
                    NavigationLink { WidgetInfoView() } label: {
                        SettingsRow(icon: "square.text.square", title: "Widget")
                    }
                    NavigationLink { LiveActivitySettingsView() } label: {
                        SettingsRow(icon: "iphone.gen3", title: "Live Activity")
                    }
                    NavigationLink { KeepAliveGuideView() } label: {
                        SettingsRow(icon: "pin", title: "Always on Lock Screen")
                    }
                }
                .listRowBackground(theme.cardColor)

                Section {
                    SupporterCard(style: .full)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Support mynote").foregroundStyle(theme.subColor)
                }

                Section {
                    Button { openURL(AppInfo.feedbackURL) } label: {
                        SettingsRow(icon: "bubble.left", title: "Give Feedback")
                    }
                    Button { openURL(AppInfo.reviewURL) } label: {
                        SettingsRow(icon: "star", title: "Rate mynote")
                    }
                    NavigationLink { AboutView() } label: {
                        SettingsRow(icon: "info.circle", title: "About mynote")
                    }
                }
                .listRowBackground(theme.cardColor)

                Section {
                    VStack(spacing: 6) {
                        Image("AppIconImage")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                            .padding(.bottom, 4)
                        Text("mynote")
                            .font(.headline)
                            .foregroundStyle(theme.textColor)
                        Text(AppInfo.version)
                            .font(.caption)
                            .foregroundStyle(theme.subColor)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .themedList(theme)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

struct SettingsRow: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(theme.textColor)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(theme.textColor)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(theme.subColor)
                    .lineLimit(1)
            }
        }
    }
}

extension View {
    /// Paints a List / Form with the theme's colours.
    func themedList(_ theme: Theme) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(theme.bgColor.ignoresSafeArea())
            .foregroundStyle(theme.textColor)
    }
}

// MARK: - Note text

struct NoteTextSettingsView: View {
    @Environment(\.theme) private var theme
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    NoteLinesView(
                        lines: NoteParser.visibleLines("## Make it yours\nThe *quick* brown fox jumps over the **lazy** dog\n- [x] Pick a theme\n- [ ] Choose a font\n- Try ==highlights=="),
                        font: settings.font,
                        size: settings.textSize.appPointSize,
                        text: theme.textColor,
                        sub: theme.subColor,
                        accent: theme.mainColor,
                        spacing: 6
                    )
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth, value: settings.font)
                .animation(.smooth, value: settings.textSize)
            }
            .listRowBackground(theme.cardColor)

            Section {
                Picker("Size", selection: $settings.textSize) {
                    ForEach(TextSize.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Text size is used in the app, widgets and Live Activity. The preview is close to, but not exactly, how text appears everywhere.")
                    .foregroundStyle(theme.subColor)
            }

            Section("Font") {
                ForEach(NoteFont.allCases) { font in
                    Button {
                        settings.font = font
                    } label: {
                        HStack {
                            Text(font.name)
                                .font(font.font(size: 17))
                                .foregroundStyle(theme.textColor)
                            Spacer()
                            if settings.font == font {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(theme.mainColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(theme.cardColor)
        }
        .themedList(theme)
        .navigationTitle("Note Text")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: settings.font)
    }
}

// MARK: - Widget

struct WidgetInfoView: View {
    @Environment(\.theme) private var theme
    private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 14) {
                        widgetPreview(width: 300, height: 141, maxLines: 5)
                        widgetPreview(width: 141, height: 141, maxLines: 6, allowsColumns: false)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Home Screen Widget")
                            .font(.headline)
                        Text("Touch and hold an empty area of your Home Screen until the apps jiggle, tap Edit → Add Widget, search for mynote, pick a size and tap Add Widget. Tap a checkbox to tick it right there, or tap anywhere else on the widget to open mynote.")
                            .font(.subheadline)
                            .foregroundStyle(theme.subColor)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lock Screen Widget")
                            .font(.headline)
                        Text("Touch and hold the Lock Screen, tap Customize → Lock Screen, then tap the widget area and add mynote to see your list or progress at a glance.")
                            .font(.subheadline)
                            .foregroundStyle(theme.subColor)
                    }
                }
                .padding(.vertical, 12)
            }
            .listRowBackground(theme.cardColor)
        }
        .themedList(theme)
        .navigationTitle("Widget")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func widgetPreview(width: CGFloat, height: CGFloat, maxLines: Int, allowsColumns: Bool = true) -> some View {
        let sample = NoteStore.shared.current.isEmpty
            ? "# Today\n- [x] Ship the update\n- [ ] Reply to **Sam**\n- [ ] Gym at 6\n- Coffee beans"
            : NoteStore.shared.current.text
        let widgetTheme = settings.theme(for: theme.colorScheme)
        return WidgetNoteContent(text: sample, theme: widgetTheme, font: settings.font,
                                 size: settings.textSize.widgetPointSize, maxLines: maxLines, interactive: false,
                                 allowsColumns: allowsColumns)
            .padding(16)
            .frame(width: width, height: height)
            .background(widgetTheme.cardColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(theme.textColor.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("AppIconImage")
                        .resizable()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                    Text("mynote")
                        .font(.title2.bold())
                    Text(AppInfo.version)
                        .font(.footnote)
                        .foregroundStyle(theme.subColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(theme.cardColor)

            Section {
                Button { openURL(AppInfo.supportURL) } label: { SettingsRow(icon: "questionmark.circle", title: "Support") }
                Button { openURL(AppInfo.privacyURL) } label: { SettingsRow(icon: "hand.raised", title: "Privacy Policy") }
            } footer: {
                Text("Your notes never leave your device. mynote has no accounts, no tracking and no analytics.")
                    .foregroundStyle(theme.subColor)
            }
            .listRowBackground(theme.cardColor)

            Section {
                Text("Theme palettes are adapted from much-loved open-source editor and typing themes: Dracula, Nord, Gruvbox, Catppuccin, Solarized, Rosé Pine, Tokyo Night, Everforest, Kanagawa, Ayu, Night Owl, Monokai, One Dark and the monkeytype community themes. Thank you to their creators.")
                    .font(.footnote)
                    .foregroundStyle(theme.subColor)
            } header: {
                Text("Credits").foregroundStyle(theme.subColor)
            }
            .listRowBackground(theme.cardColor)
        }
        .themedList(theme)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Editor

struct EditorSettingsView: View {
    @Environment(\.theme) private var theme
    @Bindable private var settings = AppSettings.shared

    private let sample = "## Groceries\n- [x] **Oat** milk\n- [ ] Coffee *beans*\n- Bread"

    var body: some View {
        List {
            Section {
                ForEach(EditorMode.allCases) { mode in
                    Button {
                        withAnimation(.smooth) { settings.editorMode = mode }
                    } label: {
                        modeRow(mode)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Both edit the same note, so you can switch any time. Your widget and Lock Screen look the same either way.")
                    .foregroundStyle(theme.subColor)
            }
            .listRowBackground(theme.cardColor)

            if settings.editorMode == .markdown {
                Section {
                    ForEach(Self.cheatSheet, id: \.0) { syntax, example in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(syntax)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(theme.subColor)
                                .frame(width: 128, alignment: .leading)
                            NoteLinesView(lines: NoteParser.visibleLines(example), font: settings.font, size: 15,
                                          text: theme.textColor, sub: theme.subColor, accent: theme.mainColor, lineLimit: 1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Markdown cheat sheet").foregroundStyle(theme.subColor)
                }
                .listRowBackground(theme.cardColor)
            }
        }
        .themedList(theme)
        .navigationTitle("Editor")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: settings.editorMode)
    }

    private func modeRow(_ mode: EditorMode) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(mode.name)
                        .font(.headline)
                        .foregroundStyle(theme.textColor)
                    Spacer()
                    if settings.editorMode == mode {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.mainColor)
                    }
                }
                Text(verbatim: mode == .rich
                     ? "Formatting shows as you type. Use the bar above the keyboard for lists, headings and bold."
                     : "Type Markdown and see the symbols, like **bold** and - [ ] tasks. The bar above the keyboard still helps.")
                    .font(.subheadline)
                    .foregroundStyle(theme.subColor)
                    .fixedSize(horizontal: false, vertical: true)
                preview(mode)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(settings.editorMode == mode ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func preview(_ mode: EditorMode) -> some View {
        Group {
            if mode == .rich {
                NoteLinesView(lines: NoteParser.visibleLines(sample), font: settings.font, size: 14,
                              text: theme.textColor, sub: theme.subColor, accent: theme.mainColor, spacing: 4)
            } else {
                Text(Self.markdownPreview(sample, theme: theme, font: settings.font))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The raw Markdown with its symbols dimmed, the way the Markdown editor shows it.
    private static func markdownPreview(_ markdown: String, theme: Theme, font: NoteFont) -> AttributedString {
        var result = AttributedString()
        for (index, raw) in NoteParser.rawLines(markdown).enumerated() {
            if index > 0 { result += AttributedString("\n") }
            let line = NoteParser.parseLine(raw, index: index)
            var prefix = AttributedString(line.prefix)
            prefix.swiftUI.font = font.font(size: 14)
            prefix.swiftUI.foregroundColor = line.isListItem ? theme.mainColor : theme.subColor
            result += prefix
            for piece in InlineMarkdown.pieces(line.content) {
                var part = AttributedString(piece.text)
                part.swiftUI.font = font.font(size: 14, bold: line.isHeading || piece.style.contains(.bold),
                                              italic: piece.style.contains(.italic))
                part.swiftUI.foregroundColor = piece.isSyntax ? theme.subColor : line.isChecked ? theme.subColor : theme.textColor
                result += part
            }
        }
        return result
    }

    private static let cheatSheet: [(String, String)] = [
        ("# Heading", "# Heading"),
        ("**bold**", "**bold**"),
        ("*italic*", "*italic*"),
        ("~~strike~~", "~~strike~~"),
        ("==highlight==", "==highlight=="),
        ("`code`", "`code`"),
        ("- item", "- item"),
        ("1. item", "1. item"),
        ("- [ ] task", "- [ ] task"),
        ("> quote", "> quote"),
        ("[link](url)", "[link](https://example.com)"),
        ("---", "---"),
    ]
}
