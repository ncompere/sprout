import SwiftUI

/// Semantic system surfaces keep the garden readable in light and dark appearance.
enum SproutStyle {
    static let green = Color.accentColor
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let warning = Color("WarningColor")
}

struct PlantSymbol: View {
    var body: some View {
        Image(systemName: "leaf.fill")
            .font(.title2)
            .foregroundStyle(SproutStyle.green)
            .frame(width: 48, height: 48)
            .background(SproutStyle.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

struct DueLabel: View {
    let plant: Plant
    let today: Date

    var body: some View {
        let due = plant.schedule.nextDueDate()
        if plant.schedule.isOverdue(on: today) {
            Label("En retard · \(due.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))", systemImage: "exclamationmark.circle")
                .foregroundStyle(SproutStyle.warning)
        } else if WateringSchedule.calendar.isDate(due, inSameDayAs: today) {
            Label("À arroser aujourd’hui", systemImage: "drop.fill")
                .foregroundStyle(SproutStyle.green)
        } else {
            Label("Le \(due.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_FR"))))", systemImage: "drop")
                .foregroundStyle(.secondary)
        }
    }
}

struct PlantRow: View {
    let plant: Plant
    let today: Date

    var body: some View {
        HStack(spacing: 14) {
            PlantSymbol()
            VStack(alignment: .leading, spacing: 6) {
                Text(plant.name).font(.headline).foregroundStyle(.primary)
                Text(plant.intervalDays == 1 ? "Chaque jour" : "Tous les \(plant.intervalDays) jours")
                    .font(.subheadline).foregroundStyle(.secondary)
                DueLabel(plant: plant, today: today).font(.subheadline)
            }
            .padding(.vertical, 5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SaveErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("Enregistrement impossible", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "Vos modifications n’ont pas été enregistrées. Réessayez.")
        }
    }
}

extension View {
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        modifier(SaveErrorAlert(message: message))
    }
}
