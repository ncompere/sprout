import XCTest
@testable import Sprout

final class LocalizationTests: XCTestCase {
    func testPhotoActionsAndCameraPermissionAreTranslated() throws {
        for language in ["fr", "en"] {
            let resources = try bundle(language)
            XCTAssertEqual(resources.localizedString(forKey: "Choisir une photo", value: nil, table: nil),
                           language == "fr" ? "Choisir une photo" : "Choose a photo")
            XCTAssertEqual(resources.localizedString(forKey: "Prendre une photo", value: nil, table: nil),
                           language == "fr" ? "Prendre une photo" : "Take a photo")
            XCTAssertEqual(resources.localizedString(forKey: "Supprimer la photo", value: nil, table: nil),
                           language == "fr" ? "Supprimer la photo" : "Remove photo")
            XCTAssertEqual(resources.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist"),
                           language == "fr" ? "Sprout utilise l’appareil photo pour ajouter une photo à votre plante."
                               : "Sprout uses the camera to add a photo to your plant.")
        }
    }

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testFrenchAndEnglishCountsAndIntervals() throws {
        for language in ["fr", "en"] {
            let locale = Locale(identifier: language == "fr" ? "fr_FR" : "en_US")
            let resources = try bundle(language)
            let counts = language == "fr" ? ["Aucune plante", "1 plante", "2 plantes"]
                : ["No plants", "1 plant", "2 plants"]
            let due = language == "fr" ? ["Vos plantes sont à jour.", "1 plante à arroser.", "2 plantes à arroser."]
                : ["Your plants are up to date.", "1 plant to water.", "2 plants to water."]
            for count in 0...2 {
                XCTAssertEqual(LocalizedCopy.plantCount(count, locale: locale, bundle: resources), counts[count])
                XCTAssertEqual(LocalizedCopy.duePlants(count, locale: locale, bundle: resources), due[count])
            }
            XCTAssertEqual(LocalizedCopy.wateringInterval(1, locale: locale, bundle: resources),
                           language == "fr" ? "Chaque jour" : "Every day")
            XCTAssertEqual(LocalizedCopy.wateringInterval(7, locale: locale, bundle: resources),
                           language == "fr" ? "Tous les 7 jours" : "Every 7 days")
        }
    }

    func testAccessibleCalendarSummariesUseLanguageSpecificPlurals() throws {
        let fr = try bundle("fr"), en = try bundle("en")
        XCTAssertEqual(LocalizedCopy.calendarSummary(planned: 1, watered: 2, overdue: false,
                        isToday: true, locale: Locale(identifier: "fr_FR"), bundle: fr),
                       "Aujourd’hui. 1 arrosage prévu. 2 arrosages effectués.")
        XCTAssertEqual(LocalizedCopy.calendarSummary(planned: 2, watered: 1, overdue: true,
                        isToday: false, locale: Locale(identifier: "en_US"), bundle: en),
                       "2 waterings overdue. 1 watering completed.")
        XCTAssertEqual(LocalizedCopy.calendarSummary(planned: 0, watered: 0, overdue: false,
                        isToday: false, locale: Locale(identifier: "en_FR"), bundle: en),
                       "0 waterings scheduled. 0 waterings completed.")
    }

    func testEnglishCopyWithFrenchRegionalPreferences() throws {
        let locale = Locale(identifier: "en_FR")
        let resources = try bundle("en")
        XCTAssertEqual(LocalizedCopy.plantCount(2, locale: locale, bundle: resources), "2 plants")
        XCTAssertEqual(String(localized: "Une pièce porte déjà ce nom.", bundle: resources, locale: locale),
                       "A room with this name already exists.")
        XCTAssertEqual(String(localized: "La fréquence doit être un nombre entier de jours supérieur ou égal à 1.",
                              bundle: resources, locale: locale),
                       "The interval must be a whole number of days greater than or equal to 1.")
    }

    func testWeekdayHeadersAndGridShareFirstWeekday() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        for (locale, firstWeekday, firstSymbol, leading) in [("fr_FR", 2, "L", 6), ("en_US", 1, "S", 0), ("en_FR", 2, "M", 6)] {
            let calendar = CalendarPresentation.calendar(locale: Locale(identifier: locale),
                                                         firstWeekday: firstWeekday, timeZone: timeZone)
            let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
            let days = WateringSchedule.monthDays(containing: date, calendar: calendar)
            XCTAssertEqual(CalendarPresentation.weekdaySymbols(calendar: calendar).first, firstSymbol)
            XCTAssertEqual(days.firstIndex(where: { $0 != nil }), leading)
            XCTAssertEqual(days.compactMap { $0 }.count, 30)
            XCTAssertEqual(days.count % 7, 0)
        }
    }

    func testLeapMonthAndWateringDatesAreIndependentOfPresentation() {
        let timeZone = TimeZone(identifier: "Europe/Paris")!
        let monday = CalendarPresentation.calendar(locale: Locale(identifier: "fr_FR"), firstWeekday: 2, timeZone: timeZone)
        let sunday = CalendarPresentation.calendar(locale: Locale(identifier: "en_US"), firstWeekday: 1, timeZone: timeZone)
        let start = monday.date(from: DateComponents(year: 2028, month: 2, day: 1))!
        let schedule = WateringSchedule(intervalDays: 7, firstDueDate: start, wateringDates: [start])
        for calendar in [monday, sunday] {
            let days = WateringSchedule.monthDays(containing: start, calendar: calendar)
            XCTAssertEqual(days.compactMap { $0 }.count, 29)
            XCTAssertEqual(days.count % 7, 0)
            XCTAssertEqual(schedule.nextDueDate(calendar: calendar), schedule.nextDueDate(calendar: monday))
            let month = calendar.dateInterval(of: .month, for: start)!
            XCTAssertEqual(schedule.projectedDates(in: month, today: start, calendar: calendar),
                           schedule.projectedDates(in: month, today: start, calendar: monday))
        }
    }

    func testDateFormattingUsesActiveLanguageAndGregorianYear() {
        let date = Date(timeIntervalSince1970: 1_791_028_800) // October 3, 2026, noon UTC.
        for (locale, month) in [("fr_FR", "octobre"), ("en_US", "October"), ("en_FR", "October")] {
            let text = date.formatted(CalendarPresentation.dateStyle(locale: Locale(identifier: locale)).day().month(.wide).year())
            XCTAssertTrue(text.contains(month), text)
            XCTAssertTrue(text.contains("2026"), text)
        }
    }
}
