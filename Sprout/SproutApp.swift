import SwiftUI
import SwiftData

@main
struct SproutApp: App {
    var body: some Scene {
        WindowGroup {
            StorageRootView()
                .environment(\.locale, Locale(identifier: "fr_FR"))
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
                    Text(storageError ?? "Ouverture de votre jardin…")
                } actions: {
                    Button("Réessayer", action: openStorage)
                }
            }
        }
        .task { if container == nil { openStorage() } }
    }

    private func openStorage() {
        do {
            let schema = Schema([Plant.self, Watering.self])
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            self.container = container
            storageError = nil
        } catch {
            storageError = "Impossible d’ouvrir les données. Réessayez pour retrouver vos plantes."
        }
    }
}

private struct SproutRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date.now
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            PlantListView(today: today)
                .tabItem { Label("Mes plantes", systemImage: "leaf") }
            WateringCalendarView(today: today)
                .tabItem { Label("Calendrier", systemImage: "calendar") }
        }
        .onReceive(clock) { today = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = .now }
        }
    }
}
