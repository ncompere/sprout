import Foundation
import SwiftData

@MainActor
struct PlantStore {
    let context: ModelContext
    private let saveChanges: () throws -> Void

    init(context: ModelContext, saveChanges: (() throws -> Void)? = nil) {
        self.context = context
        self.saveChanges = saveChanges ?? { try context.save() }
    }

    enum StoreError: LocalizedError {
        case emptyName, invalidInterval, alreadyWatered

        var errorDescription: String? {
            switch self {
            case .emptyName: "Donnez un nom à votre plante."
            case .invalidInterval: "La fréquence doit être un nombre entier de jours supérieur ou égal à 1."
            case .alreadyWatered: "Cette plante a déjà été arrosée aujourd’hui."
            }
        }
    }

    static func validate(name: String, intervalDays: Int, firstDueDate: Date) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.emptyName
        }
        guard intervalDays >= 1,
              let next = WateringSchedule.calendar.date(byAdding: .day, value: intervalDays, to: firstDueDate),
              next > firstDueDate else {
            throw StoreError.invalidInterval
        }
    }

    @discardableResult
    func savePlant(_ plant: Plant? = nil, name: String, intervalDays: Int, firstDueDate: Date) throws -> Plant {
        try Self.validate(name: name, intervalDays: intervalDays, firstDueDate: firstDueDate)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = WateringSchedule.calendar.startOfDay(for: firstDueDate)
        let savedPlant: Plant
        var restore: () -> Void = { }
        if let plant {
            let previousName = plant.name
            let previousInterval = plant.intervalDays
            let previousDate = plant.firstDueDate
            restore = {
                plant.name = previousName
                plant.intervalDays = previousInterval
                plant.firstDueDate = previousDate
            }
            plant.name = name
            plant.intervalDays = intervalDays
            plant.firstDueDate = date
            savedPlant = plant
        } else {
            savedPlant = Plant(name: name, intervalDays: intervalDays, firstDueDate: date)
            context.insert(savedPlant)
        }
        try commit(restoring: restore)
        return savedPlant
    }

    func water(_ plant: Plant, on date: Date = .now) throws {
        guard !plant.schedule.hasWatered(on: date) else { throw StoreError.alreadyWatered }
        let previousWaterings = plant.waterings
        let watering = Watering(date: date, plant: plant)
        context.insert(watering)
        // Maintain both sides immediately so all views refresh before the next fetch.
        if !plant.waterings.contains(where: { $0.id == watering.id }) {
            plant.waterings.append(watering)
        }
        try commit { plant.waterings = previousWaterings }
    }

    func unwater(_ plant: Plant, on date: Date = .now) throws {
        let calendar = WateringSchedule.calendar
        let previousWaterings = plant.waterings
        let waterings = previousWaterings.filter { calendar.isDate($0.date, inSameDayAs: date) }
        guard !waterings.isEmpty else { return }
        let ids = Set(waterings.map(\.id))
        plant.waterings.removeAll { ids.contains($0.id) }
        for watering in waterings { context.delete(watering) }
        try commit { plant.waterings = previousWaterings }
    }

    func delete(_ plant: Plant) throws {
        context.delete(plant)
        try commit()
    }

    private func commit(restoring restore: () -> Void = { }) throws {
        // Register synchronous property/relationship edits before saving or rolling back.
        context.processPendingChanges()
        do { try saveChanges() }
        catch {
            context.rollback()
            // SwiftData rollback can leave values cached on observed model instances.
            // Restore those instances too, then discard the restoration's dirty flags.
            restore()
            context.processPendingChanges()
            context.rollback()
            throw error
        }
    }
}
