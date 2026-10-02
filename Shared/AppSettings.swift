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
}

/// A read-only copy of the settings, safe to load from the widget extension.
struct SettingsSnapshot: Sendable {
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
        SettingsSnapshot(
            themeChoice: ThemeChoice(
                matchSystem: d.object(forKey: Key.matchSystem) as? Bool ?? true,
                themeID: d.string(forKey: Key.themeID) ?? "serika-dark",
                lightThemeID: d.string(forKey: Key.lightThemeID) ?? ThemeCatalog.defaultLightID,
                darkThemeID: d.string(forKey: Key.darkThemeID) ?? ThemeCatalog.defaultDarkID
            ),
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

    private init() {
        let s = SettingsSnapshot.load(d)
        matchSystem = s.themeChoice.matchSystem
        themeID = s.themeChoice.themeID
        lightThemeID = s.themeChoice.lightThemeID
        darkThemeID = s.themeChoice.darkThemeID
        font = s.font
        textSize = s.textSize
        liveStyle = s.liveStyle
        liveEnabled = s.liveEnabled
        autoRelay = s.autoRelay
        silentRelay = s.silentRelay
        expiryReminders = s.expiryReminders
        hasOnboarded = d.bool(forKey: Key.hasOnboarded)
    }

    /// Re-read values another process (an intent, the widget) may have changed.
    func reload() {
        let s = SettingsSnapshot.load(d)
        if liveEnabled != s.liveEnabled { liveEnabled = s.liveEnabled }
    }

    var themeChoice: ThemeChoice {
        ThemeChoice(matchSystem: matchSystem, themeID: themeID, lightThemeID: lightThemeID, darkThemeID: darkThemeID)
    }

    func theme(for scheme: ColorScheme) -> Theme { themeChoice.theme(for: scheme) }

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
