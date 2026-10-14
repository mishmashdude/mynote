import Foundation

/// Everything the app and the widget extension share lives in this App Group.
enum AppGroup {
    static let id = "group.com.andi.mynote"

    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        // Fallback for previews / misconfigured signing: keep working with a private folder.
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}

enum AppInfo {
    static let name = "mynote"

    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    static let siteURL = URL(string: "https://mishmashdude.github.io/mynote/")!
    static let privacyURL = URL(string: "https://mishmashdude.github.io/mynote/privacy.html")!
    static let supportURL = URL(string: "https://mishmashdude.github.io/mynote/support.html")!
    static let feedbackURL = URL(string: "https://github.com/mishmashdude/mynote/issues/new/choose")!
    static let appStoreID = "6818596761"
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6818596761?action=write-review")!
}
