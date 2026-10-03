import SwiftUI
import SwiftData

struct RoomManagerView: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var rooms: [Room]
    @State private var showingCreator = false
    @State private var editingRoom: Room?
    @State private var deletingRoom: Room?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if rooms.isEmpty {
                    ContentUnavailableView {
                        Label("Chaque plante a sa place", systemImage: "door.left.hand.open")
                    } description: {
                        Text("Créez vos pièces pour organiser votre jardin.")
                    } actions: {
                        Button("Créer une pièce") { showingCreator = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { room in
                            HStack(spacing: 12) {
                                Button {
                                    editingRoom = room
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(room.name).foregroundStyle(.primary)
                                        Text(LocalizedCopy.plantCount(room.plants.count, locale: locale))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Renommer \(room.name)")
                                .accessibilityValue(LocalizedCopy.plantCount(room.plants.count, locale: locale))
                                .accessibilityIdentifier("rooms.edit.\(room.id)")
                                Button("Supprimer \(room.name)", systemImage: "trash", role: .destructive) {
                                    deletingRoom = room
                                }
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("rooms.delete.\(room.id)")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(SproutStyle.background)
            .navigationTitle("Gérer les pièces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.accessibilityIdentifier("rooms.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Créer une pièce", systemImage: "plus") { showingCreator = true }
                        .accessibilityIdentifier("rooms.add")
                }
            }
            .sheet(isPresented: $showingCreator) { RoomEditorView() }
            .sheet(item: $editingRoom) { RoomEditorView(room: $0) }
            .confirmationDialog("Supprimer \(deletingRoom?.name ?? "") ?",
                                isPresented: Binding(get: { deletingRoom != nil },
                                                     set: { if !$0 { deletingRoom = nil } }),
                                titleVisibility: .visible, presenting: deletingRoom) { room in
                Button("Supprimer la pièce", role: .destructive) { deleteRoom(room) }
                    .accessibilityIdentifier("rooms.confirmDelete")
                Button("Annuler", role: .cancel) { deletingRoom = nil }
            } message: { _ in
                Text("Ses plantes seront déplacées vers « Sans pièce ». Les plantes et leurs arrosages seront conservés.")
            }
            .saveErrorAlert($errorMessage)
        }
    }

    private func deleteRoom(_ room: Room) {
        do { try PlantStore(context: context).deleteRoom(room) }
        catch { errorMessage = String(localized: "La pièce n’a pas été supprimée. Réessayez.") }
        deletingRoom = nil
    }
}

struct RoomEditorView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let room: Room?
    private let onSave: (Room) -> Void
    @State private var name: String
    @State private var errorMessage: String?

    init(room: Room? = nil, onSave: @escaping (Room) -> Void = { _ in }) {
        self.room = room
        self.onSave = onSave
        _name = State(initialValue: room?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Votre pièce") {
                    TextField("Nom de la pièce", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("roomEditor.name")
                }
            }
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if dynamicTypeSize.isAccessibilitySize {
                    ToolbarItem(placement: .principal) {
                        editorTitle
                            // The navigation bar has fixed height; the full-size section headings remain below.
                            .font(.system(size: 17, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.accessibilityIdentifier("roomEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("roomEditor.save")
                }
            }
            .saveErrorAlert($errorMessage)
        }
    }

    private var editorTitle: Text {
        room == nil ? Text("Nouvelle pièce") : Text("Renommer la pièce")
    }

    private func save() {
        do {
            let savedRoom = try PlantStore(context: context).saveRoom(room, name: name)
            onSave(savedRoom)
            dismiss()
        } catch {
            errorMessage = (error as? PlantStore.StoreError)?.errorDescription
                ?? String(localized: "La pièce n’a pas été enregistrée. Vos saisies sont conservées ; réessayez.")
        }
    }
}
