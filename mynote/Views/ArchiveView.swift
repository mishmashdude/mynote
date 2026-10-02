import SwiftUI

struct ArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    private var store = NoteStore.shared

    @State private var search = ""
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var restoreTick = 0

    private var filtered: [Note] {
        guard !search.isEmpty else { return store.archived }
        return store.archived.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.archived.isEmpty {
                    ContentUnavailableView {
                        Label("No Archived Notes", systemImage: "archivebox")
                    } description: {
                        Text("Archived notes will appear here.")
                    }
                    .foregroundStyle(theme.textColor, theme.subColor)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List(selection: $selection) {
                        ForEach(filtered) { note in
                            ArchiveRow(note: note, theme: theme, isSelecting: editMode.isEditing) {
                                restore(note)
                            }
                            .listRowBackground(theme.cardColor)
                            .swipeActions(edge: .leading) {
                                Button { restore(note) } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.indigo)
                            }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { filtered[$0].id })
                            withAnimation { store.deleteArchived(ids) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, $editMode)
                }
            }
            .background(theme.bgColor.ignoresSafeArea())
            .navigationTitle("Archived Notes")
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
                        Button(role: .destructive) {
                            withAnimation {
                                store.deleteArchived(selection)
                                selection.removeAll()
                                editMode = .inactive
                            }
                        } label: {
                            Text(selection.isEmpty ? "Delete" : "Delete (\(selection.count))")
                        }
                        .disabled(selection.isEmpty)
                    }
                }
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
    let isSelecting: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NoteParser.shareText(note.text))
                    .font(AppSettings.shared.font.font(size: 15))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(4)
                Text((note.archivedAt ?? note.updatedAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(theme.subColor)
            }
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
