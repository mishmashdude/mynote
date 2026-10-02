import AppIntents

struct MynoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KeepOnLockScreenIntent(),
            phrases: [
                "Keep \(.applicationName) on my Lock Screen",
                "Refresh \(.applicationName)",
                "Pin \(.applicationName)",
            ],
            shortTitle: "Keep on Lock Screen",
            systemImageName: "pin"
        )
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add an item to \(.applicationName)",
            ],
            shortTitle: "Add Item",
            systemImageName: "plus.square"
        )
        AppShortcut(
            intent: ClearCompletedIntent(),
            phrases: ["Clear completed in \(.applicationName)"],
            shortTitle: "Clear Completed",
            systemImageName: "checkmark.square"
        )
        AppShortcut(
            intent: HideFromLockScreenIntent(),
            phrases: ["Hide \(.applicationName) from my Lock Screen"],
            shortTitle: "Hide from Lock Screen",
            systemImageName: "pin.slash"
        )
    }
}
