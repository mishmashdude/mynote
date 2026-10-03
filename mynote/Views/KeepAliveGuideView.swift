import SwiftUI
import UserNotifications

/// Explains every way mynote can keep the list on the Lock Screen, beyond iOS's 8-hour limit.
struct KeepAliveGuideView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private var settings = AppSettings.shared

    @State private var notificationsAllowed = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("iOS removes any Live Activity after 8 hours. mynote uses every tool iOS offers to keep your list in view, and most of them work without you lifting a finger.")
                    .font(.subheadline)
                    .foregroundStyle(theme.subColor)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                GuideCard(number: 1, icon: "arrow.triangle.2.circlepath", title: "Auto-Refresh",
                          badge: settings.autoRelay ? "On" : "Off") {
                    Text("When you go live, mynote also schedules the next few Live Activities to start just before the previous one ends. That covers about a day and a half without opening the app, and every time you open mynote the chain is topped up.")
                }

                GuideCard(number: 2, icon: "bell.badge", title: "Expiry Reminder",
                          badge: settings.expiryReminders && notificationsAllowed ? "On" : "Off") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("If the chain ever runs out, mynote sends a notification shortly before. Tap it and your list is straight back.")
                        if !notificationsAllowed {
                            Button { allowNotifications() } label: {
                                Text("Allow Notifications").foregroundStyle(theme.onMainColor)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(theme.mainColor)
                        }
                    }
                }

                GuideCard(number: 3, icon: "wand.and.stars", title: "Automate It with Shortcuts") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Let your iPhone refresh the list for you, e.g. every morning or whenever you plug in:")
                        StepList(steps: [
                            "Open Shortcuts → Automation → New Automation.",
                            "Choose Time of Day (e.g. 7:00 AM, Daily) or Charger → Is Connected.",
                            "Select Run Immediately, then tap Next.",
                            "Add the action \"Keep mynote on Lock Screen\" and tap Done.",
                        ], theme: theme)
                        Text("Add a couple of times through the day and your list never leaves.")
                        Button {
                            if let url = URL(string: "shortcuts://") { openURL(url) }
                        } label: {
                            Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.glass)
                    }
                }

                GuideCard(number: 4, icon: "switch.2", title: "Add the Controls") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("mynote has two controls: \"mynote Live\" (on/off) and \"Refresh mynote\" (fresh 8 hours, one tap).")
                        StepList(steps: [
                            "Swipe down from the top-right to open Control Center.",
                            "Tap + → Add a Control and search for mynote.",
                            "Or put one on your Lock Screen: touch and hold the Lock Screen → Customize → Lock Screen, then tap the flashlight or camera button to swap it.",
                        ], theme: theme)
                    }
                }

                GuideCard(number: 5, icon: "square.text.square", title: "Widgets") {
                    Text("The medium and large Home Screen widgets show a Go Live button whenever your list isn't on the Lock Screen. One tap puts it back.")
                }
            }
            .padding(16)
        }
        .background(theme.bgColor.ignoresSafeArea())
        .navigationTitle("Always on Lock Screen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkNotifications() }
        .onChange(of: scenePhase) { Task { await checkNotifications() } }
    }

    private func checkNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .authorized || status == .provisional
    }

    private func allowNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if status == .denied {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            } else {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            await checkNotifications()
            await LiveActivityManager.shared.reconcile()
        }
    }
}

private struct GuideCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let number: Int
    let icon: String
    let title: String
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.onMainColor)
                    .frame(width: 30, height: 30)
                    .background(theme.mainColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.textColor)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badge == "On" ? theme.mainColor : theme.subColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((badge == "On" ? theme.mainColor : theme.subColor).opacity(0.15), in: Capsule())
                }
            }
            content
                .font(.subheadline)
                .foregroundStyle(theme.subColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct StepList: View {
    let steps: [String]
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(theme.mainColor)
                    Text(step)
                        .foregroundStyle(theme.textColor)
                }
            }
        }
    }
}
