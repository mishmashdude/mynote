import SwiftUI
import UserNotifications

struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store = NoteStore.shared
    private var settings = AppSettings.shared
    private var live = LiveActivityManager.shared

    @State private var isEditing = false
    @State private var editorFocused = false
    @State private var editor = EditorController()
    @State private var formatState = FormatState()

    @State private var limitTick = 0
    @State private var editorShowsText = true
    @State private var showLimitBanner = false
    @State private var limitBannerTask: Task<Void, Never>?

    @State private var showArchive = false
    @State private var showSettings = false
    @State private var showThemes = false
    @State private var showDeleteNotice = false
    @State private var showLiveUnavailable = false
    @State private var liveError: String?

    /// A copy of the card on its way into (or back out of) the Archive button.
    @State private var flyingCard: FlyingCard?
    @State private var cardFrame = CGRect.zero
    @State private var archiveButtonFrame = CGRect.zero
    /// Bumps when a card lands in the Archive, to make the button catch it.
    @State private var archiveCatch = 0
    @State private var archiveFull = false
    /// The note that was just moved to the Archive, while Undo is still offered.
    @State private var undoNoteID: UUID?
    @State private var undoTask: Task<Void, Never>?

    @State private var toggleTick = 0
    @State private var liveTick = 0
    @State private var landTick = 0

    @Namespace private var cardSpace

    private var isLive: Bool { settings.liveEnabled }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                content
            }
            .overlay(alignment: .bottom) {
                if undoNoteID != nil, !isEditing {
                    undoPill
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("mynote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbar(isEditing ? .hidden : .visible, for: .bottomBar)
        }
        .sheet(isPresented: $showArchive) {
            ArchiveView().environment(\.theme, theme)
        }
        .onChange(of: showArchive) { if showArchive { dismissUndo() } }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(\.theme, theme)
        }
        .sheet(isPresented: $showThemes) {
            ThemesView()
                .environment(\.theme, theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.bgColor)
        }
        .alert("Delete this note?", isPresented: $showDeleteNotice) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                settings.hasSeenArchiveNotice = true
                Task {
                    // Let the alert get out of the way so the card's trip to the Archive is visible.
                    try? await Task.sleep(for: .milliseconds(250))
                    moveToArchive()
                }
            }
        } message: {
            Text("It moves to your Archive (the box at the top right) and stays there until you delete it from the Archive.")
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
        .sensoryFeedback(.impact(weight: .medium), trigger: landTick)
        .sensoryFeedback(.error, trigger: limitTick)
        .onOpenURL { url in
            guard url.host() == "edit" else { return }
            // Close any sheet first so the editor isn't hidden behind it.
            let hadSheet = showSettings || showArchive || showThemes
            showSettings = false
            showArchive = false
            showThemes = false
            showDeleteNotice = false
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
                    FormatBar(theme: theme, state: formatState, perform: { editor.perform($0) }, onDone: { endEditing() })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Spacer(minLength: 0)
                    ZStack {
                        displayCard
                            .matchedGeometryEffect(id: store.current.id, in: cardSpace)
                            .id(store.current.id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity),
                                                    removal: .scale(scale: 0.9).combined(with: .opacity)))
                        if let flyingCard {
                            cardFace(text: flyingCard.text)
                                .modifier(ArchiveFlight(progress: flyingCard.progress, target: flyingCard.target))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: side, height: side)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrame = $0 }
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

    /// A still copy of the card for a note, used for the trip to and from the Archive.
    private func cardFace(text: String) -> some View {
        ZStack(alignment: .topLeading) {
            cardBackground
            NoteLinesView(
                lines: NoteParser.visibleLines(text),
                font: settings.font,
                size: settings.textSize.appPointSize,
                text: theme.textColor,
                sub: theme.subColor,
                accent: theme.mainColor,
                spacing: 6,
                lineLimit: nil
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipShape(cardShape)
        }
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
                        lineLimit: nil,
                        tappableLinks: true
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
            Button { UIPasteboard.general.string = NoteParser.shareText(store.current.text) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button { UIPasteboard.general.string = store.current.text } label: {
                Label("Copy as Markdown", systemImage: "number")
            }
            todoMenuItems
            if !store.current.isEmpty {
                Divider()
                Button(role: .destructive) { deleteTapped() } label: { Label("Delete", systemImage: "trash") }
            }
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
                editorView
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

    @ViewBuilder
    private var editorView: some View {
        let text = Binding(get: { store.current.text }, set: { store.setText($0) })
        let size = settings.textSize.appPointSize
        switch settings.editorMode {
        case .rich:
            RichEditor(
                text: text, isFocused: $editorFocused, theme: theme, font: settings.font, size: size, controller: editor,
                onLimitHit: { limitHit() }, onEndEditing: { endEditing() },
                onVisibleTextChange: { editorShowsText = $0 }, onFormatState: { updateFormatState($0) }
            )
        case .markdown:
            MarkdownEditor(
                text: text, isFocused: $editorFocused, theme: theme, font: settings.font, size: size, controller: editor,
                onLimitHit: { limitHit() }, onEndEditing: { endEditing() },
                onVisibleTextChange: { editorShowsText = $0 }, onFormatState: { updateFormatState($0) }
            )
        }
    }

    private var undoPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(theme.mainColor)
            Text("Moved to Archive")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textColor)
            Spacer(minLength: 12)
            Button { undoArchive() } label: {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.mainColor)
                    .frame(minWidth: 60, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 28)
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
                .accessibilityLabel("Share note")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                archiveButton
            }
        }
        ToolbarItem(placement: .bottomBar) {
            themesButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            liveButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button { deleteTapped() } label: {
                Image(systemName: "trash")
            }
            .disabled(store.current.isEmpty)
            .accessibilityLabel("Delete note")
            .accessibilityHint("Moves the note to the Archive.")
        }
    }

    private var archiveButton: some View {
        Button { showArchive = true } label: {
            Image(systemName: archiveFull ? "archivebox.fill" : "archivebox")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.down, value: archiveCatch)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { archiveButtonFrame = $0 }
        }
        .accessibilityLabel("Archive")
        .accessibilityValue(store.archived.isEmpty ? "Empty" : store.archived.count == 1 ? "1 note" : "\(store.archived.count) notes")
    }

    /// A colourful palette, so it reads as "play with the look" in any theme.
    private var themesButton: some View {
        Button { showThemes = true } label: {
            Image(systemName: "paintpalette.fill")
                .symbolRenderingMode(.multicolor)
        }
        .accessibilityLabel("Themes")
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

    private func updateFormatState(_ state: FormatState) {
        if formatState != state { formatState = state }
    }

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
        dismissUndo()
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

    /// The first delete explains where notes go; after that it's one tap, with Undo.
    private func deleteTapped() {
        guard !store.current.isEmpty else { return }
        if settings.hasSeenArchiveNotice {
            moveToArchive()
        } else {
            showDeleteNotice = true
        }
    }

    /// The offset from the card's middle to the Archive button's.
    private var archiveOffset: CGSize {
        guard archiveButtonFrame.width > 0, cardFrame.width > 0 else { return CGSize(width: 130, height: -360) }
        return CGSize(width: archiveButtonFrame.midX - cardFrame.midX, height: archiveButtonFrame.midY - cardFrame.midY)
    }

    /// Applies changes with no animation at all (not even a view's own `.animation`).
    private func instantly(_ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// The card flies into the Archive button. Underneath, the note swaps for a fresh one
    /// straight away, so the flight is just a copy and can never leave things half done.
    private func moveToArchive() {
        guard !store.current.isEmpty, flyingCard == nil else { return }
        if reduceMotion {
            var archived: UUID?
            withAnimation(.easeInOut(duration: 0.3)) { archived = store.archiveCurrent() }
            if let archived {
                catchInArchive()
                showUndo(for: archived)
            }
            return
        }
        let flight = FlyingCard(text: store.current.text, target: archiveOffset, progress: 0)
        var archived: UUID?
        instantly {
            flyingCard = flight
            archived = store.archiveCurrent()
        }
        guard let archived else {
            flyingCard = nil
            return
        }
        Task { @MainActor in
            // One frame for the copy to appear where the card was, then off it goes.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.linear(duration: FlyingCard.duration)) {
                flyingCard?.progress = 1
            } completion: {
                if flyingCard?.id == flight.id { flyingCard = nil }
            }
            try? await Task.sleep(for: .seconds(FlyingCard.duration * 0.88))
            catchInArchive()
            // Undo is offered once the card has landed, so it can't be tapped mid-flight.
            showUndo(for: archived)
        }
    }

    private func catchInArchive() {
        landTick += 1
        archiveCatch += 1
        archiveFull = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            archiveFull = false
        }
    }

    private func showUndo(for noteID: UUID) {
        withAnimation(.snappy) { undoNoteID = noteID }
        UIAccessibility.post(notification: .announcement, argument: "Moved to Archive. Undo is available.")
        undoTask?.cancel()
        // People using VoiceOver or Switch Control need longer than a few seconds to reach Undo.
        guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return }
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { undoNoteID = nil }
        }
    }

    private func dismissUndo() {
        undoTask?.cancel()
        if undoNoteID != nil { withAnimation(.snappy) { undoNoteID = nil } }
    }

    /// Undo flies the card back out of the Archive button and puts the note back.
    private func undoArchive() {
        guard let noteID = undoNoteID, flyingCard == nil else { return }
        dismissUndo()
        guard store.current.isEmpty, let note = store.archived.first(where: { $0.id == noteID }) else { return }
        archiveCatch += 1
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) { store.restore(noteID) }
            toggleTick += 1
            return
        }
        let flight = FlyingCard(text: note.text, target: archiveOffset, progress: 1)
        instantly { flyingCard = flight }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.linear(duration: 0.55)) {
                flyingCard?.progress = 0
            } completion: {
                instantly {
                    store.restore(noteID)
                    if flyingCard?.id == flight.id { flyingCard = nil }
                }
                toggleTick += 1
            }
        }
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

/// A copy of the note card in flight between its spot and the Archive button.
struct FlyingCard: Identifiable {
    let id = UUID()
    let text: String
    /// Offset from the card's middle to the Archive button's.
    let target: CGSize
    /// 0 = where the card sits, 1 = inside the Archive button.
    var progress: CGFloat

    static let duration = 0.7
}

/// Carries the card along a curve into the Archive button: a small lift, then an arc up and
/// across, shrinking as it goes and tipping mid-air before it drops into the box.
/// `progress` should run linearly; each part of the motion has its own easing.
struct ArchiveFlight: ViewModifier, Animatable {
    var progress: CGFloat
    let target: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = min(max(progress, 0), 1)
        let lift = min(1, t / 0.1)
        let travel = max(0, (t - 0.08) / 0.92)
        // Smooth start and finish for the path.
        let along = travel < 0.5 ? 4 * travel * travel * travel : 1 - pow(-2 * travel + 2, 3) / 2
        // Rises first, then swings across into the button.
        let control = CGPoint(x: target.width * 0.15, y: target.height * 0.95)
        let inverse = 1 - along
        let x = 2 * inverse * along * control.x + along * along * target.width
        let y = 2 * inverse * along * control.y + along * along * target.height
        // Shrinks quickly at first so it's button-sized by the time it arrives.
        let shrink = 1 - (1 - travel) * (1 - travel)
        let scale = (1 - 0.05 * lift) * (1 - 0.93 * shrink)
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(12 * sin(Double(travel) * .pi)))
            .offset(x: x, y: y)
            .opacity(travel < 0.86 ? 1 : max(0, 1 - (travel - 0.86) / 0.14))
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
