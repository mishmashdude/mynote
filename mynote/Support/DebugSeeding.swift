#if DEBUG
import Foundation

/// Debug-only: lets screenshot scripts set up the app from launch arguments, e.g.
/// `xcrun simctl launch <udid> com.andi.mynote -seedTheme dracula -seedNote "[ ] one"`.
@MainActor
enum DebugSeeding {
    static func apply() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        let settings = AppSettings.shared
        if args.contains("-seedOnboarded") { settings.hasOnboarded = true }
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
