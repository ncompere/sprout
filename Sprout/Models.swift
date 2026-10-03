import Foundation
import SwiftData

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

    init(name: String, intervalDays: Int = 7, firstDueDate: Date, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.intervalDays = intervalDays
        self.firstDueDate = firstDueDate
        self.createdAt = createdAt
    }

    var schedule: WateringSchedule {
        WateringSchedule(intervalDays: intervalDays, firstDueDate: firstDueDate,
                         wateringDates: waterings.map(\.date))
    }

    var roomName: String { room?.name ?? String(localized: "Sans pièce") }
}

@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(deleteRule: .nullify, inverse: \Plant.room)
    var plants: [Plant] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
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
