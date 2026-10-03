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

    var body: some View {
        let wateredToday = plant.schedule.hasWatered(on: today)
        let nextDue = plant.schedule.nextDueDate()
        List {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    PlantSymbol()
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
                if plant.schedule.isOverdue(on: today) {
                    Label("En retard", systemImage: "exclamationmark.circle")
                        .foregroundStyle(SproutStyle.warning)
                } else if WateringSchedule.calendar.isDate(nextDue, inSameDayAs: today) {
                    Label("À arroser aujourd’hui", systemImage: "drop.fill")
                        .foregroundStyle(SproutStyle.green)
                }
                Text(nextDue, format: CalendarPresentation.dateStyle(locale: locale).weekday(.wide).day().month(.wide).year())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("plant.nextDue")
                Toggle("Arrosée aujourd’hui", isOn: Binding(
                    get: { plant.schedule.hasWatered(on: today) },
                    set: { setWatering($0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                .accessibilityIdentifier("plant.water")
                .accessibilityValue(wateredToday ? Text("Arrosage effectué") : Text("Arrosage non effectué"))
                .accessibilityHint(wateredToday ? Text("Annuler l’arrosage d’aujourd’hui") : Text("Enregistrer un arrosage aujourd’hui"))
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
        do {
            try PlantStore(context: context).delete(plant)
            dismiss()
        } catch { errorMessage = String(localized: "La plante n’a pas été supprimée. Réessayez.") }
    }
}
