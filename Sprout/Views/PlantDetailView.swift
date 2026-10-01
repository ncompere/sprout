import SwiftUI
import SwiftData

struct PlantDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let plant: Plant
    let today: Date
    @State private var showingEditor = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    PlantSymbol()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plant.name).font(.title2.weight(.semibold))
                        Text(plant.intervalDays == 1 ? "Chaque jour" : "Tous les \(plant.intervalDays) jours")
                            .foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
            }
            Section("Prochain arrosage") {
                DueLabel(plant: plant, today: today)
                Text(plant.schedule.nextDueDate(), format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("plant.nextDue")
                Button(action: water) {
                    Label(plant.schedule.hasWatered(on: today) ? "Arrosée aujourd’hui" : "Arrosée", systemImage: "checkmark.drop")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(plant.schedule.hasWatered(on: today))
                .accessibilityIdentifier("plant.water")
            }
            if let last = plant.waterings.map(\.date).max() {
                Section("Dernier arrosage") {
                    Label(last.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR"))), systemImage: "checkmark.circle")
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
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("La plante et ses arrosages enregistrés seront supprimés.")
        }
        .saveErrorAlert($errorMessage)
    }

    private func water() {
        do { try PlantStore(context: context).water(plant) }
        catch { errorMessage = (error as? PlantStore.StoreError)?.errorDescription ?? "L’arrosage n’a pas été enregistré. Réessayez." }
    }

    private func delete() {
        do {
            try PlantStore(context: context).delete(plant)
            dismiss()
        } catch { errorMessage = "La plante n’a pas été supprimée. Réessayez." }
    }
}
