import SwiftUI
import SwiftData
import Combine

@main
struct SproutApp: App {
    @UIApplicationDelegateAdaptor(SproutAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            StorageRootView()
                .tint(SproutStyle.green)
                .modifier(DebugTestPresentation())
        }
    }
}

/// Deterministic appearance checks; these overrides are absent in release builds.
private struct DebugTestPresentation: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let scheme: ColorScheme? = arguments.contains("--uitest-dark") ? .dark
            : arguments.contains("--uitest-light") ? .light : nil
        if arguments.contains("--uitest-large-text") {
            content.preferredColorScheme(scheme).dynamicTypeSize(.accessibility5)
        } else {
            content.preferredColorScheme(scheme)
        }
        #else
        content
        #endif
    }
}

private struct StorageRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var locale = Locale.current
    @State private var presentationCalendar = CalendarPresentation.calendar(locale: .current)
    @State private var container: ModelContainer?
    @State private var storageError: String?

    var body: some View {
        Group {
            if let container {
                SproutRootView().modelContainer(container)
            } else {
                ContentUnavailableView {
                    Label("Vos plantes sont indisponibles", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(storageError ?? String(localized: "Ouverture de votre jardin…"))
                } actions: {
                    Button("Réessayer", action: openStorage)
                }
            }
        }
        .environment(\.locale, locale)
        .environment(\.calendar, presentationCalendar)
        .task { if container == nil { openStorage() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshRegionalSettings() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).receive(on: RunLoop.main)) { _ in
            refreshRegionalSettings()
        }
    }

    private func refreshRegionalSettings() {
        locale = .current
        presentationCalendar = CalendarPresentation.calendar(locale: locale)
    }

    private func openStorage() {
        do {
            let schema = Schema([Plant.self, Watering.self, Room.self])
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            self.container = container
            storageError = nil
        } catch {
            storageError = String(localized: "Impossible d’ouvrir les données. Réessayez pour retrouver vos plantes.")
        }
    }
}

private struct SproutRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var today = Date.now
    @State private var selectedTab = "plants"
    @State private var calendarPresentationID = UUID()
    @StateObject private var reminders = ReminderCoordinator.live()
    @ObservedObject private var reminderNavigation = ReminderNavigation.shared
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
            PlantListView(today: today)
                .tag("plants")
                .tabItem { Label("Mes plantes", systemImage: "leaf").accessibilityIdentifier("tab.plants") }
            WateringCalendarView(today: today)
                .id(calendarPresentationID)
                .tag("calendar")
                .tabItem { Label("Calendrier", systemImage: "calendar").accessibilityIdentifier("tab.calendar") }
            ReminderSettingsView(reminders: reminders)
                .tag("settings")
                .tabItem { Label("Réglages", systemImage: "gearshape").accessibilityIdentifier("tab.settings") }
        }
        .task { reminders.configure(context: context) }
        .onReceive(clock) { date in
            if !WateringSchedule.calendar.isDate(today, inSameDayAs: date) { reminders.refresh() }
            today = date
        }
        .onReceive(NotificationCenter.default.publisher(for: PlantStore.didCommit)) { event in
            if let changed = event.object as? ModelContext, changed === context { reminders.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).receive(on: RunLoop.main)) { _ in
            reminders.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in
            reminders.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: RunLoop.main)) { _ in
            today = .now
            reminders.refresh()
        }
        .onReceive(reminderNavigation.$calendarRequest.compactMap { $0 }) { request in
            today = .now
            calendarPresentationID = request
            selectedTab = "calendar"
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                today = .now
                reminders.refresh()
            }
        }
    }
}
