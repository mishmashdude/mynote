import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// On/off switch for Control Center (and the Lock Screen's bottom controls).
struct LiveToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlCenterReloader.liveControlKind, provider: Provider()) { isLive in
            ControlWidgetToggle("mynote on Lock Screen", isOn: isLive, action: SetLiveIntent()) { on in
                Label(on ? "Live" : "Off", systemImage: on ? "pin.fill" : "pin.slash")
            }
            .tint(.yellow)
        }
        .displayName("mynote Live")
        .description("Show or hide your list on the Lock Screen.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { true }

        func currentValue() async throws -> Bool {
            SettingsSnapshot.load().isEffectivelyLive && ActivityAuthorizationInfo().areActivitiesEnabled
        }
    }
}

/// One-tap "put it back / refresh the timer" button. Great on the Lock Screen
/// in place of the flashlight or camera.
struct KeepOnLockScreenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.andi.mynote.control.refresh") {
            ControlWidgetButton(action: KeepOnLockScreenIntent()) {
                Label("Refresh mynote", systemImage: "arrow.clockwise.circle")
            }
        }
        .displayName("Refresh mynote")
        .description("Puts your list back on the Lock Screen with a fresh timer.")
    }
}
