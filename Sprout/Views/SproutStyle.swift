import SwiftUI

/// Semantic system surfaces keep the garden readable in light and dark appearance.
enum SproutStyle {
    static let green = Color.accentColor
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let warning = Color("WarningColor")
}

/// A checkbox appearance with the accessibility behavior of a native toggle.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(configuration.isOn ? SproutStyle.green : .secondary)
                    .accessibilityHidden(true)
                configuration.label
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
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
    @Environment(\.locale) private var locale
    let plant: Plant
    let today: Date

    var body: some View {
        let due = plant.schedule.nextDueDate()
        if plant.schedule.isOverdue(on: today) {
            Label("En retard · \(due.formatted(CalendarPresentation.dateStyle(locale: locale).day().month(.abbreviated)))", systemImage: "exclamationmark.circle")
                .foregroundStyle(SproutStyle.warning)
        } else if WateringSchedule.calendar.isDate(due, inSameDayAs: today) {
            Label("À arroser aujourd’hui", systemImage: "drop.fill")
                .foregroundStyle(SproutStyle.green)
        } else {
            Label("Le \(due.formatted(CalendarPresentation.dateStyle(locale: locale).day().month(.abbreviated).year()))", systemImage: "drop")
                .foregroundStyle(.secondary)
        }
    }
}

struct PlantRow: View {
    @Environment(\.locale) private var locale
    let plant: Plant
    let today: Date
    var showsRoom = false

    var body: some View {
        HStack(spacing: 14) {
            PlantSymbol()
            VStack(alignment: .leading, spacing: 6) {
                Text(plant.name).font(.headline).foregroundStyle(.primary)
                if showsRoom {
                    Text(plant.roomName).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(LocalizedCopy.wateringInterval(plant.intervalDays, locale: locale))
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
            Text(message ?? String(localized: "Vos modifications n’ont pas été enregistrées. Réessayez."))
        }
    }
}

extension View {
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        modifier(SaveErrorAlert(message: message))
    }
}
