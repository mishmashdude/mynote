import SwiftUI
import UserNotifications

struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    private var store = NoteStore.shared
    private var settings = AppSettings.shared
    private var live = LiveActivityManager.shared

    @State private var isEditing = false
    @State private var editorFocused = false
    @State private var editor = EditorController()
    @State private var exitStyle = CardExit.archive

    @State private var limitTick = 0
    @State private var editorShowsText = true
    @State private var showLimitBanner = false
    @State private var limitBannerTask: Task<Void, Never>?
    @State private var showDeleteConfirm = false
    @State private var showArchive = false
    @State private var showSettings = false
    @State private var showLiveUnavailable = false
    @State private var liveError: String?

    @State private var toggleTick = 0
    @State private var liveTick = 0
    @State private var archiveTick = 0

    @Namespace private var cardSpace

    private var isLive: Bool { settings.liveEnabled }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                content
            }
            .navigationTitle("mynote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbar(isEditing ? .hidden : .visible, for: .bottomBar)
        }
        .sheet(isPresented: $showArchive) {
            ArchiveView().environment(\.theme, theme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(\.theme, theme)
        }
        .alert(LiveActivityManager.deviceSupportsLiveActivities ? "Live Activities are off" : "Live Activities need an iPhone",
               isPresented: $showLiveUnavailable) {
            if LiveActivityManager.deviceSupportsLiveActivities {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(LiveActivityManager.deviceSupportsLiveActivities
                 ? "Turn on Live Activities for mynote in Settings to keep your list on the Lock Screen."
                 : "Your list can appear on the Lock Screen and in the Dynamic Island when mynote runs on an iPhone.")
        }
        .alert("Couldn't go live", isPresented: Binding(get: { liveError != nil }, set: { if !$0 { liveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(liveError ?? "")
        }
        .sensoryFeedback(.selection, trigger: toggleTick)
        .sensoryFeedback(.success, trigger: liveTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: archiveTick)
        .sensoryFeedback(.error, trigger: limitTick)
        .onOpenURL { url in
            guard url.host() == "edit" else { return }
            // Close any sheet first so the editor isn't hidden behind it.
            let hadSheet = showSettings || showArchive
            showSettings = false
            showArchive = false
            showDeleteConfirm = false
            if hadSheet {
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    beginEditing()
                }
            } else {
                beginEditing()
            }
        }
    }

    // MARK: Layout

    private var content: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 72, 360)
            VStack(spacing: 12) {
                if isEditing {
                    editCard
                        .matchedGeometryEffect(id: store.current.id, in: cardSpace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    editBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Spacer(minLength: 0)
                    displayCard
                        .matchedGeometryEffect(id: store.current.id, in: cardSpace)
                        .frame(width: side, height: side)
                        .id(store.current.id)
                        .transition(.asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity),
                                                removal: exitStyle.transition))
                    Spacer(minLength: 0)
                    Spacer(minLength: 0).frame(height: 24)
                }
            }
            .padding(.horizontal, isEditing ? 14 : 0)
            .padding(.vertical, isEditing ? 8 : 0)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 34, style: .continuous) }

    private var cardBackground: some View {
        cardShape
            .fill(theme.cardColor)
            .overlay {
                // A soft top highlight, like light catching the edge of a glass card.
                cardShape.fill(
                    LinearGradient(colors: [.white.opacity(theme.isDark || theme.hasLightText ? 0.05 : 0.6), .clear],
                                   startPoint: .top, endPoint: .init(x: 0.5, y: 0.18))
                )
            }
            .overlay {
                cardShape.strokeBorder(theme.textColor.opacity(theme.isDark ? 0.09 : 0.05), lineWidth: 1)
            }
            .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.10), radius: 28, x: 0, y: 14)
    }

    private var displayCard: some View {
        let lines = NoteParser.visibleLines(store.current.text)
        let size = settings.textSize.appPointSize
        return ZStack(alignment: .topLeading) {
            cardBackground
            if lines.isEmpty {
                Text("Start typing...")
                    .font(settings.font.font(size: size))
                    .foregroundStyle(theme.subColor)
                    .padding(24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    NoteLinesView(
                        lines: lines,
                        font: settings.font,
                        size: size,
                        text: theme.textColor,
                        sub: theme.subColor,
                        accent: theme.mainColor,
                        spacing: 6,
                        interaction: .action { line in
                            withAnimation(.snappy) { store.toggleLine(line) }
                            toggleTick += 1
                        },
                        lineLimit: nil
                    )
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
                }
                .scrollBounceBehavior(.basedOnSize)
                .clipShape(cardShape)
            }
        }
        .contentShape(cardShape)
        .onTapGesture { beginEditing() }
        .contextMenu {
            Button { beginEditing() } label: { Label("Edit", systemImage: "pencil") }
            Button { UIPasteboard.general.string = store.current.text } label: { Label("Copy", systemImage: "doc.on.doc") }
            todoMenuItems
        }
        .accessibilityAction(named: "Edit note") { beginEditing() }
    }

    private var editCard: some View {
        ZStack(alignment: .bottomTrailing) {
            cardBackground
            ZStack(alignment: .topLeading) {
                if store.current.text.isEmpty && !editorShowsText {
                    Text("Start typing...")
                        .font(settings.font.font(size: settings.textSize.appPointSize))
                        .foregroundStyle(theme.subColor)
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                }
                NoteTextView(
                    text: Binding(get: { store.current.text }, set: { store.setText($0) }),
                    isFocused: $editorFocused,
                    theme: theme,
                    font: settings.font,
                    size: settings.textSize.appPointSize,
                    controller: editor,
                    onLimitHit: { limitHit() },
                    onEndEditing: { endEditing() },
                    onVisibleTextChange: { editorShowsText = $0 }
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 6)

            CharacterRing(count: NoteParser.countedLength(store.current.text), limit: NoteParser.characterLimit, theme: theme)
                .modifier(ShakeEffect(shakes: CGFloat(limitTick)))
                .animation(.linear(duration: 0.4), value: limitTick)
                .padding(18)
        }
        .overlay(alignment: .bottomLeading) {
            if showLimitBanner {
                // Sits in the editor's bottom inset next to the ring, clear of the text.
                Text("\(NoteParser.characterLimit)-character limit reached")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.textColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .padding(16)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var editBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button { editor.toggle(.todo) } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textColor)
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Checkbox")

                Button { editor.toggle(.bullet) } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textColor)
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Bullet")

                Button { endEditing() } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.onMainColor)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(theme.mainColor).interactive(), in: .capsule)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isEditing {
            ToolbarItem(placement: .topBarLeading) {
                ShareLink(item: NoteParser.shareText(store.current.text)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(store.current.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showArchive = true } label: { Label("Archived Notes", systemImage: "archivebox") }
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    todoMenuItems
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button { archive() } label: {
                Image(systemName: "archivebox")
            }
            .disabled(store.current.isEmpty)
            .accessibilityLabel("Archive note")
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            liveButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash")
            }
            .disabled(store.current.isEmpty)
            .accessibilityLabel("Delete note")
            .confirmationDialog("Delete Note?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) { delete() }
            } message: {
                Text("This note will be permanently deleted.")
            }
        }
    }

    @ViewBuilder
    private var todoMenuItems: some View {
        let progress = NoteParser.progress(store.current.text)
        if progress.total > 0 {
            Divider()
            Button { withAnimation(.snappy) { store.setAllTodos(checked: false) } } label: {
                Label("Uncheck All", systemImage: "square")
            }
            .disabled(progress.done == 0)
            Button(role: .destructive) { withAnimation(.snappy) { store.removeCompleted() } } label: {
                Label("Clear Completed", systemImage: "checkmark.square")
            }
            .disabled(progress.done == 0)
        }
    }

    private var liveButton: some View {
        Button { toggleLive() } label: {
            HStack(spacing: 7) {
                LiveDot(isLive: isLive, color: theme.mainColor, ring: theme.textColor)
                Text(isLive ? "Live" : "Go Live")
                    .fontWeight(.medium)
                    .contentTransition(.interpolate)
            }
            .padding(.horizontal, 6)
        }
        .disabled(store.current.isEmpty && !isLive)
        .accessibilityLabel(isLive ? "Live on Lock Screen. Double-tap to stop." : "Go Live on Lock Screen")
    }

    // MARK: Actions

    /// Inline feedback instead of an alert, which would steal focus and close the editor.
    private func limitHit() {
        limitTick += 1
        withAnimation(.snappy) { showLimitBanner = true }
        UIAccessibility.post(notification: .announcement, argument: "Character limit reached")
        limitBannerTask?.cancel()
        limitBannerTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showLimitBanner = false }
        }
    }

    private func beginEditing() {
        guard !isEditing else { return }
        editorShowsText = !store.current.text.isEmpty
        withAnimation(.smooth(duration: 0.38)) { isEditing = true }
        editorFocused = true
    }

    private func endEditing() {
        guard isEditing else { return }
        editor.commitComposition()
        let tidied = NoteParser.tidy(store.current.text)
        if tidied != store.current.text { store.setText(tidied) }
        editorFocused = false
        withAnimation(.smooth(duration: 0.38)) { isEditing = false }
    }

    private func archive() {
        exitStyle = .archive
        withAnimation(.spring(duration: 0.5, bounce: 0.18)) { store.archiveCurrent() }
        archiveTick += 1
    }

    private func delete() {
        exitStyle = .delete
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { store.deleteCurrent() }
        archiveTick += 1
    }

    private func toggleLive() {
        Task {
            if isLive {
                await live.stop()
                return
            }
            let ok = await live.goLive()
            if ok {
                liveTick += 1
                await askForReminderPermission()
            } else if live.status == .unavailable {
                showLiveUnavailable = true
            } else if case .failed(let message) = live.status {
                liveError = message
            }
        }
    }

    private func askForReminderPermission() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await live.reconcile()
    }
}

/// The little circle in the Go Live button: hollow when off, a softly pulsing dot when live.
private struct LiveDot: View {
    let isLive: Bool
    let color: Color
    let ring: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ring.opacity(isLive ? 0 : 0.9), lineWidth: 1.6)
            Circle()
                .fill(color)
                .scaleEffect(isLive ? 1 : 0.01)
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 2)
                .scaleEffect(pulse ? 2.1 : 1)
                .opacity(isLive && !pulse ? 1 : 0)
        }
        .frame(width: 11, height: 11)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: isLive)
        .onAppear { startPulse() }
        .onChange(of: isLive) { startPulse() }
    }

    private func startPulse() {
        pulse = false
        guard isLive else { return }
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
    }
}

enum CardExit {
    case archive, delete

    var transition: AnyTransition {
        switch self {
        case .archive:
            .offset(x: -110, y: 420).combined(with: .scale(scale: 0.15)).combined(with: .opacity)
        case .delete:
            .scale(scale: 0.6).combined(with: .opacity)
        }
    }
}

/// Horizontal shake used when the character limit is hit.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(shakes * .pi * 4), y: 0))
    }
}
