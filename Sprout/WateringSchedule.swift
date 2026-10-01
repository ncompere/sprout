import Foundation

/// Day-based scheduling, independent of SwiftUI and persistence.
struct WateringSchedule {
    let intervalDays: Int
    let firstDueDate: Date
    let wateringDates: [Date]

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    func nextDueDate(calendar: Calendar = Self.calendar) -> Date {
        guard let latest = wateringDates.max() else {
            return calendar.startOfDay(for: firstDueDate)
        }
        return calendar.date(byAdding: .day, value: max(1, intervalDays),
                             to: calendar.startOfDay(for: latest)) ?? .distantFuture
    }

    func hasWatered(on date: Date, calendar: Calendar = Self.calendar) -> Bool {
        wateringDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    func isOverdue(on today: Date, calendar: Calendar = Self.calendar) -> Bool {
        nextDueDate(calendar: calendar) < calendar.startOfDay(for: today)
    }

    /// A missed deadline is one outstanding task. Future projections resume after watering.
    func projectedDates(in range: DateInterval, today: Date,
                        calendar: Calendar = Self.calendar) -> [Date] {
        let due = nextDueDate(calendar: calendar)
        if due < calendar.startOfDay(for: today) {
            return due >= range.start && due < range.end ? [due] : []
        }
        guard intervalDays > 0, due < range.end else { return [] }
        var cursor = due
        if cursor < range.start {
            let days = calendar.dateComponents([.day], from: cursor, to: range.start).day ?? 0
            let steps = days / intervalDays
            guard let advanced = calendar.date(byAdding: .day, value: steps * intervalDays, to: cursor) else {
                return []
            }
            cursor = advanced
            if cursor < range.start {
                guard let advanced = calendar.date(byAdding: .day, value: intervalDays, to: cursor) else {
                    return []
                }
                cursor = advanced
            }
        }
        var dates: [Date] = []
        while cursor < range.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: intervalDays, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }
        return dates
    }

    static func monthDays(containing date: Date, calendar: Calendar = Self.calendar) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: month.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        days += dayRange.map { calendar.date(byAdding: .day, value: $0 - 1, to: month.start) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}
