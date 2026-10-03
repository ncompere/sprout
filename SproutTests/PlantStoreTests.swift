import XCTest
import SwiftData
@testable import Sprout

final class PlantStoreTests: XCTestCase {
    @MainActor
    private func container(inMemory: Bool = true, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Plant.self, Watering.self, Room.self])
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        let container = try ModelContainer(for: schema, configurations: [config])
        container.mainContext.autosaveEnabled = false
        return container
    }

    @MainActor
    func testAddEditAndDeletePlant() async throws {
        let container = try container()
        let context = container.mainContext
        let store = PlantStore(context: context)
        let plant = try store.savePlant(name: "  Monstera  ", intervalDays: 7, firstDueDate: .now)
        XCTAssertEqual(plant.name, "Monstera")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plant>()), 1)
        let id = plant.id
        try store.savePlant(plant, name: "Monstera du salon", intervalDays: 3, firstDueDate: .now)
        XCTAssertEqual(plant.id, id)
        XCTAssertEqual(plant.intervalDays, 3)
        XCTAssertEqual(plant.name, "Monstera du salon")
        try store.delete(plant)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plant>()), 0)
    }

    @MainActor
    func testValidationDoesNotInsertInvalidPlant() async throws {
        let container = try container()
        let store = PlantStore(context: container.mainContext)
        XCTAssertThrowsError(try store.savePlant(name: " \n ", intervalDays: 7, firstDueDate: .now))
        XCTAssertThrowsError(try store.savePlant(name: "Ficus", intervalDays: 0, firstDueDate: .now))
        XCTAssertThrowsError(try store.savePlant(name: "Ficus", intervalDays: -2, firstDueDate: .now))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Plant>()), 0)
    }

    @MainActor
    func testWateringClearsRetardAndRejectsSameDayDuplicate() async throws {
        let container = try container()
        let store = PlantStore(context: container.mainContext)
        let calendar = WateringSchedule.calendar
        let now = Date.now
        let past = calendar.date(byAdding: .day, value: -10, to: now)!
        let plant = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: past)
        XCTAssertTrue(plant.schedule.isOverdue(on: now))
        try store.water(plant, on: now)
        XCTAssertFalse(plant.schedule.isOverdue(on: now))
        XCTAssertEqual(plant.waterings.count, 1)
        XCTAssertEqual(plant.schedule.nextDueDate(), calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)))
        XCTAssertThrowsError(try store.water(plant, on: calendar.startOfDay(for: now)))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Watering>()), 1)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        try store.water(plant, on: tomorrow)
        XCTAssertEqual(plant.waterings.count, 2)
    }

    @MainActor
    func testDeletingPlantCascadesWaterings() async throws {
        let container = try container()
        let store = PlantStore(context: container.mainContext)
        let plant = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: .now)
        try store.water(plant)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Watering>()), 1)
        try store.delete(plant)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Watering>()), 0)
    }

    @MainActor
    func testTwoPlantsCanShareAnArrosageDate() async throws {
        let container = try container()
        let store = PlantStore(context: container.mainContext)
        let first = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: .now)
        let second = try store.savePlant(name: "Monstera", intervalDays: 7, firstDueDate: .now)
        try store.water(first)
        try store.water(second)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Watering>()), 2)
        XCTAssertEqual(first.schedule.nextDueDate(), second.schedule.nextDueDate())
    }

    @MainActor
    func testUndoFirstWateringRestoresInitialDateAndAllowsWateringAgain() async throws {
        let container = try container()
        let context = container.mainContext
        let store = PlantStore(context: context)
        let now = Date.now
        let plant = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: now)
        let due = plant.schedule.nextDueDate()
        let earlierToday = WateringSchedule.calendar.startOfDay(for: now)
        try store.water(plant, on: earlierToday)
        try store.unwater(plant, on: now)
        XCTAssertFalse(plant.schedule.hasWatered(on: now))
        XCTAssertEqual(plant.schedule.nextDueDate(), due)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 0)
        // Unchecking an already unchecked day is harmless.
        try store.unwater(plant, on: now)
        try store.water(plant, on: now)
        XCTAssertEqual(plant.waterings.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 1)
    }

    @MainActor
    func testUndoKeepsOlderWateringsAndOtherPlants() async throws {
        let container = try container()
        let context = container.mainContext
        let store = PlantStore(context: context)
        let now = Date.now
        let calendar = WateringSchedule.calendar
        let oldDate = calendar.date(byAdding: .day, value: -8, to: now)!
        let plant = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: oldDate)
        let other = try store.savePlant(name: "Monstera", intervalDays: 7, firstDueDate: now)
        try store.water(plant, on: oldDate)
        let oldWateringID = try XCTUnwrap(plant.waterings.first?.id)
        let due = plant.schedule.nextDueDate()
        try store.water(plant, on: now)
        try store.water(other, on: now)
        try store.unwater(plant, on: now)
        XCTAssertEqual(plant.waterings.map(\.id), [oldWateringID])
        XCTAssertEqual(plant.schedule.nextDueDate(), due)
        XCTAssertTrue(plant.schedule.isOverdue(on: now))
        XCTAssertTrue(other.schedule.hasWatered(on: now))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 2)
    }

    @MainActor
    func testFailedUndoRestoresWateringAndDeadline() async throws {
        struct SimulatedFailure: Error { }
        let container = try container()
        let context = container.mainContext
        let working = PlantStore(context: context)
        let failing = PlantStore(context: context, saveChanges: { throw SimulatedFailure() })
        let now = Date.now
        let plant = try working.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: now)
        try working.water(plant, on: now)
        let wateringID = try XCTUnwrap(plant.waterings.first?.id)
        let due = plant.schedule.nextDueDate()
        XCTAssertThrowsError(try failing.unwater(plant, on: now))
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID])
        XCTAssertEqual(plant.waterings.first?.plant?.id, plant.id)
        XCTAssertTrue(plant.schedule.hasWatered(on: now))
        XCTAssertEqual(plant.schedule.nextDueDate(), due)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 1)
        XCTAssertFalse(context.hasChanges)
        try working.savePlant(name: "Autre plante", intervalDays: 3, firstDueDate: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 1)
        try working.unwater(plant, on: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 0)
    }

    @MainActor
    func testDiskPersistenceAcrossContainers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("plants.store")
        let now = Date.now
        var id: UUID!
        do {
            let first = try container(inMemory: false, url: url)
            let store = PlantStore(context: first.mainContext)
            let plant = try store.savePlant(name: "Monstera", intervalDays: 5, firstDueDate: now)
            id = plant.id
            try store.water(plant, on: now)
        }
        let reopened = try container(inMemory: false, url: url)
        let plants = try reopened.mainContext.fetch(FetchDescriptor<Plant>())
        XCTAssertEqual(plants.count, 1)
        let plant = try XCTUnwrap(plants.first)
        XCTAssertEqual(plant.id, id)
        XCTAssertEqual(plant.name, "Monstera")
        XCTAssertEqual(plant.intervalDays, 5)
        XCTAssertEqual(plant.waterings.count, 1)
        XCTAssertEqual(plant.waterings.first?.date, now)
        XCTAssertEqual(plant.waterings.first?.plant?.id, id)
        try PlantStore(context: reopened.mainContext).unwater(plant, on: now)
        let afterUndo = try container(inMemory: false, url: url)
        let restored = try XCTUnwrap(afterUndo.mainContext.fetch(FetchDescriptor<Plant>()).first)
        XCTAssertTrue(restored.waterings.isEmpty)
        XCTAssertFalse(restored.schedule.hasWatered(on: now))
        XCTAssertEqual(restored.schedule.nextDueDate(), WateringSchedule.calendar.startOfDay(for: now))
        XCTAssertEqual(try afterUndo.mainContext.fetchCount(FetchDescriptor<Watering>()), 0)
    }

    @MainActor
    func testFailedSaveRollsBackAddEditAndWatering() async throws {
        struct SimulatedFailure: Error { }
        let container = try container()
        let context = container.mainContext
        let working = PlantStore(context: context)
        let failing = PlantStore(context: context, saveChanges: { throw SimulatedFailure() })
        let plant = try working.savePlant(name: "Monstera", intervalDays: 7, firstDueDate: .now)
        let due = plant.schedule.nextDueDate()

        XCTAssertThrowsError(try failing.savePlant(name: "Ficus", intervalDays: 3, firstDueDate: .now))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plant>()), 1)
        XCTAssertThrowsError(try failing.savePlant(plant, name: "Nouveau nom", intervalDays: 2, firstDueDate: .now))
        XCTAssertEqual(plant.name, "Monstera")
        XCTAssertEqual(plant.intervalDays, 7)
        XCTAssertThrowsError(try failing.water(plant))
        XCTAssertTrue(plant.waterings.isEmpty)
        XCTAssertEqual(plant.schedule.nextDueDate(), due)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Watering>()), 0)
        XCTAssertThrowsError(try failing.delete(plant))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plant>()), 1)
        XCTAssertFalse(context.hasChanges)
        // A subsequent successful save must not accidentally commit a failed mutation.
        try working.savePlant(name: "Autre plante", intervalDays: 5, firstDueDate: .now)
        XCTAssertEqual(plant.name, "Monstera")
        XCTAssertTrue(plant.waterings.isEmpty)
    }
}
