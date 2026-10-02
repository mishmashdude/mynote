import SwiftUI

struct ThemePickerView: View {
    enum Slot: String, CaseIterable, Identifiable {
        case light = "Light Mode", dark = "Dark Mode"
        var id: String { rawValue }
    }

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = AppSettings.shared

    @State private var search = ""
    @State private var slot: Slot = .light
    @State private var pickTick = 0

    private var selectedID: String {
        guard settings.matchSystem else { return settings.themeID }
        return slot == .dark ? settings.darkThemeID : settings.lightThemeID
    }

    private func matches(_ t: Theme) -> Bool {
        search.isEmpty || t.name.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        List {
            Section {
                ThemePreviewCard(theme: ThemeCatalog.theme(selectedID))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Match System Appearance", isOn: $settings.matchSystem.animation(.smooth))
                    .tint(theme.mainColor)
                if settings.matchSystem {
                    Picker("Editing", selection: $slot) {
                        ForEach(Slot.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text(settings.matchSystem
                     ? "Choose one theme for Light Mode and one for Dark Mode — mynote switches with your iPhone."
                     : "One theme, all the time. Turn on Match System Appearance to pair a light and a dark theme.")
                    .foregroundStyle(theme.subColor)
            }
            .listRowBackground(theme.cardColor)

            let preferDark = settings.matchSystem ? slot == .dark : colorScheme == .dark
            let groups: [(String, [Theme])] = preferDark
                ? [("Dark", ThemeCatalog.darkThemes), ("Light", ThemeCatalog.lightThemes)]
                : [("Light", ThemeCatalog.lightThemes), ("Dark", ThemeCatalog.darkThemes)]

            ForEach(groups, id: \.0) { title, themes in
                let visible = themes.filter(matches)
                if !visible.isEmpty {
                    Section {
                        ForEach(visible) { t in
                            Button { select(t) } label: {
                                ThemeRow(theme: t, isSelected: t.id == selectedID)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(t.bgColor)
                        }
                    } header: {
                        Text(title).foregroundStyle(theme.subColor)
                    }
                }
            }
        }
        .themedList(theme)
        .searchable(text: $search, prompt: "Search \(ThemeCatalog.all.count) themes")
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let pool = settings.matchSystem
                        ? (slot == .dark ? ThemeCatalog.darkThemes : ThemeCatalog.lightThemes)
                        : ThemeCatalog.all
                    if let random = pool.filter({ $0.id != selectedID }).randomElement() { select(random) }
                } label: {
                    Image(systemName: "dice")
                }
                .accessibilityLabel("Random theme")
            }
        }
        .sensoryFeedback(.selection, trigger: pickTick)
        .onAppear { slot = colorScheme == .dark ? .dark : .light }
    }

    private func select(_ t: Theme) {
        withAnimation(.smooth(duration: 0.3)) {
            if settings.matchSystem {
                if slot == .dark { settings.darkThemeID = t.id } else { settings.lightThemeID = t.id }
            } else {
                settings.themeID = t.id
            }
        }
        pickTick += 1
    }
}

/// A swatch row painted in the theme it represents, monkeytype style.
struct ThemeRow: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.mainColor)
            }
            Text(theme.name.lowercased())
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textColor)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                swatch(theme.mainColor)
                swatch(theme.caretColor)
                swatch(theme.subColor)
                swatch(theme.textColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(theme.cardColor, in: Capsule())
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func swatch(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 12, height: 12)
    }
}

/// A miniature mynote screen in the given theme.
struct ThemePreviewCard: View {
    let theme: Theme
    private var settings = AppSettings.shared

    init(theme: Theme) { self.theme = theme }

    var body: some View {
        ZStack {
            theme.bgColor
            VStack(spacing: 14) {
                Text("mynote")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textColor)
                NoteLinesView(
                    lines: NoteParser.parse("# \(theme.name.lowercased())\n[x] Pick a theme\n[ ] Write my list\n- Go live"),
                    font: settings.font,
                    size: 14,
                    text: theme.textColor,
                    sub: theme.subColor,
                    accent: theme.mainColor,
                    spacing: 4
                )
                .padding(16)
                .frame(width: 190, alignment: .leading)
                .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.1), radius: 12, y: 6)
                HStack(spacing: 6) {
                    Circle().fill(theme.mainColor).frame(width: 7, height: 7)
                    Text("Live")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.cardColor.opacity(0.8), in: Capsule())
            }
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(.smooth, value: theme)
    }
}
