import Foundation
import SwiftData

@MainActor
struct PlantStore {
    static let didCommit = Notification.Name("Sprout.gardenDidCommit")
    let context: ModelContext
    private let saveChanges: () throws -> Void

    init(context: ModelContext, saveChanges: (() throws -> Void)? = nil) {
        self.context = context
        self.saveChanges = saveChanges ?? { try context.save() }
    }

    enum StoreError: LocalizedError {
        case emptyName, invalidInterval, alreadyWatered, emptyRoomName, duplicateRoomName

        var errorDescription: String? {
            switch self {
            case .emptyName: String(localized: "Donnez un nom à votre plante.")
            case .invalidInterval: String(localized: "La fréquence doit être un nombre entier de jours supérieur ou égal à 1.")
            case .alreadyWatered: String(localized: "Cette plante a déjà été arrosée aujourd’hui.")
            case .emptyRoomName: String(localized: "Donnez un nom à votre pièce.")
            case .duplicateRoomName: String(localized: "Une pièce porte déjà ce nom.")
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
    func savePlant(_ plant: Plant? = nil, name: String, intervalDays: Int, firstDueDate: Date,
                   room: Room?, photoData: Data?, remindersIncluded: Bool? = nil) throws -> Plant {
        try Self.validate(name: name, intervalDays: intervalDays, firstDueDate: firstDueDate)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = WateringSchedule.calendar.startOfDay(for: firstDueDate)
        let savedPlant: Plant
        let previousRoom = plant?.room
        let affectedRooms = [previousRoom, room].compactMap { $0 }
        let previousMembers = affectedRooms.map { ($0, $0.plants) }
        var restore: () -> Void = { previousMembers.forEach { $0.0.plants = $0.1 } }
        if let plant {
            let previousName = plant.name
            let previousInterval = plant.intervalDays
            let previousDate = plant.firstDueDate
            let previousPhoto = plant.photoData
            let previousReminders = plant.remindersIncluded
            restore = {
                plant.name = previousName
                plant.intervalDays = previousInterval
                plant.firstDueDate = previousDate
                plant.photoData = previousPhoto
                plant.remindersIncluded = previousReminders
                plant.room = previousRoom
                previousMembers.forEach { $0.0.plants = $0.1 }
            }
            plant.name = name
            plant.intervalDays = intervalDays
            plant.firstDueDate = date
            savedPlant = plant
        } else {
            savedPlant = Plant(name: name, intervalDays: intervalDays, firstDueDate: date)
            context.insert(savedPlant)
        }
        savedPlant.photoData = photoData
        if let remindersIncluded { savedPlant.remindersIncluded = remindersIncluded }
        setRoom(room, for: savedPlant)
        try commit(restoring: restore)
        return savedPlant
    }

    // Existing callers retain the photo unless they explicitly supply a replacement or nil.
    @discardableResult
    func savePlant(_ plant: Plant? = nil, name: String, intervalDays: Int, firstDueDate: Date,
                   room: Room?) throws -> Plant {
        try savePlant(plant, name: name, intervalDays: intervalDays, firstDueDate: firstDueDate,
                      room: room, photoData: plant?.photoData)
    }

    // Existing callers editing the watering schedule retain the plant's assignment and photo.
    @discardableResult
    func savePlant(_ plant: Plant? = nil, name: String, intervalDays: Int, firstDueDate: Date) throws -> Plant {
        try savePlant(plant, name: name, intervalDays: intervalDays, firstDueDate: firstDueDate, room: plant?.room)
    }

    @discardableResult
    func saveRoom(_ room: Room? = nil, name: String) throws -> Room {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.emptyRoomName }
        let rooms = try context.fetch(FetchDescriptor<Room>())
        guard !rooms.contains(where: {
            $0.id != room?.id && $0.name.compare(name, options: .caseInsensitive,
                                               locale: Locale(identifier: "fr_FR")) == .orderedSame
        }) else { throw StoreError.duplicateRoomName }
        let savedRoom: Room
        var restore: () -> Void = { }
        if let room {
            let previousName = room.name
            restore = { room.name = previousName }
            room.name = name
            savedRoom = room
        } else {
            savedRoom = Room(name: name)
            context.insert(savedRoom)
        }
        try commit(restoring: restore)
        return savedRoom
    }

    func deleteRoom(_ room: Room) throws {
        let previousPlants = room.plants
        for plant in previousPlants { setRoom(nil, for: plant) }
        context.delete(room)
        try commit {
            room.plants = previousPlants
            for plant in previousPlants { plant.room = room }
        }
    }

    private func setRoom(_ room: Room?, for plant: Plant) {
        if plant.room?.id != room?.id {
            plant.room?.plants.removeAll { $0.id == plant.id }
            plant.room = room
        }
        if let room, !room.plants.contains(where: { $0.id == plant.id }) {
            room.plants.append(plant)
        }
    }

    func water(_ plant: Plant, on date: Date = .now) throws {
        guard !plant.schedule.hasWatered(on: date) else { throw StoreError.alreadyWatered }
        let previousWaterings = plant.waterings
        let watering = Watering(date: date, plant: plant)
        context.insert(watering)
        // Assign explicitly even if SwiftData already updated the inverse: inverse updates
        // alone do not consistently notify views observing the plant on older iOS versions.
        plant.waterings = previousWaterings + [watering]
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
        let previousPhoto = plant.photoData
        let previousRoom = plant.room
        let previousMembers = previousRoom?.plants ?? []
        let previousWaterings = plant.waterings
        context.delete(plant)
        try commit {
            plant.photoData = previousPhoto
            plant.room = previousRoom
            previousRoom?.plants = previousMembers
            for watering in previousWaterings where watering.plant?.id != plant.id {
                watering.plant = plant
            }
            plant.waterings = previousWaterings
        }
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
        NotificationCenter.default.post(name: Self.didCommit, object: context)
    }
}
