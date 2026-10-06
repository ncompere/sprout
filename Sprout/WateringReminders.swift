import Foundation

/// Immutable input: no SwiftData objects cross an asynchronous notification operation.
struct ReminderPlant {
    let id: UUID
    let name: String
    let nextDueDate: Date
    var included = true
}

struct WateringReminder: Equatable {
    static let identifierPrefix = "Sprout.watering."
    let identifier: String
    let fireDate: Date
    let plantNames: [String]

    func body(locale: Locale = .current, bundle: Bundle = .main) -> String {
        var result = LocalizedCopy.duePlants(plantNames.count, locale: locale, bundle: bundle)
        result += " " + plantNames.prefix(3).joined(separator: ", ")
        let remaining = plantNames.count - 3
        if remaining > 0 {
            result += ". " + String(localized: "Et \(remaining) autre plante.", bundle: bundle, locale: locale)
        }
        return result
    }
}

enum WateringReminderPlanner {
    static let capacity = 60

    static func reminders(plants: [ReminderPlant], now: Date, hour: Int, minute: Int,
                          calendar: Calendar = WateringSchedule.calendar,
                          locale: Locale = .current) -> [WateringReminder] {
        let included = plants.filter(\.included)
        guard let earliest = included.map(\.nextDueDate).min() else { return [] }
        var day = max(calendar.startOfDay(for: now), calendar.startOfDay(for: earliest))
        let sorted = included.sorted {
            let comparison = $0.name.compare($1.name, options: [.numeric, .caseInsensitive], locale: locale)
            return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }
        var result: [WateringReminder] = []
        while result.count < capacity {
            // Calendar arithmetic preserves wall-clock time across DST. In a missing hour,
            // use the next available time; in a repeated hour, send only on the first occurrence.
            guard let fire = calendar.date(bySettingHour: min(23, max(0, hour)),
                                           minute: min(59, max(0, minute)), second: 0, of: day,
                                           matchingPolicy: .nextTime, repeatedTimePolicy: .first,
                                           direction: .forward) else { break }
            if fire > now, calendar.isDate(fire, inSameDayAs: day) {
                let names = sorted.filter { calendar.startOfDay(for: $0.nextDueDate) <= day }.map(\.name)
                if !names.isEmpty {
                    let parts = calendar.dateComponents([.year, .month, .day], from: day)
                    let key = "\(parts.year!)-\(parts.month!)-\(parts.day!)"
                    result.append(WateringReminder(identifier: WateringReminder.identifierPrefix + key,
                                                  fireDate: fire, plantNames: names))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }
}

/// The user's preference is separate from the system's notification authorization.
struct ReminderPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var enabled: Bool {
        get { defaults.bool(forKey: "reminders.enabled") }
        nonmutating set { defaults.set(newValue, forKey: "reminders.enabled") }
    }
    var hour: Int {
        get { min(23, max(0, defaults.object(forKey: "reminders.hour") as? Int ?? 9)) }
        nonmutating set { defaults.set(min(23, max(0, newValue)), forKey: "reminders.hour") }
    }
    var minute: Int {
        get { min(59, max(0, defaults.integer(forKey: "reminders.minute"))) }
        nonmutating set { defaults.set(min(59, max(0, newValue)), forKey: "reminders.minute") }
    }
}
