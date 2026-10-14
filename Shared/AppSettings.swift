import SwiftUI
import Observation
import WidgetKit

private enum Key {
    static let matchSystem = "matchSystem"
    static let themeID = "themeID"
    static let lightThemeID = "lightThemeID"
    static let darkThemeID = "darkThemeID"
    static let font = "noteFont"
    static let textSize = "textSize"
    static let liveStyle = "liveStyle"
    static let liveEnabled = "liveEnabled"
    static let autoRelay = "autoRelay"
    static let silentRelay = "silentRelay"
    static let expiryReminders = "expiryReminders"
    static let hasOnboarded = "hasOnboarded"
    static let activitySequence = "activitySequence"
    static let coveredUntil = "liveCoveredUntil"
    static let editorMode = "editorMode"
    static let isSupporter = "isSupporter"
    static let keptThemeIDs = "keptThemeIDs"
    static let themeAccessMigrated = "themeAccessMigrated"
    static let hasSeenArchiveNotice = "hasSeenArchiveNotice"
}

/// Which theme(s) the user picked. Plain value so widgets can use it too.
struct ThemeChoice: Codable, Hashable, Sendable {
    var matchSystem: Bool
    var themeID: String
    var lightThemeID: String
    var darkThemeID: String

    func theme(for scheme: ColorScheme) -> Theme {
        if matchSystem {
            return ThemeCatalog.theme(scheme == .dark ? darkThemeID : lightThemeID)
        }
        return ThemeCatalog.theme(themeID)
    }

    /// The colour scheme to force on the UI (nil = follow the system).
    var forcedScheme: ColorScheme? {
        matchSystem ? nil : ThemeCatalog.theme(themeID).colorScheme
    }

    /// Theme ids to hand to the Live Activity (light, dark).
    var liveIDs: (light: String, dark: String) {
        matchSystem ? (lightThemeID, darkThemeID) : (themeID, themeID)
    }

    /// The same choice with any theme the user can't use swapped for the matching default.
    func allowed(by access: ThemeAccess) -> ThemeChoice {
        var choice = self
        choice.themeID = access.resolved(themeID)
        choice.lightThemeID = access.resolved(lightThemeID)
        choice.darkThemeID = access.resolved(darkThemeID)
        return choice
    }
}

/// Which themes can be shown. Everyone gets the free ones, supporters get them all, and
/// people who updated from 1.0 keep the ones they had picked.
///
/// A locked theme is swapped for a default when it's drawn. The saved pick is rewritten
/// only after StoreKit confirms this Apple Account doesn't own Supporter, so a check that
/// hasn't finished can't throw a theme away. Themes kept from 1.0 are still allowed.
struct ThemeAccess: Sendable {
    var isSupporter: Bool
    var kept: Set<String>
    /// False until 1.1 has run once. Every theme was free in 1.0, so a widget drawn
    /// before the first launch of the update keeps the old look.
    var rulesApply: Bool

    func allows(_ id: String) -> Bool {
        !rulesApply || isSupporter || ThemeCatalog.freeIDs.contains(id) || kept.contains(id)
    }

    /// The id to actually paint. A locked dark theme becomes Default Dark, a locked light one Default Light.
    func resolved(_ id: String) -> String {
        guard !allows(id) else { return id }
        return ThemeCatalog.theme(id).isDark ? ThemeCatalog.defaultDarkID : ThemeCatalog.defaultLightID
    }

    static func load(_ d: UserDefaults) -> ThemeAccess {
        ThemeAccess(isSupporter: d.bool(forKey: Key.isSupporter),
                    kept: Set(d.stringArray(forKey: Key.keptThemeIDs) ?? []),
                    rulesApply: d.bool(forKey: Key.themeAccessMigrated))
    }
}

/// A read-only copy of the settings, safe to load from the widget extension.
struct SettingsSnapshot: Sendable {
    /// What the user picked.
    var savedThemeChoice: ThemeChoice
    /// What can be shown (locked themes swapped for defaults). Widgets and the Live Activity use this.
    var themeChoice: ThemeChoice
    var font: NoteFont
    var textSize: TextSize
    var liveStyle: LiveStyle
    var liveEnabled: Bool
    var autoRelay: Bool
    var silentRelay: Bool
    var expiryReminders: Bool
    /// When the last scheduled Live Activity ends (nil when nothing is scheduled).
    var coveredUntil: Date?

    /// True when the user wants Live on *and* something should still be on the Lock Screen.
    var isEffectivelyLive: Bool {
        liveEnabled && (coveredUntil ?? .distantPast) > .now
    }

    static func storeCoveredUntil(_ date: Date?) {
        if let date {
            AppGroup.defaults.set(date, forKey: Key.coveredUntil)
        } else {
            AppGroup.defaults.removeObject(forKey: Key.coveredUntil)
        }
    }

    static func load(_ d: UserDefaults = AppGroup.defaults) -> SettingsSnapshot {
        let saved = ThemeChoice(
            matchSystem: d.object(forKey: Key.matchSystem) as? Bool ?? true,
            // 1.0 fell back to Serika Dark here; kept so 1.0 notes look the same until the update first runs.
            themeID: d.string(forKey: Key.themeID) ?? "serika-dark",
            lightThemeID: d.string(forKey: Key.lightThemeID) ?? ThemeCatalog.defaultLightID,
            darkThemeID: d.string(forKey: Key.darkThemeID) ?? ThemeCatalog.defaultDarkID
        )
        return SettingsSnapshot(
            savedThemeChoice: saved,
            themeChoice: saved.allowed(by: ThemeAccess.load(d)),
            font: NoteFont(rawValue: d.string(forKey: Key.font) ?? "") ?? .system,
            textSize: TextSize(rawValue: d.object(forKey: Key.textSize) as? Int ?? 1) ?? .regular,
            liveStyle: LiveStyle(rawValue: d.string(forKey: Key.liveStyle) ?? "") ?? .theme,
            liveEnabled: d.bool(forKey: Key.liveEnabled),
            autoRelay: d.object(forKey: Key.autoRelay) as? Bool ?? true,
            silentRelay: d.object(forKey: Key.silentRelay) as? Bool ?? true,
            expiryReminders: d.object(forKey: Key.expiryReminders) as? Bool ?? true,
            coveredUntil: d.object(forKey: Key.coveredUntil) as? Date
        )
    }

    static func nextActivitySequence() -> Int {
        let d = AppGroup.defaults
        let next = d.integer(forKey: Key.activitySequence) + 1
        d.set(next, forKey: Key.activitySequence)
        return next
    }
}

/// Live, observable settings used by the app UI. Every change is written to the
/// shared App Group defaults so the widget and Live Activity pick it up.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let d = AppGroup.defaults

    var matchSystem: Bool { didSet { d.set(matchSystem, forKey: Key.matchSystem); appearanceChanged() } }
    var themeID: String { didSet { d.set(themeID, forKey: Key.themeID); appearanceChanged() } }
    var lightThemeID: String { didSet { d.set(lightThemeID, forKey: Key.lightThemeID); appearanceChanged() } }
    var darkThemeID: String { didSet { d.set(darkThemeID, forKey: Key.darkThemeID); appearanceChanged() } }
    var font: NoteFont { didSet { d.set(font.rawValue, forKey: Key.font); appearanceChanged() } }
    var textSize: TextSize { didSet { d.set(textSize.rawValue, forKey: Key.textSize); appearanceChanged() } }
    var liveStyle: LiveStyle { didSet { d.set(liveStyle.rawValue, forKey: Key.liveStyle); appearanceChanged() } }
    var liveEnabled: Bool { didSet { d.set(liveEnabled, forKey: Key.liveEnabled); WidgetCenter.shared.reloadAllTimelines(); ControlCenterReloader.reload() } }
    var autoRelay: Bool { didSet { d.set(autoRelay, forKey: Key.autoRelay) } }
    var silentRelay: Bool { didSet { d.set(silentRelay, forKey: Key.silentRelay) } }
    var expiryReminders: Bool { didSet { d.set(expiryReminders, forKey: Key.expiryReminders) } }
    var hasOnboarded: Bool { didSet { d.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    var editorMode: EditorMode { didSet { d.set(editorMode.rawValue, forKey: Key.editorMode) } }
    /// Bought the Supporter unlock. Kept here so the app shows the right state before StoreKit answers.
    var isSupporter: Bool { didSet { d.set(isSupporter, forKey: Key.isSupporter); appearanceChanged() } }
    /// The first time the trash button is used, an alert explains where deleted notes go.
    var hasSeenArchiveNotice: Bool { didSet { d.set(hasSeenArchiveNotice, forKey: Key.hasSeenArchiveNotice) } }
    /// Paid themes someone had already picked before themes needed the unlock. They keep them.
    private(set) var keptThemeIDs: Set<String> { didSet { d.set(Array(keptThemeIDs), forKey: Key.keptThemeIDs) } }

    /// A theme being tried on in the Themes sheet. It only paints the app: it is never
    /// saved, so the widget and Live Activity keep showing the real choice.
    var previewThemeID: String?

    private init() {
        let s = SettingsSnapshot.load(d)
        matchSystem = s.savedThemeChoice.matchSystem
        themeID = s.savedThemeChoice.themeID
        lightThemeID = s.savedThemeChoice.lightThemeID
        darkThemeID = s.savedThemeChoice.darkThemeID
        font = s.font
        textSize = s.textSize
        liveStyle = s.liveStyle
        liveEnabled = s.liveEnabled
        autoRelay = s.autoRelay
        silentRelay = s.silentRelay
        expiryReminders = s.expiryReminders
        hasOnboarded = d.bool(forKey: Key.hasOnboarded)
        editorMode = EditorMode(rawValue: d.string(forKey: Key.editorMode) ?? "") ?? .rich
        isSupporter = d.bool(forKey: Key.isSupporter)
        hasSeenArchiveNotice = d.bool(forKey: Key.hasSeenArchiveNotice)
        keptThemeIDs = Set(d.stringArray(forKey: Key.keptThemeIDs) ?? [])
        keepThemesPickedBeforeUnlock()
    }

    /// Re-read values another process (an intent, the widget) may have changed.
    func reload() {
        let s = SettingsSnapshot.load(d)
        if liveEnabled != s.liveEnabled { liveEnabled = s.liveEnabled }
    }

    /// What the user picked, locked or not.
    var savedThemeChoice: ThemeChoice {
        ThemeChoice(matchSystem: matchSystem, themeID: themeID, lightThemeID: lightThemeID, darkThemeID: darkThemeID)
    }

    /// What can be shown right now.
    var themeChoice: ThemeChoice { savedThemeChoice.allowed(by: access) }

    func theme(for scheme: ColorScheme) -> Theme { themeChoice.theme(for: scheme) }

    /// What the app should paint with right now: a preview if one is running, else the saved choice.
    func displayTheme(for scheme: ColorScheme) -> Theme {
        previewThemeID.map(ThemeCatalog.theme) ?? theme(for: scheme)
    }

    /// The colour scheme to force on every window (nil = follow the system).
    var displayForcedScheme: ColorScheme? {
        previewThemeID.map { ThemeCatalog.theme($0).colorScheme } ?? themeChoice.forcedScheme
    }

    // MARK: Theme access

    private var access: ThemeAccess {
        ThemeAccess(isSupporter: isSupporter, kept: keptThemeIDs, rulesApply: true)
    }

    func canUse(_ theme: Theme) -> Bool { access.allows(theme.id) }

    /// Writes the themes this person is allowed to use over any locked picks.
    /// A Supporter's picks, and themes kept from version 1.0, are left as they are.
    func replaceLockedThemePicks() {
        let allowed = savedThemeChoice.allowed(by: access)
        if themeID != allowed.themeID { themeID = allowed.themeID }
        if lightThemeID != allowed.lightThemeID { lightThemeID = allowed.lightThemeID }
        if darkThemeID != allowed.darkThemeID { darkThemeID = allowed.darkThemeID }
    }

    /// Themes were all free in 1.0. Anyone updating keeps the themes they had chosen.
    private func keepThemesPickedBeforeUnlock() {
        guard !d.bool(forKey: Key.themeAccessMigrated) else { return }
        if d.string(forKey: Key.themeID) == nil {
            // 1.0 showed Serika Dark when "Match System Appearance" was off and no theme had been picked.
            let updatingWithMatchSystemOff = hasOnboarded && d.object(forKey: Key.matchSystem) as? Bool == false
            let fallback = updatingWithMatchSystemOff ? "serika-dark" : ThemeCatalog.defaultDarkID
            d.set(fallback, forKey: Key.themeID)
            themeID = fallback
        }
        if hasOnboarded {
            let picked = [Key.themeID, Key.lightThemeID, Key.darkThemeID].compactMap { d.string(forKey: $0) }
            keptThemeIDs = Set(picked).subtracting(ThemeCatalog.freeIDs)
            d.set(Array(keptThemeIDs), forKey: Key.keptThemeIDs)
        }
        // Last, so a widget never sees the rules switched on before the kept themes are saved.
        d.set(true, forKey: Key.themeAccessMigrated)
    }

    /// Match System Appearance on or off, keeping the theme that's on screen.
    /// - Parameter shown: the theme the app shows right now (a preview included).
    /// - Parameter systemIsDark: the iPhone's own appearance.
    func setMatchSystem(_ on: Bool, keeping shown: Theme, systemIsDark: Bool) {
        matchSystem = on
        guard canUse(shown) else { return }
        if on {
            if shown.isDark { darkThemeID = shown.id } else { lightThemeID = shown.id }
        } else {
            themeID = shown.id
        }
        // The preview is no longer needed when the saved choice shows the same thing.
        if theme(for: systemIsDark ? .dark : .light).id == shown.id { previewThemeID = nil }
    }

    private func appearanceChanged() {
        WidgetCenter.shared.reloadAllTimelines()
        LiveActivityManager.shared.contentDidChange()
    }
}

enum ControlCenterReloader {
    static let liveControlKind = "com.andi.mynote.control.live"
    static func reload() {
        ControlCenter.shared.reloadControls(ofKind: liveControlKind)
    }
}
