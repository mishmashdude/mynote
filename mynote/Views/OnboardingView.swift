import SwiftUI

struct OnboardingView: View {
    @Environment(\.theme) private var theme
    private var settings = AppSettings.shared
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    @State private var appeared = false
    @State private var pickTick = 0

    private let featuredThemes = ["default", "serika-dark", "dracula", "nord", "gruvbox-dark", "catppuccin-mocha", "tokyo-night", "rose-pine-dawn", "solarized-light", "matrix"]

    private var tryingOn: Theme? {
        settings.previewThemeID.map(ThemeCatalog.theme).flatMap { settings.canUse($0) ? nil : $0 }
    }

    var body: some View {
        ZStack {
            theme.bgColor.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    sampleCard
                        .padding(.top, 36)
                        .scaleEffect(appeared ? 1 : 0.9)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 8) {
                        Text("mynote")
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.textColor)
                        Text(AppInfo.tagline)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(theme.subColor)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        feature("checklist", "One focused note", "Checkboxes, lists, headings and bold, in rich text or Markdown.")
                        feature("lock.iphone", "Always on your Lock Screen", "Go Live and mynote keeps your list on the Lock Screen and Dynamic Island, refreshing it on its own.")
                        feature("paintpalette", "Themes devs love", "Dracula, Nord, Gruvbox, Catppuccin and \(ThemeCatalog.all.count - 4) more. Try any of them for free.")
                    }
                    .padding(.horizontal, 28)

                    VStack(alignment: .leading, spacing: 10) {
                        // While a locked theme is tried on, the label says so (in place, so nothing moves).
                        Text(tryingOn.map { "Trying on \($0.name). Supporters keep it, any time." } ?? "Try a vibe")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.subColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.opacity)
                            .padding(.horizontal, 28)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(featuredThemes, id: \.self) { id in themeChip(id) }
                            }
                            .padding(.horizontal, 28)
                        }
                    }

                    Spacer(minLength: 100)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack {
                Spacer()
                Button {
                    seedNoteIfNeeded()
                    // A theme that was only tried on isn't kept.
                    settings.previewThemeID = nil
                    onFinish()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(theme.onMainColor)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(theme.mainColor).interactive(), in: .capsule)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.selection, trigger: pickTick)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3).delay(0.1)) { appeared = true }
        }
    }

    private var sampleCard: some View {
        NoteLinesView(
            lines: NoteParser.visibleLines("# today\n- [x] Write one **clear** list\n- [ ] Tick things off\n- [ ] Keep it on my Lock Screen"),
            font: settings.font,
            size: 17,
            text: theme.textColor,
            sub: theme.subColor,
            accent: theme.mainColor,
            spacing: 7
        )
        .padding(24)
        .frame(width: 280, height: 200, alignment: .topLeading)
        .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.1), radius: 26, y: 12)
        .rotationEffect(.degrees(appeared ? -2 : 0))
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.mainColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(theme.textColor)
                Text(detail).font(.subheadline).foregroundStyle(theme.subColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func themeChip(_ id: String) -> some View {
        let isDefault = id == "default"
        let chipTheme = isDefault ? ThemeCatalog.theme(ThemeCatalog.defaultDarkID) : ThemeCatalog.theme(id)
        let locked = !isDefault && !settings.canUse(chipTheme)
        let selected = isDefault
            ? settings.previewThemeID == nil && settings.matchSystem && settings.lightThemeID == ThemeCatalog.defaultLightID
            : settings.previewThemeID == id || (settings.previewThemeID == nil && !settings.matchSystem && settings.themeID == id)
        return Button {
            withAnimation(.smooth(duration: 0.35)) {
                if isDefault {
                    settings.previewThemeID = nil
                    settings.lightThemeID = ThemeCatalog.defaultLightID
                    settings.darkThemeID = ThemeCatalog.defaultDarkID
                    settings.matchSystem = true
                } else if locked {
                    settings.previewThemeID = id
                } else {
                    settings.previewThemeID = nil
                    settings.themeID = id
                    settings.matchSystem = false
                }
            }
            pickTick += 1
        } label: {
            HStack(spacing: 6) {
                Circle().fill(chipTheme.mainColor).frame(width: 9, height: 9)
                Text(isDefault ? "default" : chipTheme.name.lowercased())
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(chipTheme.textColor)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(chipTheme.subColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(chipTheme.bgColor, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? theme.mainColor : chipTheme.subColor.opacity(0.3), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDefault ? "Default" : chipTheme.name)
        .accessibilityValue(locked ? "Locked, tap to try it on" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func seedNoteIfNeeded() {
        guard NoteStore.shared.current.isEmpty else { return }
        NoteStore.shared.setText("- [ ] Tap a box to tick it off\n- [ ] Try a theme with the palette button\n- [ ] Tap Go Live to pin this list")
    }
}
