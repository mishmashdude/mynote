import SwiftUI

/// The Themes sheet, opened from the palette button on the home screen. Tapping a
/// theme paints the whole app at once. Locked themes can be tried on for free; they
/// only stick (and reach the widget and Lock Screen) once the user becomes a Supporter.
struct ThemesView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var settings = AppSettings.shared
    private var store = SupporterStore.shared

    @State private var pickTick = 0
    @State private var thanksTick = 0
    @State private var message: String?
    /// A short line explaining where a pick went ("Saved as your night theme").
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?
    /// Light or dark section first, fixed when the sheet opens so the grid doesn't jump.
    @State private var darkFirst = false

    /// A locked theme being tried on.
    private var tryingOn: Theme? {
        guard let id = settings.previewThemeID else { return nil }
        let theme = ThemeCatalog.theme(id)
        return settings.canUse(theme) ? nil : theme
    }

    /// The iPhone's own appearance. The app's windows may be forced into the other one
    /// by the theme on screen, so this asks the screen instead.
    private var systemIsDark: Bool {
        let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
        return screen?.traitCollection.userInterfaceStyle == .dark
    }

    /// The theme on screen right now gets the ring.
    private func isShown(_ option: Theme) -> Bool {
        option.id == settings.displayTheme(for: colorScheme).id
    }

    /// With Match System on, the saved day and night themes carry a sun or moon.
    private func badge(for option: Theme) -> String? {
        let choice = settings.themeChoice
        guard choice.matchSystem else { return nil }
        if option.id == choice.lightThemeID { return "sun.max.fill" }
        if option.id == choice.darkThemeID { return "moon.fill" }
        return nil
    }

    private var sections: [(title: String, themes: [Theme])] {
        let dark = ("Dark", ThemeCatalog.darkThemes)
        let light = ("Light", ThemeCatalog.lightThemes)
        return darkFirst ? [dark, light] : [light, dark]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !settings.isSupporter {
                        // While a theme is tried on, the bar at the bottom carries the button.
                        SupporterBanner(showsButton: tryingOn == nil)
                    }
                    pairing
                    ForEach(sections, id: \.title) { section in
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.subColor)
                            .padding(.top, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)], spacing: 12) {
                            ForEach(section.themes) { option in
                                Button { pick(option) } label: {
                                    ThemeTile(theme: option, isSelected: isShown(option), isLocked: !settings.canUse(option),
                                              badge: badge(for: option))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !settings.isSupporter {
                        Button { restore() } label: {
                            Text(store.isRestoring ? "Checking…" : "Restore Purchase")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(theme.subColor)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isRestoring)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(theme.bgColor.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let tryingOn {
                    TryOnBar(theme: tryingOn, price: store.displayPrice, isBusy: store.isPurchasing) { unlock() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { surprise() } label: { Image(systemName: "dice") }
                        .accessibilityLabel("Surprise me")
                }
            }
        }
        .tint(theme.mainColor)
        .sensoryFeedback(.selection, trigger: pickTick)
        .sensoryFeedback(.success, trigger: thanksTick)
        .task { await store.loadProduct() }
        .onAppear { darkFirst = colorScheme == .dark }
        .onDisappear {
            // Back to the saved look for this time of day; a locked theme that was only tried on goes away.
            if settings.previewThemeID != nil {
                withAnimation(.smooth(duration: 0.35)) { settings.previewThemeID = nil }
            }
        }
        .alert("mynote Supporter", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { settings.matchSystem }, set: { setMatchSystem($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Match System Appearance")
                        .foregroundStyle(theme.textColor)
                    Text(settings.matchSystem
                         ? "Your light theme by day, your dark theme by night."
                         : "One theme, all the time.")
                        .font(.caption)
                        .foregroundStyle(theme.subColor)
                }
            }
            .tint(theme.controlTint)
            if let note {
                Label(note, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.mainColor)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Turning Match System on or off keeps the theme that's on screen.
    private func setMatchSystem(_ on: Bool) {
        let shown = settings.displayTheme(for: colorScheme)
        withAnimation(.smooth(duration: 0.35)) {
            settings.setMatchSystem(on, keeping: shown, systemIsDark: systemIsDark)
        }
    }

    /// Every tap shows the theme straight away. Themes you own are saved too: with
    /// Match System on, a light theme becomes the day look and a dark one the night look.
    private func pick(_ option: Theme) {
        pickTick += 1
        let owned = settings.canUse(option)
        withAnimation(.smooth(duration: 0.35)) {
            if owned { save(option) }
            let savedLook = settings.theme(for: systemIsDark ? .dark : .light)
            settings.previewThemeID = owned && savedLook.id == option.id ? nil : option.id
        }
        if owned { explainSlot(for: option) }
    }

    private func save(_ option: Theme) {
        if settings.matchSystem {
            if option.isDark { settings.darkThemeID = option.id } else { settings.lightThemeID = option.id }
        } else {
            settings.themeID = option.id
        }
    }

    /// A theme saved for the other time of day goes back to the current one when the sheet
    /// closes, so say where it went.
    private func explainSlot(for option: Theme) {
        guard settings.matchSystem, option.isDark != systemIsDark else { return }
        let text = option.isDark ? "Saved as your night theme, for when your iPhone is in Dark Mode."
                                 : "Saved as your day theme, for when your iPhone is in Light Mode."
        withAnimation(.smooth) { note = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { note = nil }
        }
    }

    private func surprise() {
        let current = settings.displayTheme(for: colorScheme).id
        if let random = ThemeCatalog.all.filter({ $0.id != current }).randomElement() { pick(random) }
    }

    private func unlock() {
        // Remember what was being tried on: the sheet may close while the App Store sheet is up.
        let tried = settings.previewThemeID.map(ThemeCatalog.theme)
        Task {
            switch await store.purchase() {
            case .purchased:
                thanksTick += 1
                if let tried {
                    withAnimation(.smooth(duration: 0.35)) { save(tried) }
                    explainSlot(for: tried)
                }
            case .pending:
                message = "Your purchase is waiting for approval. Your themes unlock as soon as it goes through."
            case .failed(let text):
                message = text
            case .cancelled:
                break
            }
        }
    }

    private func restore() {
        Task {
            if await store.restore() {
                thanksTick += 1
            } else {
                message = "No earlier purchase was found for this Apple Account."
            }
        }
    }
}

/// The slim version of the Supporter pitch that sits on top of the Themes sheet.
private struct SupporterBanner: View {
    @Environment(\.theme) private var theme
    private var store = SupporterStore.shared
    let showsButton: Bool
    @State private var message: String?

    init(showsButton: Bool) { self.showsButton = showsButton }

    var body: some View {
        HStack(spacing: 12) {
            SwatchFan()
                .scaleEffect(0.8)
                .frame(width: 46, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayPrice.map { "Become a Supporter, \($0) once" } ?? "Become a mynote Supporter")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                Text("Made by one person. Supporters get every theme; tap any to try it on.")
                    .font(.caption)
                    .foregroundStyle(theme.subColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button { buy() } label: {
                Group {
                    if store.isPurchasing {
                        ProgressView().tint(theme.onMainColor)
                    } else {
                        Text("Unlock")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.onMainColor)
                .frame(minWidth: 70, minHeight: 38)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(theme.mainColor).interactive(), in: .capsule)
            .disabled(store.isPurchasing || !showsButton)
            .opacity(showsButton ? 1 : 0)
            .accessibilityHidden(!showsButton)
            .animation(.smooth, value: showsButton)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .alert("mynote Supporter", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func buy() {
        Task {
            switch await store.purchase() {
            case .pending: message = "Your purchase is waiting for approval. Your themes unlock as soon as it goes through."
            case .failed(let text): message = text
            case .purchased, .cancelled: break
            }
        }
    }
}

/// A small mynote card painted in the theme it stands for.
struct ThemeTile: View {
    let theme: Theme
    let isSelected: Bool
    let isLocked: Bool
    /// "sun.max.fill" or "moon.fill" for the saved day and night themes.
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                row(width: 44) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(theme.mainColor)
                }
                row(width: 32) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(theme.mainColor, lineWidth: 1.5)
                }
                row(width: 50) {
                    Circle().fill(theme.mainColor).padding(2.5)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(theme.name.lowercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? theme.mainColor : theme.textColor.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if let badge {
                Image(systemName: badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.onMainColor)
                    .frame(width: 20, height: 20)
                    .background(theme.mainColor, in: Circle())
                    .padding(5)
            } else if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.subColor)
                    .padding(7)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.name)
        .accessibilityValue([
            isSelected ? "Showing" : nil,
            badge == "sun.max.fill" ? "Day theme" : badge == "moon.fill" ? "Night theme" : nil,
            isLocked ? "Locked, tap to try it on" : nil,
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func row(width: CGFloat, @ViewBuilder marker: () -> some View) -> some View {
        HStack(spacing: 5) {
            marker().frame(width: 8, height: 8)
            Capsule().fill(theme.textColor.opacity(0.85)).frame(width: width, height: 4)
        }
    }
}

/// Shown while a locked theme is being tried on.
private struct TryOnBar: View {
    let theme: Theme
    let price: String?
    let isBusy: Bool
    let unlock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trying on \(theme.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                Text(price.map { "Supporters keep it, and every other theme. \($0), once." }
                     ?? "Supporters keep it, and every other theme.")
                    .font(.caption)
                    .foregroundStyle(theme.subColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(action: unlock) {
                Group {
                    if isBusy {
                        ProgressView().tint(theme.onMainColor)
                    } else {
                        Text("Unlock")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.onMainColor)
                .frame(minWidth: 72, minHeight: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(theme.mainColor).interactive(), in: .capsule)
            .disabled(isBusy)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

/// The "support the creator" pitch for the one-off theme unlock, or a thank-you once bought.
struct SupporterCard: View {
    enum Style { case compact, full }

    @Environment(\.theme) private var theme
    private var store = SupporterStore.shared
    private var settings = AppSettings.shared
    let style: Style

    @State private var message: String?
    @State private var thanksTick = 0

    init(style: Style = .full) { self.style = style }

    var body: some View {
        Group {
            if settings.isSupporter {
                thanks
            } else {
                pitch
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sensoryFeedback(.success, trigger: thanksTick)
        .task { await store.loadProduct() }
        .alert("mynote Supporter", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                SwatchFan()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Become a mynote Supporter")
                        .font(.headline)
                        .foregroundStyle(theme.textColor)
                    Text("mynote is made by one person. A one-off \(store.displayPrice ?? "purchase") makes you a Supporter, unlocks all \(ThemeCatalog.all.count) themes for good and helps keep mynote going.")
                        .font(.subheadline)
                        .foregroundStyle(theme.subColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                Button { buy() } label: {
                    Group {
                        if store.isPurchasing {
                            ProgressView().tint(theme.onMainColor)
                        } else {
                            Text(store.displayPrice.map { "Support for \($0)" } ?? "Become a Supporter")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.onMainColor)
                    .frame(maxWidth: style == .full ? .infinity : nil, minHeight: 44)
                    .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(theme.mainColor).interactive(), in: .capsule)
                .disabled(store.isPurchasing)

                Button { restore() } label: {
                    Text(store.isRestoring ? "Checking…" : "Restore Purchase")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.subColor)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(store.isRestoring)
            }
        }
    }

    private var thanks: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(theme.mainColor)
                .symbolEffect(.bounce, value: thanksTick)
            VStack(alignment: .leading, spacing: 3) {
                Text("Thank you for supporting mynote")
                    .font(.headline)
                    .foregroundStyle(theme.textColor)
                Text("Every theme is yours, and so are any Supporter extras that come later.")
                    .font(.subheadline)
                    .foregroundStyle(theme.subColor)
            }
        }
    }

    private func buy() {
        Task {
            switch await store.purchase() {
            case .purchased: thanksTick += 1
            case .pending: message = "Your purchase is waiting for approval. Your themes unlock as soon as it goes through."
            case .failed(let text): message = text
            case .cancelled: break
            }
        }
    }

    private func restore() {
        Task {
            if await store.restore() {
                thanksTick += 1
            } else {
                message = "No earlier purchase was found for this Apple Account."
            }
        }
    }
}

/// Three theme swatches fanned out like paint chips.
private struct SwatchFan: View {
    private let picks = ["dracula", "gruvbox-light", "tokyo-night"].map(ThemeCatalog.theme)

    var body: some View {
        ZStack {
            ForEach(Array(picks.enumerated()), id: \.offset) { index, theme in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.bgColor)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Circle().fill(theme.mainColor).frame(width: 7, height: 7)
                            Capsule().fill(theme.textColor).frame(width: 16, height: 3)
                            Capsule().fill(theme.subColor).frame(width: 11, height: 3)
                        }
                        .padding(6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    }
                    .frame(width: 32, height: 42)
                    .rotationEffect(.degrees(Double(index - 1) * 14), anchor: .bottom)
                    .offset(x: CGFloat(index - 1) * 9)
            }
        }
        .frame(width: 56, height: 50)
        .accessibilityHidden(true)
    }
}
