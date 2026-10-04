import SwiftUI
import SwiftData

struct PlantDetailView: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let plant: Plant
    let today: Date
    @State private var showingEditor = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    @State private var isDeleted = false

    var body: some View {
        // Read schedule values directly in body so SwiftUI tracks watering updates.
        let wateredToday = isDeleted ? false : plant.schedule.hasWatered(on: today)
        let nextDue = isDeleted ? today : plant.schedule.nextDueDate()
        if !isDeleted {
            List {
                Section {
                    if let data = plant.photoData {
                        PlantPhotoView(data: data)
                            .accessibilityLabel("Photo de \(plant.name)")
                            .accessibilityIdentifier("plant.photo")
                    }
                    HStack(alignment: .center, spacing: 16) {
                        if plant.photoData == nil { PlantSymbol() }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(plant.name).font(.title2.weight(.semibold))
                            Label(plant.roomName, systemImage: "door.left.hand.open")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .accessibilityIdentifier("plant.room")
                            Text(LocalizedCopy.wateringInterval(plant.intervalDays, locale: locale))
                                .foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 12)
                }
                Section("Prochain arrosage") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(nextDue, format: CalendarPresentation.dateStyle(locale: locale).weekday(.wide).day().month(.wide).year())
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("plant.nextDue")
                        Group {
                            if plant.schedule.isOverdue(on: today) {
                                Label("En retard", systemImage: "exclamationmark.circle")
                                    .foregroundStyle(SproutStyle.warning)
                            } else if WateringSchedule.calendar.isDate(nextDue, inSameDayAs: today) {
                                Label("À arroser aujourd’hui", systemImage: "drop.fill")
                                    .foregroundStyle(SproutStyle.green)
                            } else {
                                Label("Arrosage prévu", systemImage: "drop")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plant.wateringStatus")
                        Divider()
                        Toggle("Arrosée aujourd’hui", isOn: Binding(
                            get: { plant.schedule.hasWatered(on: today) },
                            set: { setWatering($0) }
                        ))
                        .toggleStyle(CheckboxToggleStyle())
                        .accessibilityIdentifier("plant.water")
                        .accessibilityValue(wateredToday ? Text("Arrosage effectué") : Text("Arrosage non effectué"))
                        .accessibilityHint(wateredToday ? Text("Annuler l’arrosage d’aujourd’hui") : Text("Enregistrer un arrosage aujourd’hui"))
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .contain)
                }
                if let last = plant.waterings.map(\.date).max() {
                    Section("Dernier arrosage") {
                        Label(last.formatted(CalendarPresentation.dateStyle(locale: locale).day().month(.wide).year()), systemImage: "checkmark.circle")
                    }
                }
                Section {
                    Button("Supprimer la plante", role: .destructive) { confirmingDelete = true }
                        .accessibilityIdentifier("plant.delete")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(plant.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier") { showingEditor = true }
                        .accessibilityIdentifier("plant.edit")
                }
            }
            .sheet(isPresented: $showingEditor) { PlantEditorView(plant: plant) }
            .confirmationDialog("Supprimer \(plant.name) ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive, action: delete)
                    .accessibilityIdentifier("plant.confirmDelete")
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("La plante et ses arrosages enregistrés seront supprimés.")
            }
            .saveErrorAlert($errorMessage)
        }
    }

    private func setWatering(_ isWatered: Bool) {
        let now = Date.now
        guard plant.schedule.hasWatered(on: now) != isWatered else { return }
        do {
            let store = PlantStore(context: context)
            if isWatered { try store.water(plant, on: now) }
            else { try store.unwater(plant, on: now) }
        } catch {
            errorMessage = (error as? PlantStore.StoreError)?.errorDescription
                ?? (isWatered ? String(localized: "L’arrosage n’a pas été enregistré. Réessayez.")
                    : String(localized: "L’arrosage n’a pas été annulé. Réessayez."))
        }
    }

    private func delete() {
        // Stop observing model properties before SwiftData invalidates the deleted instance.
        isDeleted = true
        do {
            try PlantStore(context: context).delete(plant)
            dismiss()
        } catch {
            isDeleted = false
            errorMessage = String(localized: "La plante n’a pas été supprimée. Réessayez.")
        }
    }
}
