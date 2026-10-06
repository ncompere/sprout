import SwiftUI
import UIKit
import UserNotifications

struct ReminderSettingsView: View {
    @ObservedObject var reminders: ReminderCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var time: Binding<Date> {
        Binding {
            WateringSchedule.calendar.date(bySettingHour: reminders.hour, minute: reminders.minute,
                                          second: 0, of: .now) ?? .now
        } set: { date in
            let parts = WateringSchedule.calendar.dateComponents([.hour, .minute], from: date)
            reminders.setTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Rappels d’arrosage", isOn: Binding(get: { reminders.enabled }, set: reminders.setEnabled))
                        .accessibilityIdentifier("reminders.enabled")
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Heure du rappel").fixedSize(horizontal: false, vertical: true)
                            timePicker.labelsHidden().accessibilityLabel("Heure du rappel")
                        }
                    } else {
                        timePicker
                    }
                } header: {
                    Text("Résumé quotidien")
                } footer: {
                    Text("Un rappel regroupe les plantes à arroser et celles en retard. Excluez une plante depuis son formulaire de modification.")
                }
                Section("Autorisation iOS") {
                    authorizationLabel.accessibilityIdentifier("reminders.authorization")
                    if reminders.authorization == .denied {
                        Button("Ouvrir les réglages iOS") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                        .accessibilityIdentifier("reminders.systemSettings")
                    }
                }
                if let error = reminders.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("reminders.error")
                        Button("Réessayer", action: reminders.retry)
                            .disabled(reminders.isRefreshing)
                            .accessibilityIdentifier("reminders.retry")
                    }
                }
                Section {
                    Text("Les 60 prochains rappels sont préparés sur cet appareil. Ouvrir Sprout renouvelle cette réserve. Une fois les rappels épuisés, rouvrez l’application pour les reprendre.")
                    Text("Si l’heure choisie est déjà passée, le prochain rappel commencera demain.")
                } header: {
                    Text("Rappels hors ligne")
                }
            }
            .navigationTitle("Réglages")
        }
    }

    private var timePicker: some View {
        DatePicker("Heure du rappel", selection: time, displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("reminders.time")
    }

    private var authorizationLabel: Text {
        switch reminders.authorization {
        case .authorized: Text("Notifications autorisées")
        case .provisional: Text("Notifications silencieuses autorisées")
        case .ephemeral: Text("Notifications temporairement autorisées")
        case .denied: Text("Notifications refusées. Autorisez-les dans les réglages iOS pour recevoir les rappels.")
        case .notDetermined: Text("Activez les rappels pour autoriser les notifications.")
        @unknown default: Text("Autorisation indisponible")
        }
    }
}
