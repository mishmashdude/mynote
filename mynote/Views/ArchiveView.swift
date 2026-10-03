import SwiftUI

/// Every note sent away from the home screen waits here until it's deleted for good.
struct ArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    private var store = NoteStore.shared
    private var settings = AppSettings.shared

    @State private var search = ""
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var restoreTick = 0
    /// Notes waiting for "Delete for good?" to be confirmed.
    @State private var pendingDelete: Set<UUID> = []

    private var filtered: [Note] {
        guard !search.isEmpty else { return store.archived }
        return store.archived.filter { NoteParser.shareText($0.text).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.archived.isEmpty {
                    ContentUnavailableView {
                        Label("Your Archive is empty", systemImage: "archivebox")
                    } description: {
                        Text("Notes you delete land here, so nothing is lost by accident.")
                    }
                    .foregroundStyle(theme.textColor, theme.subColor)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List(selection: $selection) {
                        Section {
                            ForEach(filtered) { note in
                                ArchiveRow(note: note, theme: theme, font: settings.font, isSelecting: editMode.isEditing) {
                                    restore(note)
                                }
                                .listRowBackground(theme.cardColor)
                                .swipeActions(edge: .leading) {
                                    Button { restore(note) } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.indigo)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    // Deleting from the Archive is for good, so it always asks first.
                                    Button(role: .destructive) { pendingDelete = [note.id] } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text("Deleted notes stay here until you delete them from the Archive.")
                                .font(.footnote)
                                .foregroundStyle(theme.subColor)
                                .textCase(nil)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, $editMode)
                }
            }
            .background(theme.bgColor.ignoresSafeArea())
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                            selection.removeAll()
                        }
                    }
                    .disabled(store.archived.isEmpty)
                }
                if editMode.isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(selection.count == filtered.count ? "Deselect All" : "Select All") {
                            selection = selection.count == filtered.count ? [] : Set(filtered.map(\.id))
                        }
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            // Only what the search still shows.
                            pendingDelete = selection.intersection(filtered.map(\.id))
                        } label: {
                            Text(selection.isEmpty ? "Delete" : "Delete (\(selection.count))")
                        }
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .confirmationDialog(
                pendingDelete.count == 1 ? "Delete this note for good?" : "Delete \(pendingDelete.count) notes for good?",
                isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
                titleVisibility: .visible
            ) {
                Button(pendingDelete.count == 1 ? "Delete Note" : "Delete \(pendingDelete.count) Notes", role: .destructive) {
                    let ids = pendingDelete
                    withAnimation {
                        store.deleteArchived(ids)
                        selection.subtract(ids)
                        if editMode.isEditing, selection.isEmpty { editMode = .inactive }
                    }
                    pendingDelete = []
                }
            } message: {
                Text("This can't be undone.")
            }
        }
        .sensoryFeedback(.success, trigger: restoreTick)
    }

    private func restore(_ note: Note) {
        store.restore(note.id)
        restoreTick += 1
        dismiss()
    }
}

private struct ArchiveRow: View {
    let note: Note
    let theme: Theme
    let font: NoteFont
    let isSelecting: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                NoteLinesView(
                    lines: Array(NoteParser.visibleLines(note.text).prefix(4)),
                    font: font,
                    size: 15,
                    text: theme.textColor,
                    sub: theme.subColor,
                    accent: theme.mainColor,
                    spacing: 3,
                    lineLimit: 1,
                    compact: true
                )
                Text((note.archivedAt ?? note.updatedAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(theme.subColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NoteParser.spokenText(note.text))
            Spacer(minLength: 0)
            if !isSelecting {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textColor)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Restore note")
            }
        }
        .padding(.vertical, 6)
    }
}
