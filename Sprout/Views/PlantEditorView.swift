import SwiftUI
import SwiftData

struct PlantEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var rooms: [Room]
    private let plant: Plant?
    @State private var name: String
    @State private var interval: String
    @State private var firstDueDate: Date
    @State private var errorMessage: String?
    @State private var roomID: UUID?
    @State private var showingRoomCreator = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, interval }

    init(plant: Plant? = nil) {
        self.plant = plant
        _name = State(initialValue: plant?.name ?? "")
        _interval = State(initialValue: String(plant?.intervalDays ?? 7))
        _firstDueDate = State(initialValue: plant?.firstDueDate ?? .now)
        _roomID = State(initialValue: plant?.room?.id)
    }

    private var validInterval: Int? {
        guard let days = Int(interval), days >= 1,
              let next = WateringSchedule.calendar.date(byAdding: .day, value: days, to: firstDueDate),
              next > firstDueDate else { return nil }
        return days
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Votre plante") {
                    TextField("Nom de la plante", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("editor.name")
                }
                Section("Emplacement") {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pièce").font(.subheadline).foregroundStyle(.secondary)
                            Menu {
                                Button("Sans pièce") { roomID = nil }
                                ForEach(sortedRooms) { room in
                                    Button(room.name) { roomID = room.id }
                                }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(rooms.first { $0.id == roomID }?.name ?? String(localized: "Sans pièce"))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                                }
                                .frame(minHeight: 44)
                            }
                            .accessibilityLabel("Pièce")
                            .accessibilityValue(rooms.first { $0.id == roomID }?.name ?? String(localized: "Sans pièce"))
                            .accessibilityIdentifier("editor.room")
                        }
                    } else {
                        Picker("Pièce", selection: $roomID) {
                            Text("Sans pièce").tag(nil as UUID?)
                            ForEach(sortedRooms) { room in
                                Text(room.name).tag(Optional(room.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("editor.room")
                    }
                    Button("Créer une pièce", systemImage: "plus") {
                        focusedField = nil
                        showingRoomCreator = true
                    }
                    .accessibilityIdentifier("editor.createRoom")
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fréquence en jours")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("Nombre de jours", text: $interval)
                            .keyboardType(.numberPad)
                            .frame(minHeight: 44)
                            .focused($focusedField, equals: .interval)
                            .accessibilityLabel("Fréquence en jours")
                            .accessibilityIdentifier("editor.interval")
                    }
                    DatePicker("Premier arrosage", selection: $firstDueDate, displayedComponents: .date)
                        .accessibilityIdentifier("editor.firstDate")
                    if validInterval == nil {
                        Text("Saisissez un nombre entier de jours supérieur ou égal à 1.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Rythme d’arrosage")
                } footer: {
                    if plant?.waterings.isEmpty == false {
                        Text("La prochaine échéance sera calculée depuis le dernier arrosage enregistré.")
                    } else {
                        Text("Après chaque arrosage enregistré, la prochaine date sera calculée selon cette fréquence.")
                    }
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
                    Button("Annuler") { dismiss() }.accessibilityIdentifier("editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validInterval == nil)
                        .accessibilityIdentifier("editor.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { focusedField = nil }
                }
            }
            .saveErrorAlert($errorMessage)
            .sheet(isPresented: $showingRoomCreator) {
                RoomEditorView { roomID = $0.id }
            }
        }
    }

    private var sortedRooms: [Room] {
        rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var editorTitle: Text {
        plant == nil ? Text("Nouvelle plante") : Text("Modifier la plante")
    }

    private func save() {
        guard let days = validInterval else { return }
        do {
            try PlantStore(context: context).savePlant(plant, name: name, intervalDays: days,
                                                     firstDueDate: firstDueDate,
                                                     room: rooms.first { $0.id == roomID })
            dismiss()
        } catch {
            errorMessage = String(localized: "Vos modifications n’ont pas été enregistrées. Vos saisies sont conservées ; réessayez.")
        }
    }
}
