import AppIntents
import Foundation
import WidgetKit

// All intents conform to `LiveActivityIntent`, so iOS runs them inside the app's
// process — even when they're triggered from the Lock Screen, a widget, a Control
// or a Shortcuts automation. That's what lets them start a brand-new Live Activity.

/// Ticks or unticks one checklist line.
struct ToggleItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Checklist Item"
    static let isDiscoverable = false

    @Parameter(title: "Line")
    var line: Int

    /// The item's text when the button was drawn, so a stale widget can't tick the wrong item.
    @Parameter(title: "Item")
    var content: String?

    /// Whether the item looked ticked when it was tapped.
    @Parameter(title: "Was Checked")
    var wasChecked: Bool?

    init() {}
    init(line: Int, content: String? = nil, wasChecked: Bool? = nil) {
        self.line = line
        self.content = content
        self.wasChecked = wasChecked
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Log.intents.notice("\(Self.self) running in \(Log.process, privacy: .public)")
        NoteStore.shared.reloadFromDisk()
        NoteStore.shared.toggleLine(line, expecting: content, wasChecked: wasChecked)
        NoteStore.shared.flushWidgetReload()
        await LiveActivityManager.shared.reconcile()
        return .result()
    }
}

/// Puts the note back on the Lock Screen with a fresh 8-hour clock.
/// Built for Shortcuts automations, the Control and the refresh buttons.
struct KeepOnLockScreenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Keep mynote on Lock Screen"
    static let description = IntentDescription(
        "Shows your mynote list on the Lock Screen and Dynamic Island, restarting it with a fresh timer. Add it to a Shortcuts automation to keep your list there all the time.",
        categoryName: "Lock Screen"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        Log.intents.notice("\(Self.self) running in \(Log.process, privacy: .public)")
        NoteStore.shared.reloadFromDisk()
        await LiveActivityManager.shared.goLive()
        return .result()
    }
}

/// Takes the note off the Lock Screen.
struct HideFromLockScreenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Hide mynote from Lock Screen"
    static let description = IntentDescription("Removes your list from the Lock Screen and Dynamic Island.", categoryName: "Lock Screen")

    @MainActor
    func perform() async throws -> some IntentResult {
        Log.intents.notice("\(Self.self) running in \(Log.process, privacy: .public)")
        await LiveActivityManager.shared.stop()
        return .result()
    }
}

/// Drives the on/off Control in Control Center and on the Lock Screen.
struct SetLiveIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Show mynote on Lock Screen"
    static let isDiscoverable = false

    @Parameter(title: "Show on Lock Screen")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        Log.intents.notice("\(Self.self) running in \(Log.process, privacy: .public)")
        NoteStore.shared.reloadFromDisk()
        if value {
            await LiveActivityManager.shared.goLive()
        } else {
            await LiveActivityManager.shared.stop()
        }
        return .result()
    }
}

/// Adds a checklist item from Siri / Shortcuts.
struct AddItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add Item to mynote"
    static let description = IntentDescription("Adds a new checklist item to the end of your note.", categoryName: "Note")

    @Parameter(title: "Item", requestValueDialog: "What should I add?")
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to mynote")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Log.intents.notice("\(Self.self) running in \(Log.process, privacy: .public)")
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $item.needsValueError("What should I add?")
        }
        NoteStore.shared.reloadFromDisk()
        let added = NoteStore.shared.appendItem(trimmed)
        NoteStore.shared.flushWidgetReload()
        await LiveActivityManager.shared.reconcile()
        return .result(dialog: added ? "Added to your list." : "Your note is full. mynote keeps lists under \(NoteParser.characterLimit) characters.")
    }
}

/// Clears all ticked items.
struct ClearCompletedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clear Completed Items"
    static let description = IntentDescription("Removes every ticked checklist item from your note.", categoryName: "Note")

    @MainActor
    func perform() async throws -> some IntentResult {
        Log.intents.notice("\(Self.self) running in \(Log.process, privacy: .public)")
        NoteStore.shared.reloadFromDisk()
        NoteStore.shared.removeCompleted()
        NoteStore.shared.flushWidgetReload()
        await LiveActivityManager.shared.reconcile()
        return .result()
    }
}
