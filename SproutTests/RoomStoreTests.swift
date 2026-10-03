import XCTest
import SwiftData
@testable import Sprout

final class RoomStoreTests: XCTestCase {
    @MainActor
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Plant.self, Watering.self, Room.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        return container
    }

    @MainActor
    func testRoomNamesAreTrimmedAndUniqueIgnoringCase() throws {
        let container = try container()
        let store = PlantStore(context: container.mainContext)
        let room = try store.saveRoom(name: "  Salon \n")
        XCTAssertEqual(room.name, "Salon")
        let id = room.id
        XCTAssertThrowsError(try store.saveRoom(name: "\n "))
        XCTAssertThrowsError(try store.saveRoom(name: " SALON "))
        try store.saveRoom(room, name: "salon")
        XCTAssertEqual(room.id, id)
        let other = try store.saveRoom(name: "Chambre")
        XCTAssertThrowsError(try store.saveRoom(room, name: "chambre"))
        XCTAssertEqual(room.name, "salon")
        XCTAssertEqual(other.name, "Chambre")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Room>()), 2)
        XCTAssertFalse(container.mainContext.hasChanges)
    }

    @MainActor
    func testAssignMoveAndUnassignKeepBothSidesAndSchedule() throws {
        let container = try container()
        let store = PlantStore(context: container.mainContext)
        let first = try store.saveRoom(name: "Salon")
        let second = try store.saveRoom(name: "Bureau")
        let plant = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: .now, room: first)
        try store.water(plant)
        let due = plant.schedule.nextDueDate()
        let wateringID = try XCTUnwrap(plant.waterings.first?.id)
        XCTAssertEqual(first.plants.map(\.id), [plant.id])
        try store.savePlant(plant, name: plant.name, intervalDays: 7, firstDueDate: plant.firstDueDate, room: second)
        XCTAssertTrue(first.plants.isEmpty)
        XCTAssertEqual(second.plants.map(\.id), [plant.id])
        XCTAssertEqual(plant.room?.id, second.id)
        try store.saveRoom(second, name: "Atelier")
        XCTAssertEqual(plant.roomName, "Atelier")
        try store.savePlant(plant, name: plant.name, intervalDays: 7, firstDueDate: plant.firstDueDate)
        XCTAssertEqual(plant.room?.id, second.id)
        try store.savePlant(plant, name: plant.name, intervalDays: 7, firstDueDate: plant.firstDueDate, room: nil)
        XCTAssertNil(plant.room)
        XCTAssertEqual(plant.roomName, String(localized: "Sans pièce"))
        XCTAssertTrue(second.plants.isEmpty)
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID])
        XCTAssertEqual(plant.schedule.nextDueDate(), due)
    }

    @MainActor
    func testDeleteOccupiedRoomPreservesPlantsAndWaterings() throws {
        let container = try container()
        let context = container.mainContext
        let store = PlantStore(context: context)
        let room = try store.saveRoom(name: "Salon")
        let otherRoom = try store.saveRoom(name: "Bureau")
        let first = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: .now, room: room)
        let second = try store.savePlant(name: "Monstera", intervalDays: 3, firstDueDate: .now, room: room)
        let other = try store.savePlant(name: "Aloe", intervalDays: 10, firstDueDate: .now, room: otherRoom)
        try store.water(first)
        let wateringID = try XCTUnwrap(first.waterings.first?.id)
        let due = first.schedule.nextDueDate()
        try store.deleteRoom(room)
        XCTAssertNil(first.room)
        XCTAssertNil(second.room)
        XCTAssertEqual(other.room?.id, otherRoom.id)
        XCTAssertEqual(first.waterings.map(\.id), [wateringID])
        XCTAssertEqual(first.schedule.nextDueDate(), due)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plant>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Room>()), 1)
        try store.delete(other)
        XCTAssertTrue(otherRoom.plants.isEmpty)
        try store.deleteRoom(otherRoom)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Room>()), 0)
    }

    @MainActor
    func testFailedRoomMutationsRestoreObservedModelsAndMemberships() throws {
        struct SimulatedFailure: Error { }
        let container = try container()
        let context = container.mainContext
        let working = PlantStore(context: context)
        let failing = PlantStore(context: context, saveChanges: { throw SimulatedFailure() })
        let first = try working.saveRoom(name: "Salon")
        let second = try working.saveRoom(name: "Bureau")
        let plant = try working.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: .now, room: first)
        try working.water(plant)
        let wateringID = try XCTUnwrap(plant.waterings.first?.id)
        XCTAssertThrowsError(try failing.saveRoom(name: "Chambre"))
        XCTAssertThrowsError(try failing.saveRoom(first, name: "Nouveau salon"))
        XCTAssertEqual(first.name, "Salon")
        XCTAssertThrowsError(try failing.savePlant(name: "Aloe", intervalDays: 3, firstDueDate: .now, room: first))
        XCTAssertEqual(first.plants.map(\.id), [plant.id])
        XCTAssertThrowsError(try failing.savePlant(plant, name: "Modifié", intervalDays: 3,
                                                 firstDueDate: .now, room: second))
        XCTAssertEqual(plant.name, "Ficus")
        XCTAssertEqual(plant.intervalDays, 7)
        XCTAssertEqual(plant.room?.id, first.id)
        XCTAssertEqual(first.plants.map(\.id), [plant.id])
        XCTAssertTrue(second.plants.isEmpty)
        XCTAssertThrowsError(try failing.savePlant(plant, name: plant.name, intervalDays: 7,
                                                 firstDueDate: plant.firstDueDate, room: nil))
        XCTAssertEqual(plant.room?.id, first.id)
        XCTAssertThrowsError(try failing.deleteRoom(first))
        XCTAssertEqual(first.plants.map(\.id), [plant.id])
        XCTAssertEqual(plant.room?.id, first.id)
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID])
        XCTAssertThrowsError(try failing.delete(plant))
        XCTAssertEqual(plant.room?.id, first.id)
        XCTAssertEqual(first.plants.map(\.id), [plant.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Room>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plant>()), 1)
        XCTAssertFalse(context.hasChanges)
        try working.saveRoom(name: "Cuisine")
        XCTAssertEqual(first.name, "Salon")
        XCTAssertEqual(plant.room?.id, first.id)
        XCTAssertEqual(first.plants.map(\.id), [plant.id])
        try working.deleteRoom(first)
        XCTAssertNil(plant.room)
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID])
    }

    @MainActor
    func testRoomMembershipAndDeletionPersistOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rooms.store")
        var roomID: UUID!
        var plantID: UUID!
        var wateringID: UUID!
        do {
            let initial = try container(url: url)
            let store = PlantStore(context: initial.mainContext)
            let room = try store.saveRoom(name: "Salon")
            let plant = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: .now, room: room)
            try store.water(plant)
            roomID = room.id
            plantID = plant.id
            wateringID = plant.waterings.first?.id
        }
        do {
            let reopened = try container(url: url)
            let context = reopened.mainContext
            let room = try XCTUnwrap(context.fetch(FetchDescriptor<Room>()).first)
            let plant = try XCTUnwrap(context.fetch(FetchDescriptor<Plant>()).first)
            XCTAssertEqual(room.id, roomID)
            XCTAssertEqual(room.plants.map(\.id), [plantID!])
            XCTAssertEqual(plant.room?.id, roomID)
            let store = PlantStore(context: context)
            try store.saveRoom(room, name: "Séjour")
            XCTAssertEqual(plant.roomName, "Séjour")
            try store.deleteRoom(room)
        }
        let final = try container(url: url)
        let plant = try XCTUnwrap(final.mainContext.fetch(FetchDescriptor<Plant>()).first)
        XCTAssertEqual(plant.id, plantID)
        XCTAssertNil(plant.room)
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID!])
        XCTAssertEqual(try final.mainContext.fetchCount(FetchDescriptor<Room>()), 0)
    }

    @MainActor
    func testLegacyStoreMigratesWithoutLosingPlantsOrWaterings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        let now = Date.now
        var plantID: UUID!
        var wateringID: UUID!
        do {
            let schema = Schema([LegacyGarden.Plant.self, LegacyGarden.Watering.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            legacy.mainContext.autosaveEnabled = false
            let plant = LegacyGarden.Plant(name: "Monstera", intervalDays: 5, firstDueDate: now, createdAt: now)
            let watering = LegacyGarden.Watering(date: now, plant: plant)
            legacy.mainContext.insert(plant)
            legacy.mainContext.insert(watering)
            plant.waterings = [watering]
            plantID = plant.id
            wateringID = watering.id
            try legacy.mainContext.save()
        }
        let migrated = try container(url: url)
        let context = migrated.mainContext
        let plant = try XCTUnwrap(context.fetch(FetchDescriptor<Plant>()).first)
        XCTAssertEqual(plant.id, plantID)
        XCTAssertEqual(plant.name, "Monstera")
        XCTAssertEqual(plant.intervalDays, 5)
        XCTAssertEqual(plant.firstDueDate, now)
        XCTAssertEqual(plant.createdAt, now)
        XCTAssertNil(plant.room)
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID!])
        XCTAssertEqual(plant.waterings.first?.date, now)
        XCTAssertEqual(plant.waterings.first?.plant?.id, plantID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Room>()), 0)
        let store = PlantStore(context: context)
        let room = try store.saveRoom(name: "Salon")
        try store.savePlant(plant, name: plant.name, intervalDays: plant.intervalDays,
                            firstDueDate: plant.firstDueDate, room: room)
        let reopened = try container(url: url)
        let restored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Plant>()).first)
        XCTAssertEqual(restored.room?.name, "Salon")
        XCTAssertEqual(restored.waterings.map(\.id), [wateringID!])
    }
}

// Frozen pre-room schema, used to exercise automatic migration of an existing disk store.
private enum LegacyGarden {
    @Model
    final class Plant {
        @Attribute(.unique) var id: UUID
        var name: String
        var intervalDays: Int
        var firstDueDate: Date
        var createdAt: Date
        @Relationship(deleteRule: .cascade, inverse: \Watering.plant)
        var waterings: [Watering] = []

        init(name: String, intervalDays: Int, firstDueDate: Date, createdAt: Date) {
            self.id = UUID()
            self.name = name
            self.intervalDays = intervalDays
            self.firstDueDate = firstDueDate
            self.createdAt = createdAt
        }
    }

    @Model
    final class Watering {
        @Attribute(.unique) var id: UUID
        var date: Date
        var plant: Plant?

        init(date: Date, plant: Plant) {
            self.id = UUID()
            self.date = date
            self.plant = plant
        }
    }
}
