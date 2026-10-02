import SwiftUI
import UserNotifications

@main
struct MynoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.id)) {
            await LiveActivityManager.shared.reconcile(fromBackground: true)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let keep = UNNotificationAction(identifier: ExpiryReminder.keepAction, title: "Keep on Lock Screen", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ExpiryReminder.category, actions: [keep], intentIdentifiers: [])
        ])
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        // Opening the app from the reminder is enough: put the note straight back.
        await Task { @MainActor in
            await LiveActivityManager.shared.reconcile()
        }.value
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    private var settings = AppSettings.shared
    @State private var showOnboarding = !AppSettings.shared.hasOnboarded

    var body: some View {
        let theme = settings.theme(for: colorScheme)
        HomeView()
            .environment(\.theme, theme)
            .tint(theme.mainColor)
            .onAppear { applyInterfaceStyle() }
            .onChange(of: settings.themeChoice) { applyInterfaceStyle() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                NoteStore.shared.reloadFromDisk()
                settings.reload()
                Task { await LiveActivityManager.shared.reconcile() }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    settings.hasOnboarded = true
                    showOnboarding = false
                }
                .environment(\.theme, theme)
            }
    }

    /// Forces light/dark on every window (including sheets) so the chosen theme's
    /// system controls and glass match. `preferredColorScheme(nil)` can't reliably undo an override.
    private func applyInterfaceStyle() {
        let style: UIUserInterfaceStyle = switch settings.themeChoice.forcedScheme {
        case .dark: .dark
        case .light: .light
        default: .unspecified
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
