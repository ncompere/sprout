import XCTest
@testable import Sprout

final class WateringScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = WateringSchedule.calendar
        value.timeZone = TimeZone(identifier: "Europe/Paris")!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testFirstDueDateIsNormalizedToDay() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 10, 1), wateringDates: [])
        XCTAssertEqual(schedule.nextDueDate(calendar: calendar), date(2026, 10, 1, 0))
    }

    func testEarlyWateringRecalculatesFromActualDay() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 10, 10),
                                       wateringDates: [date(2026, 10, 1, 18)])
        XCTAssertEqual(schedule.nextDueDate(calendar: calendar), date(2026, 10, 8, 0))
    }

    func testLateWateringClearsOverdueAndUsesLatestRecord() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 9, 1),
                                       wateringDates: [date(2026, 10, 1), date(2026, 9, 20)])
        XCTAssertEqual(schedule.nextDueDate(calendar: calendar), date(2026, 10, 8, 0))
        XCTAssertFalse(schedule.isOverdue(on: date(2026, 10, 1), calendar: calendar))
    }

    func testDueTodayIsNotOverdue() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 10, 1), wateringDates: [])
        XCTAssertFalse(schedule.isOverdue(on: date(2026, 10, 1, 22), calendar: calendar))
        XCTAssertTrue(schedule.isOverdue(on: date(2026, 10, 2), calendar: calendar))
    }

    func testChangedFrequencyUsesLatestWatering() {
        let schedule = WateringSchedule(intervalDays: 3, firstDueDate: date(2026, 9, 1),
                                       wateringDates: [date(2026, 10, 1)])
        XCTAssertEqual(schedule.nextDueDate(calendar: calendar), date(2026, 10, 4, 0))
    }

    func testFrequencyChangeBeforeFirstWateringKeepsInitialDate() {
        let schedule = WateringSchedule(intervalDays: 3, firstDueDate: date(2026, 10, 10), wateringDates: [])
        XCTAssertEqual(schedule.nextDueDate(calendar: calendar), date(2026, 10, 10, 0))
    }

    func testSameDayCheckAcrossDifferentTimes() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 10, 1),
                                       wateringDates: [date(2026, 10, 1, 1)])
        XCTAssertTrue(schedule.hasWatered(on: date(2026, 10, 1, 23), calendar: calendar))
        XCTAssertFalse(schedule.hasWatered(on: date(2026, 10, 2, 0), calendar: calendar))
    }

    func testCrossingYear() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 12, 25),
                                       wateringDates: [date(2026, 12, 28)])
        XCTAssertEqual(schedule.nextDueDate(calendar: calendar), date(2027, 1, 4, 0))
    }

    func testLeapDay() {
        let schedule = WateringSchedule(intervalDays: 1, firstDueDate: date(2028, 2, 28),
                                       wateringDates: [date(2028, 2, 28)])
        XCTAssertEqual(schedule.nextDueDate(calendar: calendar), date(2028, 2, 29, 0))
    }

    func testSpringTimeChangeUsesCalendarDays() {
        let watered = date(2026, 3, 28, 0)
        let schedule = WateringSchedule(intervalDays: 2, firstDueDate: watered, wateringDates: [watered])
        let next = schedule.nextDueDate(calendar: calendar)
        XCTAssertEqual(next, date(2026, 3, 30, 0))
        XCTAssertEqual(next.timeIntervalSince(watered), 47 * 3600)
    }

    func testAutumnTimeChangeUsesCalendarDays() {
        let watered = date(2026, 10, 24, 0)
        let schedule = WateringSchedule(intervalDays: 2, firstDueDate: watered, wateringDates: [watered])
        let next = schedule.nextDueDate(calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 26, 0))
        XCTAssertEqual(next.timeIntervalSince(watered), 49 * 3600)
    }

    func testProjectionsAreBoundedToDisplayedMonth() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 10, 1), wateringDates: [])
        let month = calendar.dateInterval(of: .month, for: date(2026, 10, 1))!
        XCTAssertEqual(schedule.projectedDates(in: month, today: date(2026, 10, 1), calendar: calendar),
                       [1, 8, 15, 22, 29].map { date(2026, 10, $0, 0) })
    }

    func testFarFutureMonthKeepsCadenceAndExcludesEndBoundary() {
        let schedule = WateringSchedule(intervalDays: 1, firstDueDate: date(2026, 10, 1), wateringDates: [])
        let month = calendar.dateInterval(of: .month, for: date(2030, 2, 1))!
        let projections = schedule.projectedDates(in: month, today: date(2026, 10, 1), calendar: calendar)
        XCTAssertEqual(projections.count, 28)
        XCTAssertEqual(projections.first, date(2030, 2, 1, 0))
        XCTAssertEqual(projections.last, date(2030, 2, 28, 0))
    }

    func testProjectionsSkipToMonthWithoutLosingWeeklyCadence() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 10, 1), wateringDates: [])
        let month = calendar.dateInterval(of: .month, for: date(2027, 2, 1))!
        XCTAssertEqual(schedule.projectedDates(in: month, today: date(2026, 10, 1), calendar: calendar),
                       [4, 11, 18, 25].map { date(2027, 2, $0, 0) })
    }

    func testOverdueIsOneOutstandingTaskWithoutFutureProjections() {
        let schedule = WateringSchedule(intervalDays: 2, firstDueDate: date(2026, 10, 1), wateringDates: [])
        let october = calendar.dateInterval(of: .month, for: date(2026, 10, 1))!
        let november = calendar.dateInterval(of: .month, for: date(2026, 11, 1))!
        XCTAssertEqual(schedule.projectedDates(in: october, today: date(2026, 10, 15), calendar: calendar),
                       [date(2026, 10, 1, 0)])
        XCTAssertTrue(schedule.projectedDates(in: november, today: date(2026, 10, 15), calendar: calendar).isEmpty)
    }

    func testWateringResumesProjections() {
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: date(2026, 9, 1),
                                       wateringDates: [date(2026, 10, 15)])
        let month = calendar.dateInterval(of: .month, for: date(2026, 10, 1))!
        XCTAssertEqual(schedule.projectedDates(in: month, today: date(2026, 10, 15), calendar: calendar),
                       [date(2026, 10, 22, 0), date(2026, 10, 29, 0)])
    }

    func testMonthGridStartsOnMondayAndIncludesLeapDay() {
        let days = WateringSchedule.monthDays(containing: date(2028, 2, 1), calendar: calendar)
        XCTAssertNil(days.first!) // February 1 is a Tuesday.
        XCTAssertEqual(days[1], date(2028, 2, 1, 0))
        XCTAssertEqual(days.compactMap { $0 }.count, 29)
        XCTAssertEqual(days.count % 7, 0)
    }

    func testMonthStartingSundayHasSixLeadingSlots() {
        let days = WateringSchedule.monthDays(containing: date(2026, 11, 1), calendar: calendar)
        XCTAssertTrue(days.prefix(6).allSatisfy { $0 == nil })
        XCTAssertEqual(days[6], date(2026, 11, 1, 0))
    }

    func testProjectionsAcrossDaylightSavingKeepMidnight() {
        let schedule = WateringSchedule(intervalDays: 1, firstDueDate: date(2026, 3, 27), wateringDates: [])
        let month = calendar.dateInterval(of: .month, for: date(2026, 3, 1))!
        let dates = schedule.projectedDates(in: month, today: date(2026, 3, 27), calendar: calendar)
        XCTAssertEqual(dates.count, 5)
        XCTAssertTrue(dates.allSatisfy { calendar.component(.hour, from: $0) == 0 })
    }
}
