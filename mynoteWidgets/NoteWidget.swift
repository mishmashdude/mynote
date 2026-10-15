import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct NoteEntry: TimelineEntry {
    let date: Date
    let text: String
    let settings: SettingsSnapshot
    /// Whether the list is actually on the Lock Screen at `date`.
    var isLive: Bool = false
    /// A line that was just ticked. It stays crossed out until this entry's moment passes.
    var justTicked: Int? = nil
}

struct NoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, text: "# Today\n- [x] Ship the update\n- [ ] Reply to **Sam**\n- [ ] Gym at 6\n- Pick up coffee beans", settings: .load())
    }

    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> Void) {
        let text = NoteFile.load().current.text
        completion(NoteEntry(date: .now, text: text.isEmpty && context.isPreview ? placeholder(in: context).text : text, settings: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> Void) {
        let settings = SettingsSnapshot.load()
        let text = NoteFile.load().current.text
        let live = settings.isEffectivelyLive && ActivityAuthorizationInfo().areActivitiesEnabled
        let now = Date()
        var entries = [NoteEntry(date: now, text: text, settings: settings, isLive: live, justTicked: RecentTick.line(at: now))]
        if live, let end = settings.coveredUntil {
            // Drop the freshly ticked line once its strike has been seen, then flip to
            // Go Live when the relay runs out. Both have to stay in time order.
            if let until = RecentTick.expiresAt(), until > now, until < end {
                entries.append(NoteEntry(date: until, text: text, settings: settings, isLive: true))
            }
            entries.append(NoteEntry(date: end, text: text, settings: settings, isLive: false))
        } else if let until = RecentTick.expiresAt(), until > now {
            entries.append(NoteEntry(date: until, text: text, settings: settings, isLive: live))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct NoteWidget: Widget {
    let kind = "NoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoteProvider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("mynote")
        .description("Your note. Tick boxes right on the widget, tap anywhere else to open mynote.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NoteWidgetView: View {
    let entry: NoteEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let theme = entry.settings.themeChoice.theme(for: scheme)
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .accessoryCircular: circular
            default: home(theme: theme)
            }
        }
        // Tapping anything but a checkbox opens the app. An empty note opens straight into the editor.
        .widgetURL(URL(string: NoteParser.visibleLines(entry.text).isEmpty ? "mynote://edit" : "mynote://open"))
    }

    // MARK: Home screen

    private func home(theme: Theme) -> some View {
        let size = entry.settings.textSize.widgetPointSize
        let maxLines: Int = switch family {
        case .systemSmall: 6
        case .systemMedium: 5
        default: 14
        }
        return VStack(alignment: .leading, spacing: 6) {
            if family != .systemSmall {
                HStack {
                    Text("mynote")
                        .font(entry.settings.font.font(size: 12, bold: true))
                        .foregroundStyle(theme.subColor)
                    Spacer()
                    liveBadge(theme: theme)
                }
            }
            WidgetNoteContent(
                text: entry.text,
                theme: theme,
                font: entry.settings.font,
                size: size,
                maxLines: maxLines,
                allowsColumns: family != .systemSmall,
                justTicked: entry.justTicked
            )
        }
        .containerBackground(for: .widget) {
            theme.cardColor
        }
    }

    @ViewBuilder
    private func liveBadge(theme: Theme) -> some View {
        if entry.isLive {
            HStack(spacing: 4) {
                Circle().fill(theme.mainColor).frame(width: 6, height: 6)
                Text("Live")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.subColor)
            }
        } else {
            Button(intent: KeepOnLockScreenIntent()) {
                Label("Go Live", systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.mainColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Lock screen accessories

    private var rectangular: some View {
        let visible = NoteParser.visibleLines(entry.text).filter { $0.kind != .blank && $0.kind != .divider }
        let settled = FittedNoteLines.hidingFinished(visible, keeping: Set(entry.justTicked.map { [$0] } ?? []))
        let lines = Array(settled.shown.prefix(3))
        return VStack(alignment: .leading, spacing: 1) {
            if lines.isEmpty && settled.hiddenDone == 0 {
                Text("mynote").font(.headline)
                Text("Tap to write your list").font(.caption).foregroundStyle(.secondary)
            } else if lines.isEmpty {
                Text("\(settled.hiddenDone) done").font(.headline)
            } else {
                ForEach(lines) { line in
                    HStack(spacing: 4) {
                        switch line.kind {
                        case .todo(let checked):
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11, weight: .semibold))
                        case .bullet:
                            Text("•")
                        case .numbered:
                            Text("\(line.ordinal ?? 1).").monospacedDigit()
                        case .quote:
                            Capsule().frame(width: 2, height: 11)
                        default:
                            EmptyView()
                        }
                        Text(InlineMarkdown.attributed(line.content, font: .system, size: 13,
                                                       color: line.isChecked ? .secondary : .primary, accent: .primary,
                                                       bold: line.isHeading, struck: line.isChecked, onWidget: true))
                            .foregroundStyle(line.isChecked ? .secondary : .primary)
                            .lineLimit(1)
                    }
                }
                if lines.count < 3, settled.hiddenDone > 0 {
                    Text("\(settled.hiddenDone) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        let progress = NoteParser.progress(entry.text)
        let lines = NoteParser.visibleLines(entry.text)
        let nextTask = lines.first { $0.isTodo && !$0.isChecked }
        let firstLine = lines.first { $0.kind != .blank && $0.kind != .divider }
        return Group {
            if progress.total > 0 {
                Label("\(progress.total - progress.done) left · \(nextTask?.plainContent ?? "All done")", systemImage: "checklist")
            } else {
                Label(firstLine?.plainContent ?? "mynote", systemImage: "note.text")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        let progress = NoteParser.progress(entry.text)
        return Group {
            if progress.total > 0 {
                Gauge(value: Double(progress.done), in: 0...Double(max(progress.total, 1))) {
                    Image(systemName: "checklist")
                } currentValueLabel: {
                    Text("\(progress.done)/\(progress.total)")
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "note.text").font(.title3)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

#Preview(as: .systemMedium) {
    NoteWidget()
} timeline: {
    NoteEntry(date: .now, text: "# Today\n- [x] Ship the update\n- [ ] Reply to **Sam**\n- Coffee ==beans==", settings: .load())
}
