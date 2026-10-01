import SwiftUI
import SwiftData

struct PlantListView: View {
    @Query private var plants: [Plant]
    @State private var showingEditor = false
    let today: Date

    private var sortedPlants: [Plant] {
        plants.sorted {
            let left = $0.schedule.nextDueDate()
            let right = $1.schedule.nextDueDate()
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plants.isEmpty {
                    ContentUnavailableView {
                        Label("Votre jardin commence ici", systemImage: "leaf")
                    } description: {
                        Text("Ajoutez votre première plante et choisissez son rythme d’arrosage.")
                    } actions: {
                        Button("Ajouter une plante") { showingEditor = true }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("plants.empty.add")
                    }
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Un peu d’attention, beaucoup de vie.")
                                    .font(.title3.weight(.semibold))
                                let dueCount = plants.filter {
                                    $0.schedule.nextDueDate() <= WateringSchedule.calendar.startOfDay(for: today)
                                }.count
                                Text(dueCount == 0 ? "Vos plantes sont à jour." : "\(dueCount) plante\(dueCount > 1 ? "s" : "") à arroser.")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                        let overdue = sortedPlants.filter { $0.schedule.isOverdue(on: today) }
                        let remaining = sortedPlants.filter { !$0.schedule.isOverdue(on: today) }
                        if !overdue.isEmpty {
                            Section("En retard") { plantRows(overdue) }
                        }
                        if !remaining.isEmpty {
                            Section("Votre jardin") { plantRows(remaining) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(SproutStyle.background)
            .navigationTitle("Mes plantes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajouter une plante", systemImage: "plus") { showingEditor = true }
                        .accessibilityIdentifier("plants.add")
                }
            }
            .sheet(isPresented: $showingEditor) { PlantEditorView() }
        }
    }

    @ViewBuilder
    private func plantRows(_ plants: [Plant]) -> some View {
        ForEach(plants) { plant in
            NavigationLink {
                PlantDetailView(plant: plant, today: today)
            } label: {
                PlantRow(plant: plant, today: today)
            }
        }
    }
}
