import Foundation
import os

enum Log {
    static let live = Logger(subsystem: "com.andi.mynote", category: "live")
    static let intents = Logger(subsystem: "com.andi.mynote", category: "intents")

    /// "app" or "widgets" — handy for checking which process ran an intent.
    static var process: String {
        Bundle.main.bundleIdentifier?.hasSuffix(".widgets") == true ? "widgets" : "app"
    }
}
