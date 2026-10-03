import Foundation

/// Shared phrases also used by accessibility. Integer interpolation drives catalog plurals.
enum LocalizedCopy {
    static func plantCount(_ count: Int, locale: Locale = .current, bundle: Bundle = .main) -> String {
        if count == 0 { return String(localized: "Aucune plante", bundle: bundle, locale: locale) }
        return String(localized: "\(count) plante", bundle: bundle, locale: locale)
    }

    static func wateringInterval(_ days: Int, locale: Locale = .current, bundle: Bundle = .main) -> String {
        if days == 1 { return String(localized: "Chaque jour", bundle: bundle, locale: locale) }
        return String(localized: "Tous les \(days) jours", bundle: bundle, locale: locale)
    }

    static func duePlants(_ count: Int, locale: Locale = .current, bundle: Bundle = .main) -> String {
        if count == 0 { return String(localized: "Vos plantes sont à jour.", bundle: bundle, locale: locale) }
        return String(localized: "\(count) plante à arroser.", bundle: bundle, locale: locale)
    }

    static func calendarSummary(planned: Int, watered: Int, overdue: Bool, isToday: Bool,
                                locale: Locale = .current, bundle: Bundle = .main) -> String {
        var sentences: [String] = []
        if isToday { sentences.append(String(localized: "Aujourd’hui.", bundle: bundle, locale: locale)) }
        sentences.append(overdue
            ? String(localized: "\(planned) arrosage en retard.", bundle: bundle, locale: locale)
            : String(localized: "\(planned) arrosage prévu.", bundle: bundle, locale: locale))
        sentences.append(String(localized: "\(watered) arrosage effectué.", bundle: bundle, locale: locale))
        return sentences.joined(separator: " ")
    }
}

/// Presentation preferences never alter the Gregorian day-based watering schedule.
enum CalendarPresentation {
    static func calendar(locale: Locale, firstWeekday: Int = Calendar.autoupdatingCurrent.firstWeekday,
                         timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = locale
        result.timeZone = timeZone
        result.firstWeekday = firstWeekday
        return result
    }

    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    static func dateStyle(locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar(locale: locale), timeZone: .autoupdatingCurrent)
    }
}
