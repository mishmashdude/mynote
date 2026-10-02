import AppIntents
import SwiftUI
import WidgetKit

struct NoteEntry: TimelineEntry {
    let date: Date
    let text: String
    let settings: SettingsSnapshot
}

struct NoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, text: "[x] Ship the update\n[ ] Reply to Sam\n[ ] Gym at 6\n- Pick up coffee beans", settings: .load())
    }

    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> Void) {
        let text = NoteFile.load().current.text
        completion(NoteEntry(date: .now, text: text.isEmpty && context.isPreview ? placeholder(in: context).text : text, settings: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> Void) {
        let entry = NoteEntry(date: .now, text: NoteFile.load().current.text, settings: .load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct NoteWidget: Widget {
    let kind = "NoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoteProvider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("mynote")
        .description("Your note, with tappable checkboxes.")
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
        .widgetURL(URL(string: "mynote://edit"))
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
                maxLines: maxLines
            )
        }
        .containerBackground(for: .widget) {
            theme.cardColor
        }
    }

    @ViewBuilder
    private func liveBadge(theme: Theme) -> some View {
        if entry.settings.liveEnabled {
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
        let lines = Array(NoteParser.visibleLines(entry.text).prefix(3))
        return VStack(alignment: .leading, spacing: 1) {
            if lines.isEmpty {
                Text("mynote").font(.headline)
                Text("Tap to write your list").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(lines) { line in
                    HStack(spacing: 4) {
                        switch line.kind {
                        case .todo(let checked):
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11, weight: .semibold))
                        case .bullet:
                            Text("•")
                        default:
                            EmptyView()
                        }
                        Text(line.content)
                            .font(.system(size: 13, weight: line.kind == .heading ? .bold : .regular))
                            .strikethrough(line.isChecked)
                            .foregroundStyle(line.isChecked ? .secondary : .primary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        let progress = NoteParser.progress(entry.text)
        let first = NoteParser.visibleLines(entry.text).first { !$0.isChecked && $0.kind != .blank }
        return Group {
            if progress.total > 0 {
                Label("\(progress.total - progress.done) left · \(first?.content ?? "All done")", systemImage: "checklist")
            } else {
                Label(first?.content ?? "mynote", systemImage: "note.text")
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
    NoteEntry(date: .now, text: "# Today\n[x] Ship the update\n[ ] Reply to Sam\n- Coffee beans", settings: .load())
}
