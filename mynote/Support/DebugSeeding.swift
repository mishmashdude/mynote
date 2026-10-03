#if DEBUG
import Foundation

/// Debug-only: lets screenshot scripts set up the app from launch arguments, e.g.
/// `xcrun simctl launch <udid> com.andi.mynote -seedTheme dracula -seedNote "- [ ] one"`.
@MainActor
enum DebugSeeding {
    /// `-seedSupporter YES|NO` pretends the Supporter unlock is (or isn't) owned.
    private(set) static var supporterOverride: Bool?
    /// `-seedPrice '$1.99'` stands in for the App Store price when no StoreKit configuration is attached.
    private(set) static var priceOverride: String?
    private static var applied = false

    /// Runs once per launch: SwiftUI can rebuild the root view, which must not re-seed the note.
    static func apply() {
        guard !applied else { return }
        applied = true
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        let settings = AppSettings.shared
        if args.contains("-seedOnboarded") { settings.hasOnboarded = true }
        if let supporter = value("-seedSupporter") {
            supporterOverride = supporter == "YES"
            settings.isSupporter = supporter == "YES"
        }
        if let price = value("-seedPrice") { priceOverride = price }
        if let seen = value("-seedArchiveNotice") { settings.hasSeenArchiveNotice = seen == "YES" }
        if let editor = value("-seedEditor"), let mode = EditorMode(rawValue: editor) { settings.editorMode = mode }
        if let theme = value("-seedTheme") {
            settings.matchSystem = false
            settings.themeID = theme
        }
        if let font = value("-seedFont"), let f = NoteFont(rawValue: font) { settings.font = f }
        if let style = value("-seedLiveStyle"), let s = LiveStyle(rawValue: style) { settings.liveStyle = s }
        if let note = value("-seedNote") {
            NoteStore.shared.setText(note.replacingOccurrences(of: "\\n", with: "\n"))
        }
        if let archived = value("-seedArchive") {
            for text in archived.components(separatedBy: "||") where !text.isEmpty {
                let current = NoteStore.shared.current.text
                NoteStore.shared.setText(text.replacingOccurrences(of: "\\n", with: "\n"))
                NoteStore.shared.archiveCurrent()
                NoteStore.shared.setText(current)
            }
        }
    }
}
#endif
