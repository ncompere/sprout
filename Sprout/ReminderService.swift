import Combine
import Foundation
import SwiftData
import UIKit
import UserNotifications

@MainActor
protocol ReminderNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
    func add(_ reminder: WateringReminder, calendar: Calendar, locale: Locale) async throws
}

@MainActor
struct SystemReminderNotificationCenter: ReminderNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func requestAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func deliveredIdentifiers() async -> [String] { await center.deliveredNotifications().map { $0.request.identifier } }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(_ identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }

    static func request(for reminder: WateringReminder, calendar: Calendar, locale: Locale,
                        bundle: Bundle = .main) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "C’est l’heure d’arroser", bundle: bundle, locale: locale)
        content.body = reminder.body(locale: locale, bundle: bundle)
        content.sound = .default
        content.threadIdentifier = "Sprout.watering"
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        // Gregorian dates, with a floating local time so iOS uses the device's time zone.
        var triggerCalendar = Calendar(identifier: .gregorian)
        triggerCalendar.timeZone = .autoupdatingCurrent
        components.calendar = triggerCalendar
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }

    func add(_ reminder: WateringReminder, calendar: Calendar, locale: Locale) async throws {
        try await center.add(Self.request(for: reminder, calendar: calendar, locale: locale))
    }
}

@MainActor
final class ReminderCoordinator: ObservableObject {
    static func live() -> ReminderCoordinator {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--uitest-reminders"),
           let suite = process.environment["UITEST_REMINDERS_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            if process.arguments.contains("--uitest-reminders-real") {
                let preferences = ReminderPreferences(defaults: defaults)
                let time = WateringSchedule.calendar.dateComponents([.hour, .minute], from: Date.now.addingTimeInterval(120))
                preferences.hour = time.hour ?? 9
                preferences.minute = time.minute ?? 0
                return ReminderCoordinator(preferences: preferences)
            }
            return ReminderCoordinator(preferences: ReminderPreferences(defaults: defaults),
                                       center: DebugReminderNotificationCenter())
        }
        #endif
        return ReminderCoordinator()
    }
    @Published private(set) var enabled: Bool
    @Published private(set) var hour: Int
    @Published private(set) var minute: Int
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private let preferences: ReminderPreferences
    private let center: any ReminderNotificationCenter
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let locale: () -> Locale
    private var plants: (() throws -> [ReminderPlant])?
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var shouldRequestAuthorization = false

    init(preferences: ReminderPreferences = ReminderPreferences(),
         center: (any ReminderNotificationCenter)? = nil,
         now: @escaping () -> Date = { .now },
         calendar: @escaping () -> Calendar = { WateringSchedule.calendar },
         locale: @escaping () -> Locale = { .current }) {
        self.preferences = preferences
        self.center = center ?? SystemReminderNotificationCenter()
        self.now = now
        self.calendar = calendar
        self.locale = locale
        enabled = preferences.enabled
        hour = preferences.hour
        minute = preferences.minute
    }

    func configure(context: ModelContext) {
        let scheduleCalendar = calendar
        plants = {
            try context.fetch(FetchDescriptor<Plant>()).map {
                ReminderPlant(id: $0.id, name: $0.name, nextDueDate: $0.schedule.nextDueDate(calendar: scheduleCalendar()),
                              included: $0.remindersIncluded)
            }
        }
        refresh()
    }

    /// Also permits deterministic tests without a persistence container.
    func configure(plants: @escaping () throws -> [ReminderPlant]) {
        self.plants = plants
        refresh()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        preferences.enabled = value
        shouldRequestAuthorization = value
        refresh()
    }

    func setTime(hour: Int, minute: Int) {
        preferences.hour = hour
        preferences.minute = minute
        self.hour = preferences.hour
        self.minute = preferences.minute
        refresh()
    }

    func refresh() {
        revision += 1
        guard worker == nil else { return }
        isRefreshing = true
        worker = Task { await reconcile() }
    }

    func retry() {
        shouldRequestAuthorization = enabled
        refresh()
    }

    func waitUntilSettled() async { await worker?.value }

    private func reconcile() async {
        // Only one writer ever touches the system queue. Any change during an await
        // invalidates the snapshot; finish that operation, then reconcile the latest state.
        while true {
            let current = revision
            do { try await synchronize(revision: current) }
            catch {
                if current == revision {
                    errorMessage = String(localized: "Les rappels n’ont pas pu être mis à jour. Réessayez.")
                }
            }
            if current == revision { break }
        }
        worker = nil
        isRefreshing = false
    }

    private func synchronize(revision current: Int) async throws {
        let status = await center.authorizationStatus()
        guard current == revision else { return }
        authorization = status
        if enabled && shouldRequestAuthorization && status == .notDetermined {
            shouldRequestAuthorization = false
            try await center.requestAuthorization()
            let updated = await center.authorizationStatus()
            guard current == revision else { return }
            authorization = updated
        }
        shouldRequestAuthorization = false
        let allowed = [.authorized, .provisional, .ephemeral].contains(authorization)
        let pending = await center.pendingIdentifiers()
        guard current == revision else { return }
        if !enabled || !allowed {
            let delivered = await center.deliveredIdentifiers()
            guard current == revision else { return }
            center.removePending(pending.filter(Self.owns))
            center.removeDelivered(delivered.filter(Self.owns))
            errorMessage = nil
            return
        }
        guard let plants else { return }
        let calendar = calendar(), locale = locale()
        let plan = WateringReminderPlanner.reminders(plants: try plants(), now: now(),
                                                    hour: hour, minute: minute, calendar: calendar, locale: locale)
        let desired = Set(plan.map(\.identifier))
        // Same-date requests are replaced in place. Remove obsolete dates before adding,
        // so renewal never temporarily doubles the queue and exceeds its capacity.
        center.removePending(pending.filter { Self.owns($0) && !desired.contains($0) })
        for reminder in plan {
            guard current == revision else { return }
            try await center.add(reminder, calendar: calendar, locale: locale)
        }
        guard current == revision else { return }
        errorMessage = nil
    }

    static func owns(_ identifier: String) -> Bool { identifier.hasPrefix(WateringReminder.identifierPrefix) }
}

@MainActor
final class ReminderNavigation: ObservableObject {
    static let shared = ReminderNavigation()
    @Published private(set) var calendarRequest: UUID?
    func openCalendar() { calendarRequest = UUID() }
}

/// Installed before a cold-start notification response, and retained by the app delegate.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let owned = notification.request.identifier.hasPrefix(WateringReminder.identifierPrefix)
        completionHandler(owned ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           response.notification.request.identifier.hasPrefix(WateringReminder.identifierPrefix) {
            Task { @MainActor in
                ReminderNavigation.shared.openCalendar()
                completionHandler()
            }
        } else { completionHandler() }
    }
}

final class SproutAppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = ReminderNotificationDelegate()
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-open-reminder") {
            ReminderNavigation.shared.openCalendar()
        }
        #endif
        return true
    }
}

#if DEBUG
/// Isolated notification permission/error states for UI tests; never schedules real alerts.
@MainActor
private final class DebugReminderNotificationCenter: ReminderNotificationCenter {
    private var status: UNAuthorizationStatus = ProcessInfo.processInfo.arguments.contains("--uitest-reminders-denied")
        ? .denied : .notDetermined
    private var failNextAdd = ProcessInfo.processInfo.arguments.contains("--uitest-reminders-error")
    private var pending: Set<String> = []
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws { status = .authorized }
    func pendingIdentifiers() async -> [String] { Array(pending) }
    func deliveredIdentifiers() async -> [String] { [] }
    func removePending(_ identifiers: [String]) { pending.subtract(identifiers) }
    func removeDelivered(_ identifiers: [String]) { }
    func add(_ reminder: WateringReminder, calendar: Calendar, locale: Locale) async throws {
        if failNextAdd {
            failNextAdd = false
            throw NSError(domain: "Sprout.UITest", code: 1)
        }
        pending.insert(reminder.identifier)
    }
}
#endif
