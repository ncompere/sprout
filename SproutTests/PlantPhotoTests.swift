import XCTest
import SwiftData
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import Sprout

final class PlantPhotoTests: XCTestCase {
    private func image(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.red.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            renderer.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
    }

    func testLibraryPhotoIsResizedToJPEGWithoutMetadata() throws {
        let original = image(size: CGSize(width: 2400, height: 1200))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(original.cgImage), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.0, kCGImagePropertyGPSLatitudeRef: "N"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let data = try PlantPhotoProcessor.jpegData(from: encoded as Data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let result = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(result.size, CGSize(width: 800, height: 1600))
        XCTAssertEqual(result.imageOrientation, .up)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    func testSmallPhotosAreNotUpscaledAndInvalidDataFails() throws {
        let original = image(size: CGSize(width: 120, height: 80))
        let data = try PlantPhotoProcessor.jpegData(from: XCTUnwrap(original.pngData()))
        let result = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(result.size, original.size)
        XCTAssertThrowsError(try PlantPhotoProcessor.jpegData(from: Data("invalid image".utf8)))
    }

    func testCameraPhotoOrientationIsNormalizedAndSizeIsBounded() throws {
        let original = image(size: CGSize(width: 2400, height: 1200))
        let rotated = UIImage(cgImage: try XCTUnwrap(original.cgImage), scale: 1, orientation: .right)
        let data = try PlantPhotoProcessor.jpegData(from: rotated)
        let result = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(result.imageOrientation, .up)
        XCTAssertEqual(result.size, CGSize(width: 800, height: 1600))
        // The red left half of the source becomes the top half after a clockwise rotation.
        let cgImage = try XCTUnwrap(result.cgImage)
        let sample = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 100, y: 100, width: 1, height: 1)))
        let pixel = try XCTUnwrap(sample.dataProvider?.data) as Data
        XCTAssertGreaterThan(pixel[0], pixel[2])
    }

    @MainActor
    func testDraftPreservesPhotoOnFailureAndIgnoresObsoleteImports() async throws {
        enum Failure: Error { case simulated }
        let old = Data([1]), new = Data([2])
        let draft = PlantPhotoDraft(photoData: old)
        let failure = draft.load { throw Failure.simulated }
        XCTAssertTrue(draft.isLoading)
        await failure.value
        XCTAssertEqual(draft.photoData, old)
        XCTAssertFalse(draft.isLoading)
        XCTAssertEqual(draft.alert, .importFailed)

        let gate = PhotoImportGate()
        let obsolete = draft.load { await gate.data() }
        await gate.waitUntilRequested()
        let latest = draft.load { new }
        await latest.value
        await gate.release(Data([3]))
        await obsolete.value
        XCTAssertEqual(draft.photoData, new)
        XCTAssertNil(draft.alert)
        XCTAssertFalse(draft.isLoading)

        let removalGate = PhotoImportGate()
        let removed = draft.load { await removalGate.data() }
        await removalGate.waitUntilRequested()
        draft.remove()
        await removalGate.release(new)
        await removed.value
        XCTAssertNil(draft.photoData)
        XCTAssertFalse(draft.isLoading)
    }

    @MainActor
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Plant.self, Room.self, Watering.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        return container
    }

    @MainActor
    func testSaveReplaceRemoveAndLegacySignaturesKeepPhoto() throws {
        let container = try container()
        let store = PlantStore(context: container.mainContext)
        let first = Data([1]), second = Data([2])
        let plant = try store.savePlant(name: "Monstera", intervalDays: 7, firstDueDate: .now,
                                        room: nil, photoData: first)
        XCTAssertEqual(plant.photoData, first)
        let room = try store.saveRoom(name: "Salon")
        try store.savePlant(plant, name: plant.name, intervalDays: 3, firstDueDate: plant.firstDueDate, room: room)
        try store.savePlant(plant, name: "Monstera du salon", intervalDays: 5, firstDueDate: plant.firstDueDate)
        XCTAssertEqual(plant.photoData, first)
        XCTAssertEqual(plant.room?.id, room.id)
        try store.water(plant)
        let wateringID = try XCTUnwrap(plant.waterings.first?.id)
        let due = plant.schedule.nextDueDate()
        try store.savePlant(plant, name: plant.name, intervalDays: 5, firstDueDate: plant.firstDueDate,
                            room: room, photoData: second)
        XCTAssertEqual(plant.photoData, second)
        try store.savePlant(plant, name: plant.name, intervalDays: 5, firstDueDate: plant.firstDueDate,
                            room: room, photoData: nil)
        XCTAssertNil(plant.photoData)
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID])
        XCTAssertEqual(plant.schedule.nextDueDate(), due)
    }

    @MainActor
    func testFailedPhotoSavesRestorePlantAndAllowRetry() throws {
        enum Failure: Error { case simulated }
        let container = try container()
        let context = container.mainContext
        let working = PlantStore(context: context)
        let failing = PlantStore(context: context, saveChanges: { throw Failure.simulated })
        let first = Data([1]), second = Data([2])
        let room = try working.saveRoom(name: "Salon")
        let plant = try working.savePlant(name: "Monstera", intervalDays: 7, firstDueDate: .now,
                                         room: room, photoData: first)
        try working.water(plant)
        let wateringID = try XCTUnwrap(plant.waterings.first?.id)
        XCTAssertThrowsError(try failing.savePlant(name: "Ficus", intervalDays: 3, firstDueDate: .now,
                                                  room: room, photoData: second))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plant>()), 1)
        for replacement in [second, nil] as [Data?] {
            XCTAssertThrowsError(try failing.savePlant(plant, name: "Modifiée", intervalDays: 3,
                                  firstDueDate: .now, room: nil, photoData: replacement))
            XCTAssertEqual(plant.photoData, first)
            XCTAssertEqual(plant.name, "Monstera")
            XCTAssertEqual(plant.room?.id, room.id)
            XCTAssertEqual(room.plants.map(\.id), [plant.id])
            XCTAssertFalse(context.hasChanges)
        }
        try working.saveRoom(name: "Bureau")
        XCTAssertEqual(plant.photoData, first)
        XCTAssertThrowsError(try failing.delete(plant))
        XCTAssertEqual(plant.photoData, first)
        XCTAssertEqual(plant.room?.id, room.id)
        XCTAssertEqual(room.plants.map(\.id), [plant.id])
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID])
        XCTAssertFalse(context.hasChanges)
        try working.savePlant(plant, name: plant.name, intervalDays: 7,
                              firstDueDate: plant.firstDueDate, room: room, photoData: second)
        XCTAssertEqual(plant.photoData, second)
    }

    @MainActor
    func testExternalPhotoPersistsReplacementRemovalAndPlantDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("photos.store")
        // A sufficiently large blob exercises SwiftData's external-storage path.
        let first = Data(repeating: 42, count: 300_000)
        let second = Data(repeating: 84, count: 300_000)
        var plantID: UUID!
        do {
            let initial = try container(url: url)
            let plant = try PlantStore(context: initial.mainContext).savePlant(name: "Monstera",
                                intervalDays: 7, firstDueDate: .now, room: nil, photoData: first)
            plantID = plant.id
        }
        do {
            let reopened = try container(url: url)
            let plant = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Plant>()).first)
            XCTAssertEqual(plant.id, plantID)
            XCTAssertEqual(plant.photoData, first)
            try PlantStore(context: reopened.mainContext).savePlant(plant, name: plant.name,
                intervalDays: 7, firstDueDate: plant.firstDueDate, room: nil, photoData: second)
        }
        do {
            let reopened = try container(url: url)
            let plant = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Plant>()).first)
            XCTAssertEqual(plant.photoData, second)
            try PlantStore(context: reopened.mainContext).savePlant(plant, name: plant.name,
                intervalDays: 7, firstDueDate: plant.firstDueDate, room: nil, photoData: nil)
        }
        do {
            let reopened = try container(url: url)
            let plant = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Plant>()).first)
            XCTAssertNil(plant.photoData)
            let store = PlantStore(context: reopened.mainContext)
            try store.savePlant(plant, name: plant.name, intervalDays: 7,
                                firstDueDate: plant.firstDueDate, room: nil, photoData: first)
            try store.delete(plant)
        }
        let reopened = try container(url: url)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<Plant>()), 0)
    }

    @MainActor
    func testMigrationFromPrePhotoSchemaPreservesRoomAndWatering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        let now = Date.now
        var plantID: UUID!, roomID: UUID!, wateringID: UUID!
        do {
            let schema = Schema([PrePhotoGarden.Plant.self, PrePhotoGarden.Room.self, PrePhotoGarden.Watering.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            legacy.mainContext.autosaveEnabled = false
            let plant = PrePhotoGarden.Plant(name: "Monstera", firstDueDate: now)
            let room = PrePhotoGarden.Room(name: "Salon")
            let watering = PrePhotoGarden.Watering(date: now, plant: plant)
            legacy.mainContext.insert(plant)
            legacy.mainContext.insert(room)
            legacy.mainContext.insert(watering)
            plant.room = room
            room.plants = [plant]
            plant.waterings = [watering]
            plantID = plant.id
            roomID = room.id
            wateringID = watering.id
            try legacy.mainContext.save()
        }
        let migrated = try container(url: url)
        let plant = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Plant>()).first)
        XCTAssertEqual(plant.id, plantID)
        XCTAssertEqual(plant.name, "Monstera")
        XCTAssertEqual(plant.intervalDays, 7)
        XCTAssertEqual(plant.firstDueDate, now)
        XCTAssertEqual(plant.createdAt, now)
        XCTAssertNil(plant.photoData)
        XCTAssertEqual(plant.room?.id, roomID)
        XCTAssertEqual(plant.room?.name, "Salon")
        XCTAssertEqual(plant.room?.plants.map(\.id), [plantID!])
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID!])
        XCTAssertEqual(plant.waterings.first?.date, now)
        let photo = Data([1, 2, 3])
        try PlantStore(context: migrated.mainContext).savePlant(plant, name: plant.name,
                intervalDays: 7, firstDueDate: plant.firstDueDate, room: plant.room, photoData: photo)
        let reopened = try container(url: url)
        let restored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Plant>()).first)
        XCTAssertEqual(restored.photoData, photo)
        XCTAssertEqual(restored.room?.id, roomID)
        XCTAssertEqual(restored.waterings.map(\.id), [wateringID!])
    }
}

private actor PhotoImportGate {
    private var continuation: CheckedContinuation<Data, Never>?
    private var requested: CheckedContinuation<Void, Never>?

    func data() async -> Data {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            requested?.resume()
            requested = nil
        }
    }

    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }

    func release(_ data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

// Frozen schema immediately before photos were added, including room relationships.
private enum PrePhotoGarden {
    @Model
    final class Plant {
        @Attribute(.unique) var id: UUID
        var name: String
        var intervalDays: Int
        var firstDueDate: Date
        var createdAt: Date
        var room: Room?
        @Relationship(deleteRule: .cascade, inverse: \Watering.plant)
        var waterings: [Watering] = []

        init(name: String, firstDueDate: Date) {
            id = UUID()
            self.name = name
            intervalDays = 7
            self.firstDueDate = firstDueDate
            createdAt = firstDueDate
        }
    }

    @Model
    final class Room {
        @Attribute(.unique) var id: UUID
        var name: String
        @Relationship(deleteRule: .nullify, inverse: \Plant.room)
        var plants: [Plant] = []

        init(name: String) { id = UUID(); self.name = name }
    }

    @Model
    final class Watering {
        @Attribute(.unique) var id: UUID
        var date: Date
        var plant: Plant?

        init(date: Date, plant: Plant) { id = UUID(); self.date = date; self.plant = plant }
    }
}
