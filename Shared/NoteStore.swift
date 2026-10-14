import Foundation
import Observation
import WidgetKit

/// The single source of truth for the current note and the archive.
@Observable
@MainActor
final class NoteStore {
    static let shared = NoteStore()

    private(set) var document: NoteDocument

    @ObservationIgnored private var widgetReloadTask: Task<Void, Never>?

    private init() {
        document = NoteFile.load()
    }

    var current: Note { document.current }
    var archived: [Note] { document.archived }

    // MARK: Editing

    func setText(_ text: String) {
        guard text != document.current.text else { return }
        document.current.text = text
        document.current.updatedAt = .now
        commit()
    }

    /// Toggles the checkbox on `index`. A widget or Live Activity may have been drawn
    /// before the note last changed, so `expected` (the item's text then) and `wasChecked`
    /// guard against ticking the wrong thing:
    /// - the line at `index` is the same item: toggle it, unless it has already been flipped;
    /// - the note moved on: toggle the closest checkbox with the same words, if any.
    /// Words are compared without Markdown, which the Rich Text editor may have respelled.
    /// Returns the line that was toggled, if any.
    @discardableResult
    func toggleLine(_ index: Int, expecting expected: String? = nil, wasChecked: Bool? = nil) -> Int? {
        var target = index
        if let expected {
            let lines = NoteParser.parse(document.current.text)
            let words = InlineMarkdown.plain(expected)
            let sameItem: (NoteLine) -> Bool = { $0.isTodo && $0.plainContent == words }
            if lines.indices.contains(index), sameItem(lines[index]) {
                if let wasChecked, lines[index].isChecked != wasChecked { return nil }
            } else {
                let candidates = lines.filter { sameItem($0) && (wasChecked == nil || $0.isChecked == wasChecked) }
                guard let nearest = candidates.min(by: { abs($0.id - index) < abs($1.id - index) }) else { return nil }
                target = nearest.id
            }
        }
        let newText = NoteParser.toggle(document.current.text, line: target)
        guard newText != document.current.text else { return nil }
        document.current.text = newText
        document.current.updatedAt = .now
        commit(immediate: true)
        return target
    }

    func setAllTodos(checked: Bool) {
        setText(NoteParser.setAllTodos(document.current.text, checked: checked))
    }

    func removeCompleted() {
        setText(NoteParser.removeCheckedTodos(document.current.text))
    }

    /// Appends a new checklist line. Returns false when it would go over the limit.
    @discardableResult
    func appendItem(_ item: String, asTodo: Bool = true) -> Bool {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let line = (asTodo ? "- [ ] " : "") + trimmed
        var text = document.current.text
        while text.hasSuffix("\n") { text.removeLast() }
        let newText = text.isEmpty ? line : text + "\n" + line
        guard NoteParser.countedLength(newText) <= NoteParser.characterLimit else { return false }
        setText(newText)
        return true
    }

    // MARK: Archive

    /// Moves the note on screen into the Archive and starts a fresh one.
    /// Returns the archived note's id so the move can be undone.
    @discardableResult
    func archiveCurrent() -> UUID? {
        guard !document.current.isEmpty else { return nil }
        var note = document.current
        note.archivedAt = .now
        document.archived.insert(note, at: 0)
        document.current = Note()
        commit(immediate: true)
        return note.id
    }

    /// Brings an archived note back. The note currently on screen (if any) is archived in its place.
    func restore(_ id: UUID) {
        guard let index = document.archived.firstIndex(where: { $0.id == id }) else { return }
        var restored = document.archived.remove(at: index)
        restored.archivedAt = nil
        restored.updatedAt = .now
        if !document.current.isEmpty {
            var old = document.current
            old.archivedAt = .now
            document.archived.insert(old, at: 0)
        }
        document.current = restored
        commit(immediate: true)
    }

    func deleteArchived(_ ids: Set<UUID>) {
        document.archived.removeAll { ids.contains($0.id) }
        NoteFile.save(document)
    }

    // MARK: Sync

    /// Picks up changes written by another process (e.g. a widget intent).
    func reloadFromDisk() {
        guard let disk = NoteFile.loadExisting(), disk != document else { return }
        document = disk
    }

    /// Reload widgets right now (intents may be suspended before a debounced reload fires).
    func flushWidgetReload() {
        widgetReloadTask?.cancel()
        widgetReloadTask = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func commit(immediate: Bool = false) {
        NoteFile.save(document)
        LiveActivityManager.shared.contentDidChange(immediate: immediate)
        widgetReloadTask?.cancel()
        if immediate {
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            widgetReloadTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
