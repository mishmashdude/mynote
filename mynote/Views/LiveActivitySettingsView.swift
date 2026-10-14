import SwiftUI
import UserNotifications

struct LiveActivitySettingsView: View {
    @Environment(\.theme) private var theme
    @Bindable private var settings = AppSettings.shared
    private var live = LiveActivityManager.shared

    @State private var refreshTick = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    LockScreenPreview()
                    Text("Live Activity")
                        .font(.headline)
                    Text("After you go live, your note appears on the Lock Screen, with checkboxes you can tick without opening the app. iOS ends each Live Activity after 8 hours, so mynote lines up fresh ones back to back to keep your list there.")
                        .font(.subheadline)
                        .foregroundStyle(theme.subColor)
                }
                .padding(.vertical, 10)
            }
            .listRowBackground(theme.cardColor)

            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    statusLabel
                }
                if settings.liveEnabled {
                    Button {
                        Task {
                            await live.restart()
                            refreshTick += 1
                        }
                    } label: {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                            .foregroundStyle(theme.mainColor)
                    }
                }
            } footer: {
                if settings.liveEnabled, let until = live.coveredUntil {
                    Text("Your list is lined up to stay on screen until \(until.formatted(date: .abbreviated, time: .shortened)). Opening mynote extends it.")
                        .foregroundStyle(theme.subColor)
                }
            }
            .listRowBackground(theme.cardColor)

            Section {
                ForEach(LiveStyle.allCases) { style in
                    Button {
                        settings.liveStyle = style
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.name).foregroundStyle(theme.textColor)
                                Text(style.detail).font(.caption).foregroundStyle(theme.subColor)
                            }
                            Spacer()
                            if settings.liveStyle == style {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(theme.mainColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Appearance").foregroundStyle(theme.subColor)
            } footer: {
                Text("Choose how your note looks on the Lock Screen.")
                    .foregroundStyle(theme.subColor)
            }
            .listRowBackground(theme.cardColor)

            Section {
                Toggle(isOn: $settings.autoRelay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Refresh")
                        Text("Schedule fresh Live Activities before each one expires.")
                            .font(.caption)
                            .foregroundStyle(theme.subColor)
                    }
                }
                Toggle(isOn: $settings.silentRelay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Silent Refresh")
                        Text("No sound when a fresh Live Activity takes over.")
                            .font(.caption)
                            .foregroundStyle(theme.subColor)
                    }
                }
                .disabled(!settings.autoRelay)
                Toggle(isOn: $settings.expiryReminders) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Expiry Reminder")
                        Text("A notification just before your list would disappear.")
                            .font(.caption)
                            .foregroundStyle(theme.subColor)
                    }
                }
                NavigationLink {
                    KeepAliveGuideView()
                } label: {
                    Text("More Ways to Stay On Screen")
                }
            } header: {
                Text("Keep It There").foregroundStyle(theme.subColor)
            }
            .tint(theme.controlTint)
            .listRowBackground(theme.cardColor)
        }
        .themedList(theme)
        .navigationTitle("Live Activity")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: refreshTick)
        .onChange(of: settings.autoRelay) { Task { await live.reconcile() } }
        .onChange(of: settings.silentRelay) { Task { await live.restartRelayIfLive() } }
        .onChange(of: settings.expiryReminders) {
            Task {
                if settings.expiryReminders {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                }
                await live.reconcile()
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch live.status {
        case .live where settings.liveEnabled:
            Label("Live", systemImage: "circle.fill")
                .labelStyle(StatusLabelStyle(color: theme.mainColor))
        case .unavailable:
            Text(LiveActivityManager.deviceSupportsLiveActivities ? "Turned off in iOS Settings" : "Needs an iPhone")
                .foregroundStyle(theme.readableErrorColor)
        case .failed:
            Text("Needs attention").foregroundStyle(theme.readableErrorColor)
        default:
            Text("Off").foregroundStyle(theme.subColor)
        }
    }
}

private struct StatusLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 8)).foregroundStyle(color)
            configuration.title
        }
    }
}

/// A faithful mock of the Lock Screen with the real Live Activity view on it.
struct LockScreenPreview: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    private var settings = AppSettings.shared

    var body: some View {
        var state = LiveActivityManager.shared.makeState()
        if NoteStore.shared.current.isEmpty {
            state.text = "[x] Ship the update\n[ ] Reply to Sam\n[ ] Gym at 6\n- Coffee beans"
        }
        let liveTheme = state.theme(for: colorScheme)
        let palette = LivePalette(style: state.style, theme: liveTheme)

        return ZStack {
            LinearGradient(colors: [liveTheme.mainColor.opacity(0.85), Color(hex: 0x1B1F3B), Color(hex: 0x0B0C10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 18)
                Text(Date.now, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 10)
                LiveNoteView(state: state, interactive: false)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(palette.background ?? .clear)
                            .background {
                                if state.style == .glass {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                                }
                            }
                    }
                    .environment(\.colorScheme, colorScheme)
                    .padding(.horizontal, 10)
                HStack {
                    lockButton("flashlight.off.fill")
                    Spacer()
                    lockButton("camera.fill")
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
            }
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.smooth, value: settings.liveStyle)
    }

    private func lockButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .glassEffect(.regular, in: .circle)
    }
}
