import SwiftUI
import SwiftData

struct PlantEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let plant: Plant?
    @State private var name: String
    @State private var interval: String
    @State private var firstDueDate: Date
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    private enum Field { case name, interval }

    init(plant: Plant? = nil) {
        self.plant = plant
        _name = State(initialValue: plant?.name ?? "")
        _interval = State(initialValue: String(plant?.intervalDays ?? 7))
        _firstDueDate = State(initialValue: plant?.firstDueDate ?? .now)
    }

    private var validInterval: Int? {
        guard let days = Int(interval), days >= 1,
              let next = WateringSchedule.calendar.date(byAdding: .day, value: days, to: firstDueDate),
              next > firstDueDate else { return nil }
        return days
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Votre plante") {
                    TextField("Nom de la plante", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("editor.name")
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fréquence en jours")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("Nombre de jours", text: $interval)
                            .keyboardType(.numberPad)
                            .frame(minHeight: 44)
                            .focused($focusedField, equals: .interval)
                            .accessibilityLabel("Fréquence en jours")
                            .accessibilityIdentifier("editor.interval")
                    }
                    DatePicker("Premier arrosage", selection: $firstDueDate, displayedComponents: .date)
                        .accessibilityIdentifier("editor.firstDate")
                    if validInterval == nil {
                        Text("Saisissez un nombre entier de jours supérieur ou égal à 1.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Rythme d’arrosage")
                } footer: {
                    Text(plant?.waterings.isEmpty == false
                         ? "La prochaine échéance sera calculée depuis le dernier arrosage enregistré."
                         : "Après chaque arrosage enregistré, la prochaine date sera calculée selon cette fréquence.")
                }
            }
            .navigationTitle(plant == nil ? "Nouvelle plante" : "Modifier la plante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validInterval == nil)
                        .accessibilityIdentifier("editor.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { focusedField = nil }
                }
            }
            .saveErrorAlert($errorMessage)
        }
    }

    private func save() {
        guard let days = validInterval else { return }
        do {
            try PlantStore(context: context).savePlant(plant, name: name, intervalDays: days, firstDueDate: firstDueDate)
            dismiss()
        } catch {
            errorMessage = "Vos modifications n’ont pas été enregistrées. Vos saisies sont conservées ; réessayez."
        }
    }
}
