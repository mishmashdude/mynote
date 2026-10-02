import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct NoteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoteActivityAttributes.self) { context in
            LockScreenLiveView(context: context)
        } dynamicIsland: { context in
            let theme = context.state.theme(for: .dark)
            let lines = NoteParser.visibleLines(context.state.text)
            let progress = NoteParser.progress(context.state.text)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("mynote")
                            .font(context.state.font.font(size: 14, bold: true))
                    } icon: {
                        Image(systemName: "note.text")
                    }
                    .foregroundStyle(theme.islandAccent)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if progress.total > 0 {
                        Text("\(progress.done)/\(progress.total)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if lines.isEmpty {
                            Text("Your list is empty.")
                                .font(context.state.font.font(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                        } else {
                            FittedNoteLines(
                                lines: lines,
                                maxLines: 4,
                                font: context.state.font,
                                size: 14,
                                text: .white,
                                sub: .white.opacity(0.5),
                                accent: theme.islandAccent,
                                spacing: 3,
                                interaction: .intents
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: progress.total > 0 ? "checklist" : "note.text")
                    .foregroundStyle(theme.islandAccent)
            } compactTrailing: {
                if progress.total > 0 {
                    Text("\(progress.done)/\(progress.total)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.islandAccent)
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.islandAccent)
                }
            } minimal: {
                if progress.total > 0 {
                    Gauge(value: Double(progress.done), in: 0...Double(progress.total)) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(theme.islandAccent)
                } else {
                    Image(systemName: "note.text")
                        .foregroundStyle(theme.islandAccent)
                }
            }
            .keylineTint(theme.islandAccent)
            .widgetURL(URL(string: "mynote://open"))
        }
        .supplementalActivityFamilies([.small])
    }
}

struct LockScreenLiveView: View {
    let context: ActivityViewContext<NoteActivityAttributes>
    @Environment(\.colorScheme) private var scheme
    @Environment(\.activityFamily) private var family

    var body: some View {
        let theme = context.state.theme(for: scheme)
        let palette = LivePalette(style: context.state.style, theme: theme)
        Group {
            if family == .small {
                smallView(theme: theme)
            } else {
                LiveNoteView(state: context.state, isStale: context.isStale)
            }
        }
        .activityBackgroundTint(palette.background)
        .activitySystemActionForegroundColor(palette.text)
        .widgetURL(URL(string: "mynote://open"))
    }

    /// Apple Watch Smart Stack / CarPlay.
    private func smallView(theme: Theme) -> some View {
        let lines = NoteParser.visibleLines(context.state.text)
        return FittedNoteLines(
            lines: lines,
            maxLines: 3,
            font: context.state.font,
            size: 13,
            text: theme.textColor,
            sub: theme.subColor,
            accent: theme.mainColor,
            spacing: 2
        )
        .padding(10)
    }
}

#Preview("Lock Screen", as: .content, using: NoteActivityAttributes(startedAt: .now, sequence: 1)) {
    NoteLiveActivity()
} contentStates: {
    NoteActivityAttributes.ContentState(text: "# Today\n[x] Ship the update\n[ ] Reply to Sam\n[ ] Gym at 6\n- Coffee beans", lightThemeID: "serika", darkThemeID: "serika-dark", font: .mono, textSize: .regular, style: .theme, relaying: true)
}
