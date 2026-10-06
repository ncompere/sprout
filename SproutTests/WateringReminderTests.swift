import XCTest
import SwiftData
import UserNotifications
@testable import Sprout

final class WateringReminderTests: XCTestCase {
    private var preferenceSuites: [String] = []
    override func tearDown() {
        for suite in preferenceSuites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        preferenceSuites = []
        super.tearDown()
    }
    private func calendar(_ zone: String = "Europe/Paris") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }
    private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 6,
                      _ hour: Int = 8, _ minute: Int = 0, zone: String = "Europe/Paris") -> Date {
        calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func plant(_ name: String, due: Date, included: Bool = true) -> ReminderPlant {
        ReminderPlant(id: UUID(), name: name, nextDueDate: due, included: included)
    }
    private func plan(_ plants: [ReminderPlant], now: Date? = nil, hour: Int = 9, minute: Int = 0,
                      zone: String = "Europe/Paris") -> [WateringReminder] {
        WateringReminderPlanner.reminders(plants: plants, now: now ?? date(), hour: hour, minute: minute,
                                         calendar: calendar(zone), locale: Locale(identifier: "fr_FR"))
    }

    func testSummaryGroupsDueAndOverdueAndExcludesOptedOutPlants() {
        let reminders = plan([plant("Monstera", due: date(2026, 10, 6)), plant("Aloe", due: date(2026, 10, 1)),
                              plant("Excluded", due: date(2026, 10, 1), included: false),
                              plant("Ficus", due: date(2026, 10, 8))])
        XCTAssertEqual(reminders.count, 60)
        XCTAssertEqual(reminders[0].plantNames, ["Aloe", "Monstera"])
        XCTAssertEqual(reminders[1].plantNames, ["Aloe", "Monstera"])
        XCTAssertEqual(reminders[2].plantNames, ["Aloe", "Ficus", "Monstera"])
        XCTAssertEqual(reminders[0].fireDate, date(2026, 10, 6, 9))
        XCTAssertEqual(Set(reminders.map(\.identifier)).count, 60)
    }

    func testNoPlantsOrOnlyExcludedPlantsProduceNoReminders() {
        XCTAssertTrue(plan([]).isEmpty)
        XCTAssertTrue(plan([plant("Ficus", due: date(), included: false)]).isEmpty)
    }

    func testFarFutureDeadlineStartsReserveAtFirstDueDate() {
        let reminders = plan([plant("Ficus", due: date(2027, 7, 1))])
        XCTAssertEqual(reminders.count, 60)
        XCTAssertEqual(reminders.first?.fireDate, date(2027, 7, 1, 9))
        XCTAssertEqual(reminders.last?.fireDate, date(2027, 8, 29, 9))
    }

    func testPassedTimeAndExactTimeStartTomorrowWithoutCatchUp() {
        for now in [date(2026, 10, 6, 9), date(2026, 10, 6, 15)] {
            let reminders = plan([plant("Ficus", due: date(2026, 10, 1))], now: now)
            XCTAssertEqual(reminders.first?.fireDate, date(2026, 10, 7, 9))
            XCTAssertTrue(reminders.allSatisfy { $0.fireDate > now })
        }
    }

    func testStableIdentifiersAndCustomTime() {
        let input = [plant("Ficus", due: date())]
        let first = plan(input), second = plan(input, hour: 10, minute: 30)
        XCTAssertEqual(first.map(\.identifier), second.map(\.identifier))
        XCTAssertEqual(second.first?.fireDate, date(2026, 10, 6, 10, 30))
    }

    func testDSTKeepsWallClockTimeAndSendsOncePerDay() {
        for (month, day, hours) in [(3, 28, 23.0), (10, 24, 25.0)] {
            let now = date(2026, month, day)
            let reminders = plan([plant("Ficus", due: now)], now: now)
            XCTAssertEqual(reminders[1].fireDate.timeIntervalSince(reminders[0].fireDate), hours * 3600)
            XCTAssertTrue(reminders.allSatisfy { calendar().component(.hour, from: $0.fireDate) == 9 })
        }
        let spring = date(2026, 3, 28, 1)
        let missing = plan([plant("Ficus", due: spring)], now: spring, hour: 2, minute: 30)
        XCTAssertEqual(missing[1].fireDate, date(2026, 3, 29, 3))
        let fall = date(2026, 10, 24, 1)
        let repeated = plan([plant("Ficus", due: fall)], now: fall, hour: 2, minute: 30)
        XCTAssertEqual(Set(repeated.map(\.identifier)).count, 60)
        XCTAssertEqual(calendar().component(.hour, from: repeated[1].fireDate), 2)
    }

    func testReplanningUsesCurrentTimeZone() {
        let now = date(2026, 10, 6, 0)
        let input = [plant("Ficus", due: now)]
        let paris = plan(input, now: now), tokyo = plan(input, now: now, zone: "Asia/Tokyo")
        XCTAssertEqual(calendar("Asia/Tokyo").component(.hour, from: tokyo[0].fireDate), 9)
        XCTAssertNotEqual(paris[0].fireDate, tokyo[0].fireDate)
    }

    func testLocalizedNotificationContentLimitsNamesAndUsesPlurals() throws {
        for language in ["fr", "en"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let locale = Locale(identifier: language)
            for count in [1, 2, 3, 4, 5] {
                let reminder = WateringReminder(identifier: "test", fireDate: date(),
                                                plantNames: Array(["Aloe", "Ficus", "Monstera", "Palm", "Yucca"].prefix(count)))
                let body = reminder.body(locale: locale, bundle: bundle)
                XCTAssertTrue(body.contains(language == "fr" ? "\(count) plante" : "\(count) plant"))
                XCTAssertFalse(body.contains("Palm"))
                XCTAssertFalse(body.contains("Yucca"))
                if count == 4 { XCTAssertTrue(body.contains(language == "fr" ? "Et 1 autre plante." : "And 1 other plant.")) }
                if count == 5 { XCTAssertTrue(body.contains(language == "fr" ? "Et 2 autres plantes." : "And 2 other plants.")) }
            }
        }
    }

    @MainActor
    func testRequestUsesCalendarTriggerAndLocalizedContent() throws {
        let reminder = try XCTUnwrap(plan([plant("Ficus", due: date())]).first)
        let bundle = try XCTUnwrap(Bundle(path: XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))))
        let request = SystemReminderNotificationCenter.request(for: reminder, calendar: calendar(),
                                                               locale: Locale(identifier: "en"), bundle: bundle)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.calendar?.identifier, .gregorian)
        XCTAssertEqual(request.identifier, reminder.identifier)
        XCTAssertEqual(request.content.title, "Time to water your plants")
        XCTAssertEqual(request.content.body, "1 plant to water. Ficus")
        XCTAssertNotNil(request.content.sound)
    }

    private func preferences() -> ReminderPreferences {
        let suite = "Sprout.reminderTests.\(UUID())"
        preferenceSuites.append(suite)
        return ReminderPreferences(defaults: UserDefaults(suiteName: suite)!)
    }

    func testPreferenceDefaultsPersistenceAndClamping() {
        let name = "Sprout.reminderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ReminderPreferences(defaults: defaults)
        XCTAssertFalse(preferences.enabled)
        XCTAssertEqual(preferences.hour, 9)
        XCTAssertEqual(preferences.minute, 0)
        preferences.enabled = true
        preferences.hour = 18
        preferences.minute = 30
        let reopened = ReminderPreferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertTrue(reopened.enabled)
        XCTAssertEqual(reopened.hour, 18)
        XCTAssertEqual(reopened.minute, 30)
        preferences.hour = 99
        preferences.minute = -1
        XCTAssertEqual(preferences.hour, 23)
        XCTAssertEqual(preferences.minute, 0)
    }

    @MainActor
    private func coordinator(_ center: FakeReminderCenter, preferences: ReminderPreferences? = nil) -> ReminderCoordinator {
        ReminderCoordinator(preferences: preferences ?? self.preferences(), center: center,
                            now: { self.date() }, calendar: { self.calendar() }, locale: { Locale(identifier: "en") })
    }

    @MainActor
    func testOptInRequestsPermissionButOpeningAndDeniedRefreshDoNot() async {
        let center = FakeReminderCenter()
        center.status = .notDetermined
        let coordinator = coordinator(center)
        coordinator.configure { [self.plant("Ficus", due: self.date())] }
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.authorizationRequests, 0)
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(center.pending.count, 60)
        center.status = .denied
        coordinator.refresh()
        await coordinator.waitUntilSettled()
        XCTAssertTrue(coordinator.enabled)
        XCTAssertEqual(coordinator.authorization, .denied)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.authorizationRequests, 1)
        center.status = .authorized
        coordinator.refresh()
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.pending.count, 60)
    }

    @MainActor
    func testDisableClearsOnlyOwnedPendingAndDeliveredNotifications() async {
        let center = FakeReminderCenter()
        center.unrelated = ["other.feature"]
        center.delivered = ["other.feature", WateringReminder.identifierPrefix + "old"]
        let coordinator = coordinator(center)
        coordinator.configure { [self.plant("Ficus", due: self.date())] }
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        coordinator.setEnabled(false)
        await coordinator.waitUntilSettled()
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.unrelated, ["other.feature"])
        XCTAssertEqual(center.delivered, ["other.feature"])
    }

    @MainActor
    func testDecliningAuthorizationKeepsOptInWithoutScheduling() async {
        let center = FakeReminderCenter()
        center.status = .notDetermined
        center.authorizationResult = .denied
        let coordinator = coordinator(center)
        coordinator.configure { [self.plant("Ficus", due: self.date())] }
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        XCTAssertTrue(coordinator.enabled)
        XCTAssertEqual(coordinator.authorization, .denied)
        XCTAssertTrue(center.pending.isEmpty)
        coordinator.retry()
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    @MainActor
    func testFetchFailurePreservesPreviouslyScheduledReminders() async {
        let center = FakeReminderCenter()
        let coordinator = coordinator(center)
        coordinator.configure { [self.plant("Ficus", due: self.date())] }
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        let previous = center.pending
        coordinator.configure { throw FakeReminderCenter.Failure.simulated }
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.pending, previous)
        XCTAssertNotNil(coordinator.errorMessage)
    }

    @MainActor
    func testRenewalReplacesDatesWithoutDuplicatesAndUpdatesNamesAndTime() async {
        let center = FakeReminderCenter()
        let coordinator = coordinator(center)
        var plants = [plant("Ficus", due: date())]
        coordinator.configure { plants }
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        plants = [plant("Renamed", due: date(2026, 10, 13))]
        coordinator.setTime(hour: 11, minute: 45)
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.pending.count, 60)
        XCTAssertTrue(center.pending.values.allSatisfy { $0.plantNames == ["Renamed"] })
        XCTAssertEqual(center.pending.values.map(\.fireDate).min(), date(2026, 10, 13, 11, 45))
        XCTAssertLessThanOrEqual(center.maximumPending, 60)
    }

    @MainActor
    func testErrorsPreserveEnabledPreferenceAndRetryRepairsQueue() async {
        let center = FakeReminderCenter()
        center.failAdd = true
        let coordinator = coordinator(center)
        coordinator.configure { [self.plant("Ficus", due: self.date())] }
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        XCTAssertTrue(coordinator.enabled)
        XCTAssertNotNil(coordinator.errorMessage)
        center.failAdd = false
        coordinator.retry()
        await coordinator.waitUntilSettled()
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(center.pending.count, 60)
    }

    @MainActor
    func testAuthorizationFailureCanBeRetriedWithoutDisablingPreference() async {
        let center = FakeReminderCenter()
        center.status = .notDetermined
        center.failAuthorization = true
        let coordinator = coordinator(center)
        coordinator.configure { [self.plant("Ficus", due: self.date())] }
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertTrue(coordinator.enabled)
        center.failAuthorization = false
        coordinator.retry()
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.authorizationRequests, 2)
        XCTAssertEqual(center.pending.count, 60)
        XCTAssertNil(coordinator.errorMessage)
    }

    @MainActor
    func testLatestSnapshotWinsWhenWateringChangesDuringAnAdd() async {
        let center = FakeReminderCenter()
        center.pauseNextAdd = true
        let started = expectation(description: "notification add is suspended")
        center.onPaused = { started.fulfill() }
        let coordinator = coordinator(center)
        var plants = [plant("Ficus", due: date())]
        coordinator.configure { plants }
        coordinator.setEnabled(true)
        await fulfillment(of: [started], timeout: 3)
        plants = [plant("Watered", due: date(2026, 10, 13))]
        coordinator.refresh()
        coordinator.setTime(hour: 12, minute: 0)
        center.resume()
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.pending.count, 60)
        XCTAssertTrue(center.pending.values.allSatisfy { $0.plantNames == ["Watered"] })
        XCTAssertEqual(center.pending.values.map(\.fireDate).min(), date(2026, 10, 13, 12))
        XCTAssertEqual(center.maximumConcurrentAdds, 1)
    }

    @MainActor
    func testDisableDuringAnAddRemovesTheStaleRequest() async {
        let center = FakeReminderCenter()
        center.pauseNextAdd = true
        let started = expectation(description: "notification add is suspended")
        center.onPaused = { started.fulfill() }
        let coordinator = coordinator(center)
        coordinator.configure { [self.plant("Ficus", due: self.date())] }
        coordinator.setEnabled(true)
        await fulfillment(of: [started], timeout: 3)
        coordinator.setEnabled(false)
        center.resume()
        await coordinator.waitUntilSettled()
        XCTAssertTrue(center.pending.isEmpty)
    }

    @MainActor
    func testStoreChangesRecomputeRealDeadlineAndFailedSaveDoesNotEmitCommit() async throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let store = PlantStore(context: context)
        let center = FakeReminderCenter()
        // Persistence normalizes dates in the device's zone. Use that same zone
        // here so the integration test also works on devices outside France.
        let localCalendar = WateringSchedule.calendar
        let now = localCalendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 8))!
        let firstFire = localCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let wateredFire = localCalendar.date(byAdding: .day, value: 7, to: firstFire)!
        let coordinator = ReminderCoordinator(preferences: preferences(), center: center,
                                              now: { now }, calendar: { localCalendar })
        coordinator.configure(context: context)
        let observer = NotificationCenter.default.addObserver(forName: PlantStore.didCommit, object: context, queue: .main) { _ in
            MainActor.assumeIsolated { coordinator.refresh() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let ficus = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: now)
        coordinator.setEnabled(true)
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.pending.values.map(\.fireDate).min(), firstFire)
        try store.water(ficus, on: now)
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.pending.values.map(\.fireDate).min(), wateredFire)
        try store.unwater(ficus, on: now)
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.pending.values.map(\.fireDate).min(), firstFire)
        let before = center.addCount
        let failing = PlantStore(context: context, saveChanges: { throw FakeReminderCenter.Failure.simulated })
        XCTAssertThrowsError(try failing.water(ficus, on: now))
        await coordinator.waitUntilSettled()
        XCTAssertEqual(center.addCount, before)
        XCTAssertTrue(ficus.waterings.isEmpty)
        try store.delete(ficus)
        await coordinator.waitUntilSettled()
        XCTAssertTrue(center.pending.isEmpty)
    }

    @MainActor
    private func memoryContainer() throws -> ModelContainer {
        let schema = Schema([Plant.self, Room.self, Watering.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        container.mainContext.autosaveEnabled = false
        return container
    }

    @MainActor
    func testPlantExclusionIsPreservedByExistingCallersAndRolledBackOnFailure() throws {
        let container = try memoryContainer()
        let store = PlantStore(context: container.mainContext)
        let ficus = try store.savePlant(name: "Ficus", intervalDays: 7, firstDueDate: date(), room: nil,
                                       photoData: nil, remindersIncluded: false)
        XCTAssertFalse(ficus.remindersIncluded)
        try store.savePlant(ficus, name: "Renamed", intervalDays: 3, firstDueDate: date())
        XCTAssertFalse(ficus.remindersIncluded)
        let failing = PlantStore(context: container.mainContext, saveChanges: { throw FakeReminderCenter.Failure.simulated })
        XCTAssertThrowsError(try failing.savePlant(ficus, name: "Failed", intervalDays: 7,
                firstDueDate: date(), room: nil, photoData: nil, remindersIncluded: true))
        XCTAssertFalse(ficus.remindersIncluded)
        XCTAssertEqual(ficus.name, "Renamed")
    }

    @MainActor
    func testMigrationFromPhotoSchemaIncludesExistingPlantsAndPersistsExclusion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("garden.store")
        let photo = Data([1, 2, 3])
        var id: UUID!, wateringID: UUID!, roomID: UUID!
        do {
            let schema = Schema([PreReminderGarden.Plant.self, PreReminderGarden.Room.self, PreReminderGarden.Watering.self])
            let legacy = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            legacy.mainContext.autosaveEnabled = false
            let plant = PreReminderGarden.Plant(name: "Ficus", firstDueDate: date())
            let room = PreReminderGarden.Room(name: "Salon")
            let watering = PreReminderGarden.Watering(date: date(), plant: plant)
            legacy.mainContext.insert(plant)
            legacy.mainContext.insert(room)
            legacy.mainContext.insert(watering)
            plant.photoData = photo
            plant.room = room
            room.plants = [plant]
            plant.waterings = [watering]
            id = plant.id; roomID = room.id; wateringID = watering.id
            try legacy.mainContext.save()
        }
        let schema = Schema([Plant.self, Room.self, Watering.self])
        func open() throws -> ModelContainer {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            container.mainContext.autosaveEnabled = false
            return container
        }
        do {
            let migrated = try open()
            let plant = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Plant>()).first)
            XCTAssertTrue(plant.remindersIncluded)
            XCTAssertEqual(plant.id, id)
            XCTAssertEqual(plant.name, "Ficus")
            XCTAssertEqual(plant.firstDueDate, date())
            XCTAssertEqual(plant.intervalDays, 7)
            XCTAssertEqual(plant.photoData, photo)
            XCTAssertEqual(plant.room?.id, roomID)
            XCTAssertEqual(plant.waterings.map(\.id), [wateringID!])
            try PlantStore(context: migrated.mainContext).savePlant(plant, name: plant.name,
                intervalDays: plant.intervalDays, firstDueDate: plant.firstDueDate, room: plant.room,
                photoData: plant.photoData, remindersIncluded: false)
        }
        let reopened = try open()
        let plant = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Plant>()).first)
        XCTAssertFalse(plant.remindersIncluded)
        XCTAssertEqual(plant.photoData, photo)
        XCTAssertEqual(plant.room?.id, roomID)
        XCTAssertEqual(plant.waterings.map(\.id), [wateringID!])
    }
}

@MainActor
private final class FakeReminderCenter: ReminderNotificationCenter {
    enum Failure: Error { case simulated }
    var status: UNAuthorizationStatus = .authorized
    var authorizationRequests = 0
    var authorizationResult: UNAuthorizationStatus = .authorized
    var failAuthorization = false
    var failAdd = false
    var pending: [String: WateringReminder] = [:]
    var unrelated: Set<String> = []
    var delivered: Set<String> = []
    var addCount = 0
    var maximumPending = 0
    var activeAdds = 0
    var maximumConcurrentAdds = 0
    var pauseNextAdd = false
    var onPaused: (() -> Void)?
    var paused: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws {
        authorizationRequests += 1
        if failAuthorization { throw Failure.simulated }
        status = authorizationResult
    }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) + unrelated }
    func deliveredIdentifiers() async -> [String] { Array(delivered) }
    func removePending(_ identifiers: [String]) {
        for identifier in identifiers { pending[identifier] = nil; unrelated.remove(identifier) }
    }
    func removeDelivered(_ identifiers: [String]) { delivered.subtract(identifiers) }
    func add(_ reminder: WateringReminder, calendar: Calendar, locale: Locale) async throws {
        activeAdds += 1
        maximumConcurrentAdds = max(maximumConcurrentAdds, activeAdds)
        defer { activeAdds -= 1 }
        if pauseNextAdd {
            pauseNextAdd = false
            await withCheckedContinuation { paused = $0; onPaused?() }
        }
        if failAdd { throw Failure.simulated }
        addCount += 1
        pending[reminder.identifier] = reminder
        maximumPending = max(maximumPending, pending.count)
    }
    func resume() { paused?.resume(); paused = nil }
}

/// Frozen schema including photos, immediately before reminders were introduced.
private enum PreReminderGarden {
    @Model
    final class Plant {
        @Attribute(.unique) var id: UUID
        var name: String
        var intervalDays: Int
        var firstDueDate: Date
        var createdAt: Date
        var room: Room?
        @Attribute(.externalStorage) var photoData: Data?
        @Relationship(deleteRule: .cascade, inverse: \Watering.plant) var waterings: [Watering] = []
        init(name: String, firstDueDate: Date) {
            id = UUID(); self.name = name; intervalDays = 7
            self.firstDueDate = firstDueDate; createdAt = firstDueDate
        }
    }
    @Model
    final class Room {
        @Attribute(.unique) var id: UUID
        var name: String
        @Relationship(deleteRule: .nullify, inverse: \Plant.room) var plants: [Plant] = []
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
