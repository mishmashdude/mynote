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

    func toggleLine(_ index: Int) {
        let newText = NoteParser.toggle(document.current.text, line: index)
        guard newText != document.current.text else { return }
        document.current.text = newText
        document.current.updatedAt = .now
        commit(immediate: true)
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
        let line = (asTodo ? "[ ] " : "") + trimmed
        var text = document.current.text
        while text.hasSuffix("\n") { text.removeLast() }
        let newText = text.isEmpty ? line : text + "\n" + line
        guard NoteParser.countedLength(newText) <= NoteParser.characterLimit else { return false }
        setText(newText)
        return true
    }

    // MARK: Archive

    func archiveCurrent() {
        guard !document.current.isEmpty else { return }
        var note = document.current
        note.archivedAt = .now
        document.archived.insert(note, at: 0)
        document.current = Note()
        commit(immediate: true)
    }

    func deleteCurrent() {
        document.current = Note()
        commit(immediate: true)
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
        let disk = NoteFile.load()
        if disk.current != document.current || disk.archived.count != document.archived.count {
            document = disk
        }
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
