import ActivityKit
import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit
#if !WIDGET_EXTENSION
import BackgroundTasks
#endif

struct NoteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var text: String
        var lightThemeID: String
        var darkThemeID: String
        var font: NoteFont
        var textSize: TextSize
        var style: LiveStyle
        /// True when another Live Activity is scheduled to take over from this one.
        var relaying: Bool

        func theme(for scheme: ColorScheme) -> Theme {
            ThemeCatalog.theme(scheme == .dark ? darkThemeID : lightThemeID)
        }
    }

    /// When this activity started (or is scheduled to start).
    var startedAt: Date
    /// Increasing number so newer activities sort above older ones.
    var sequence: Int
}

typealias NoteActivity = Activity<NoteActivityAttributes>

/// Keeps the note on the Lock Screen for as long as iOS allows — and then some.
///
/// iOS ends a Live Activity after 8 hours. To stay visible, mynote builds a
/// *relay*: while the app is open it starts one activity now and schedules the
/// next few to start (iOS 26 `start:` date) just before the previous one runs
/// out. Each time the app, a widget button, a Control or a Shortcut runs, the
/// relay is tidied up and extended. If everything runs out anyway, a reminder
/// notification brings the user back with one tap.
@Observable
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// How long iOS keeps a Live Activity running.
    static let lifetime: TimeInterval = 8 * 60 * 60
    /// The next activity starts this long before the previous one ends.
    static let handoffLead: TimeInterval = 90
    /// How many future activities we try to keep scheduled.
    static let relayDepth = 4
    static var stride: TimeInterval { lifetime - handoffLead }

    enum Status: Equatable {
        case off
        case live
        case unavailable
        case failed(String)
    }

    private(set) var status: Status = .off
    /// When the last scheduled activity in the relay will end. Shared with the widget and
    /// the Control so they can tell whether anything is really on the Lock Screen.
    private(set) var coveredUntil: Date? {
        didSet {
            guard coveredUntil != oldValue else { return }
            SettingsSnapshot.storeCoveredUntil(coveredUntil)
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenterReloader.reload()
        }
    }
    /// Number of future activities currently scheduled.
    private(set) var scheduledCount = 0

    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var observeTask: Task<Void, Never>?

    private init() {}

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Live Activities only exist on iPhone (not on iPad or when the iPhone app runs on a Mac).
    static var deviceSupportsLiveActivities: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && !ProcessInfo.processInfo.isiOSAppOnMac
    }
    private var activities: [NoteActivity] { NoteActivity.activities }

    private var running: [NoteActivity] {
        activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .sorted { $0.attributes.startedAt > $1.attributes.startedAt }
    }

    private var pending: [NoteActivity] {
        activities
            .filter { $0.activityState == .pending }
            .sorted { $0.attributes.startedAt < $1.attributes.startedAt }
    }

    // MARK: - Public API
    //
    // Every operation is queued and runs one at a time. Without this, overlapping calls
    // (a double tap on the Refresh control, an intent racing the app coming to the
    // foreground) could each start their own activity and leave duplicates behind.

    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    private func serially<T>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = lastOperation
        let operation = Task { @MainActor () -> T in
            await previous?.value
            return await body()
        }
        lastOperation = Task { _ = await operation.value }
        return await operation.value
    }

    /// Turn Live on and put the note on the Lock Screen right now.
    @discardableResult
    func goLive() async -> Bool {
        await serially { await self.performGoLive() }
    }

    /// Turn Live off and remove every activity.
    func stop() async {
        await serially { await self.performStop() }
    }

    /// Replace everything with a brand-new activity (fresh 8-hour clock) and a new relay.
    func restart() async {
        await serially { await self.performRestart() }
    }

    /// Bring the activities in line with what the user wants. Safe to call any time.
    func reconcile(fromBackground: Bool = false) async {
        await serially { await self.performReconcile(fromBackground: fromBackground) }
    }

    /// Re-create the scheduled activities (e.g. after the Silent Refresh setting changes).
    func restartRelayIfLive() async {
        await serially { await self.performRestartRelay() }
    }

    // MARK: - Operations (only ever called through `serially`)

    private func performGoLive() async -> Bool {
        guard activitiesEnabled else {
            status = .unavailable
            return false
        }
        AppSettings.shared.liveEnabled = true
        await performRestart()
        if status != .live {
            AppSettings.shared.liveEnabled = false
        }
        return status == .live
    }

    private func performStop() async {
        AppSettings.shared.liveEnabled = false
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        status = .off
        coveredUntil = nil
        scheduledCount = 0
        ExpiryReminder.cancel()
    }

    private func performRestart() async {
        startObserving()
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard SettingsSnapshot.load().liveEnabled else { return }
        do {
            try requestNow()
        } catch {
            Log.live.error("requestNow failed: \(error.localizedDescription, privacy: .public)")
            status = activitiesEnabled ? .failed(error.localizedDescription) : .unavailable
            return
        }
        await extendRelay()
        refreshStatus()
        scheduleSafetyNets()
    }

    private func performReconcile(fromBackground: Bool) async {
        startObserving()
        Log.live.notice("reconcile in \(Log.process, privacy: .public): \(self.activities.count) activities [\(self.activities.map { "\($0.activityState)" }.joined(separator: ","), privacy: .public)]")
        guard SettingsSnapshot.load().liveEnabled else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            status = .off
            coveredUntil = nil
            scheduledCount = 0
            ExpiryReminder.cancel()
            return
        }
        guard activitiesEnabled else {
            status = .unavailable
            return
        }

        let now = Date()

        // 1. Clear out finished activities still lingering on the Lock Screen.
        for activity in activities where activity.activityState == .ended || activity.activityState == .dismissed {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        // 2. Keep only the newest running activity that still has time left.
        var keeper = running.first { $0.attributes.startedAt.addingTimeInterval(Self.lifetime) > now.addingTimeInterval(60) }
        for activity in running where activity.id != keeper?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        // 3. Nothing on screen? Start a fresh one (works in the foreground and from intents).
        if keeper == nil {
            for activity in pending {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            do {
                keeper = try requestNow()
            } catch {
                if !fromBackground { status = .failed(error.localizedDescription) }
            }
        } else if let current = keeper, !fromBackground, !SettingsSnapshot.load().autoRelay,
                  now.timeIntervalSince(current.attributes.startedAt) > 4 * 60 * 60 {
            // Without the relay, top the clock back up whenever the app is opened.
            if let fresh = try? requestNow() {
                await current.end(nil, dismissalPolicy: .immediate)
                keeper = fresh
            }
        }

        // Anything else still running is a leftover; keep exactly one on screen.
        for activity in running where activity.id != keeper?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        // 4. Make sure future activities are lined up, and everything shows the latest note.
        await extendRelay()
        await pushContent()
        refreshStatus()
        scheduleSafetyNets()
    }

    private func performRestartRelay() async {
        guard SettingsSnapshot.load().liveEnabled else { return }
        for activity in pending {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        await extendRelay()
        refreshStatus()
        scheduleSafetyNets()
    }

    /// Call after the note or the look changes.
    func contentDidChange(immediate: Bool = false) {
        guard SettingsSnapshot.load().liveEnabled else { return }
        pushTask?.cancel()
        pushTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            await serially { await self.pushContent() }
        }
    }

    // MARK: - Internals

    func makeState() -> NoteActivityAttributes.ContentState {
        let s = SettingsSnapshot.load()
        let ids = s.themeChoice.liveIDs
        return NoteActivityAttributes.ContentState(
            text: NoteStore.shared.current.text,
            lightThemeID: ids.light,
            darkThemeID: ids.dark,
            font: s.font,
            textSize: s.textSize,
            style: s.liveStyle,
            relaying: s.autoRelay
        )
    }

    private func content(for attributes: NoteActivityAttributes,
                         state: NoteActivityAttributes.ContentState) -> ActivityContent<NoteActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: attributes.startedAt.addingTimeInterval(Self.stride),
            relevanceScore: Double(attributes.sequence % 1_000_000)
        )
    }

    @discardableResult
    private func requestNow() throws -> NoteActivity {
        let attributes = NoteActivityAttributes(startedAt: .now, sequence: SettingsSnapshot.nextActivitySequence())
        return try NoteActivity.request(
            attributes: attributes,
            content: content(for: attributes, state: makeState()),
            pushType: nil
        )
    }

    private func requestScheduled(at date: Date) throws {
        let attributes = NoteActivityAttributes(startedAt: date, sequence: SettingsSnapshot.nextActivitySequence())
        let silent = SettingsSnapshot.load().silentRelay
        let alert = AlertConfiguration(
            title: "mynote",
            body: "Your list is still on your Lock Screen.",
            sound: silent ? .named("silence.caf") : .default
        )
        _ = try NoteActivity.request(
            attributes: attributes,
            content: content(for: attributes, state: makeState()),
            pushType: nil,
            style: .standard,
            alertConfiguration: alert,
            start: date
        )
    }

    /// Schedules the next activities so they take over just before the current one expires.
    private func extendRelay() async {
        let anchor = running.first
        let scheduled = pending
        guard SettingsSnapshot.load().autoRelay, let anchor else {
            for activity in scheduled {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            scheduledCount = 0
            coveredUntil = anchor.map { $0.attributes.startedAt.addingTimeInterval(Self.lifetime) }
            return
        }

        var wanted = (1...Self.relayDepth).map {
            anchor.attributes.startedAt.addingTimeInterval(Double($0) * Self.stride)
        }
        for activity in scheduled {
            if let match = wanted.firstIndex(where: { abs($0.timeIntervalSince(activity.attributes.startedAt)) < 120 }) {
                wanted.remove(at: match)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        for date in wanted {
            do {
                try requestScheduled(at: date)
                Log.live.notice("scheduled relay activity for \(date, privacy: .public)")
            } catch {
                Log.live.error("scheduling relay failed: \(error.localizedDescription, privacy: .public)")
                // Hit the per-app limit or scheduling isn't available — keep what we have.
                break
            }
        }
        let lastStart = pending.last?.attributes.startedAt ?? anchor.attributes.startedAt
        scheduledCount = pending.count
        coveredUntil = lastStart.addingTimeInterval(Self.lifetime)
    }

    private func pushContent() async {
        let state = makeState()
        Log.live.notice("pushContent to \(self.activities.count) activities")
        for activity in activities where activity.activityState == .active || activity.activityState == .pending || activity.activityState == .stale {
            guard activity.content.state != state else { continue }
            await activity.update(content(for: activity.attributes, state: state))
        }
    }

    private func refreshStatus() {
        guard SettingsSnapshot.load().liveEnabled else {
            status = .off
            return
        }
        if !activitiesEnabled {
            status = .unavailable
        } else if !running.isEmpty || !pending.isEmpty {
            status = .live
        } else if case .failed = status {
            // keep the error message
        } else {
            status = .failed("The Live Activity couldn't be started.")
        }
    }

    private func scheduleSafetyNets() {
        guard let until = coveredUntil else { return }
        if SettingsSnapshot.load().expiryReminders {
            Task { await ExpiryReminder.schedule(at: until.addingTimeInterval(-15 * 60)) }
        } else {
            ExpiryReminder.cancel()
        }
        #if !WIDGET_EXTENSION
        // Wake up shortly after the next handoff to tidy the old activity away.
        let nextHandoff = pending.first?.attributes.startedAt ?? until
        BackgroundRefresh.schedule(at: nextHandoff.addingTimeInterval(120))
        #endif
    }

    private func startObserving() {
        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            for await activity in NoteActivity.activityUpdates {
                Task { [weak self] in
                    for await _ in activity.activityStateUpdates {
                        self?.refreshStatus()
                    }
                }
                self?.refreshStatus()
            }
        }
    }
}

// MARK: - Expiry reminder

enum ExpiryReminder {
    static let id = "mynote.expiry"
    static let category = "mynote.expiry"
    static let keepAction = "mynote.keep"

    static func schedule(at date: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let interval = date.timeIntervalSinceNow
        guard interval > 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Keep your list on the Lock Screen"
        content.body = "Your mynote Live Activity is about to run out. Tap to keep it there."
        content.categoryIdentifier = category
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

#if !WIDGET_EXTENSION
enum BackgroundRefresh {
    static let id = "com.andi.mynote.refresh"

    static func schedule(at date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = max(date, Date().addingTimeInterval(15 * 60))
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif
