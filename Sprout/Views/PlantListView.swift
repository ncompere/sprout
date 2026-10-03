import SwiftUI
import SwiftData

struct PlantListView: View {
    @Environment(\.locale) private var locale
    @Query private var plants: [Plant]
    @Query private var rooms: [Room]
    @AppStorage("plants.grouping") private var grouping = "rooms"
    @State private var showingEditor = false
    @State private var showingRooms = false
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
            VStack(spacing: 0) {
                Picker("Organisation des plantes", selection: $grouping) {
                    Text("Par pièces").tag("rooms")
                    Text("Par arrosage").tag("watering")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier("plants.grouping")

                if plants.isEmpty && (rooms.isEmpty || grouping == "watering") {
                    emptyGarden
                } else {
                    List {
                        Section {
                            if plants.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Ajoutez votre première plante dans l’une de vos pièces.")
                                        .foregroundStyle(.secondary)
                                    Button("Ajouter une plante") { showingEditor = true }
                                        .accessibilityIdentifier("plants.empty.add")
                                }
                            } else {
                                gardenSummary
                            }
                        }
                        if grouping == "rooms" {
                            ForEach(rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { room in
                                Section {
                                    let members = sortedPlants.filter { $0.room?.id == room.id }
                                    if members.isEmpty {
                                        Text("Aucune plante").foregroundStyle(.secondary)
                                    } else {
                                        plantRows(members)
                                    }
                                } header: {
                                    Text(room.name)
                                        .textCase(nil)
                                        .accessibilityLabel(room.name)
                                        .accessibilityIdentifier("plants.room.\(room.id)")
                                }
                            }
                            let unassigned = sortedPlants.filter { $0.room == nil }
                            if !unassigned.isEmpty {
                                Section("Sans pièce") { plantRows(unassigned) }.textCase(nil)
                            }
                        } else {
                            let overdue = sortedPlants.filter { $0.schedule.isOverdue(on: today) }
                            let remaining = sortedPlants.filter { !$0.schedule.isOverdue(on: today) }
                            if !overdue.isEmpty {
                                Section("En retard") { plantRows(overdue, showsRoom: true) }
                            }
                            if !remaining.isEmpty {
                                Section("Votre jardin") { plantRows(remaining, showsRoom: true) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(SproutStyle.background)
            .navigationTitle("Mes plantes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gérer les pièces", systemImage: "door.left.hand.open") { showingRooms = true }
                        .accessibilityIdentifier("plants.rooms")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajouter une plante", systemImage: "plus") { showingEditor = true }
                        .accessibilityIdentifier("plants.add")
                }
            }
            .sheet(isPresented: $showingEditor) { PlantEditorView() }
            .sheet(isPresented: $showingRooms) { RoomManagerView() }
        }
    }

    private var emptyGarden: some View {
        ContentUnavailableView {
            Label("Votre jardin commence ici", systemImage: "leaf")
        } description: {
            Text("Ajoutez votre première plante et choisissez son rythme d’arrosage.")
        } actions: {
            Button("Ajouter une plante") { showingEditor = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("plants.empty.add")
        }
    }

    private var gardenSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Un peu d’attention, beaucoup de vie.")
                .font(.title3.weight(.semibold))
            let dueCount = plants.filter {
                $0.schedule.nextDueDate() <= WateringSchedule.calendar.startOfDay(for: today)
            }.count
            Text(LocalizedCopy.duePlants(dueCount, locale: locale))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func plantRows(_ plants: [Plant], showsRoom: Bool = false) -> some View {
        ForEach(plants) { plant in
            NavigationLink {
                PlantDetailView(plant: plant, today: today)
            } label: {
                PlantRow(plant: plant, today: today, showsRoom: showsRoom)
            }
        }
    }
}
