import SwiftUI
import SwiftData

struct WateringCalendarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query private var plants: [Plant]
    @State private var visibleMonth = Date.now
    @State private var selectedDate = Date.now
    @State private var showingEditor = false
    let today: Date
    private var calendar: Calendar { WateringSchedule.calendar }

    private struct Entry: Identifiable {
        enum Kind { case planned, overdue, watered }
        let plant: Plant
        let date: Date
        let kind: Kind
        var id: String { "\(plant.id)-\(date.timeIntervalSince1970)-\(kind)" }
    }

    private var entries: [Date: [Entry]] {
        guard let month = calendar.dateInterval(of: .month, for: visibleMonth) else { return [:] }
        var result: [Date: [Entry]] = [:]
        for plant in plants {
            for date in plant.schedule.projectedDates(in: month, today: today) {
                let kind: Entry.Kind = plant.schedule.isOverdue(on: today) ? .overdue : .planned
                result[date, default: []].append(Entry(plant: plant, date: date, kind: kind))
            }
            for watering in plant.waterings {
                let date = calendar.startOfDay(for: watering.date)
                if date >= month.start && date < month.end {
                    result[date, default: []].append(Entry(plant: plant, date: date, kind: .watered))
                }
            }
        }
        return result
    }

    private var overdue: [Plant] {
        plants.filter { $0.schedule.isOverdue(on: today) }
            .sorted { $0.schedule.nextDueDate() < $1.schedule.nextDueDate() }
    }

    var body: some View {
        let monthEntries = entries
        let dayEntries = (monthEntries[calendar.startOfDay(for: selectedDate)] ?? [])
            .sorted { $0.plant.name.localizedStandardCompare($1.plant.name) == .orderedAscending }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    calendarGrid(entries: monthEntries)
                        .padding(12)
                        .background(SproutStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                    if !overdue.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("En retard").font(.headline).foregroundStyle(SproutStyle.warning)
                            VStack(spacing: 0) {
                                ForEach(overdue) { plant in
                                    NavigationLink {
                                        PlantDetailView(plant: plant, today: today)
                                    } label: {
                                        HStack {
                                            PlantRow(plant: plant, today: today)
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                                .accessibilityHidden(true)
                                        }.padding(16)
                                    }
                                    .buttonStyle(.plain)
                                    if plant.id != overdue.last?.id { Divider().padding(.horizontal, 16) }
                                }
                            }
                            .background(SproutStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                            Text("Ces arrosages restent en attente. Les prochaines dates seront recalculées après l’arrosage.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "fr_FR"))))
                            .font(.headline).foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            if dayEntries.isEmpty {
                                Label("Aucun arrosage prévu ce jour", systemImage: "drop")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(20)
                            } else {
                                ForEach(dayEntries) { entry in
                                    NavigationLink {
                                        PlantDetailView(plant: entry.plant, today: today)
                                    } label: {
                                        HStack(spacing: 14) {
                                            PlantSymbol()
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(entry.plant.name).font(.headline)
                                                entryLabel(entry.kind).font(.subheadline)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                                .accessibilityHidden(true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(16)
                                        .accessibilityElement(children: .combine)
                                    }
                                    .buttonStyle(.plain)
                                    if entry.id != dayEntries.last?.id { Divider().padding(.horizontal, 16) }
                                }
                            }
                        }
                        .background(SproutStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if plants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ajoutez une plante pour voir son planning ici.")
                                .foregroundStyle(.secondary)
                            Button("Ajouter une plante") { showingEditor = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(SproutStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(16)
            }
            .background(SproutStyle.background)
            .navigationTitle("Calendrier")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aujourd’hui") {
                        visibleMonth = today
                        selectedDate = today
                    }
                    .accessibilityIdentifier("calendar.today")
                }
            }
            .sheet(isPresented: $showingEditor) { PlantEditorView() }
        }
    }

    private func calendarGrid(entries: [Date: [Entry]]) -> some View {
        VStack(spacing: 18) {
            HStack {
                Button("Mois précédent", systemImage: "chevron.left") { changeMonth(by: -1) }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("calendar.previous")
                Spacer(minLength: 0)
                Text(visibleMonth.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR"))).capitalized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("calendar.month")
                Spacer(minLength: 0)
                Button("Mois suivant", systemImage: "chevron.right") { changeMonth(by: 1) }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("calendar.next")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 6) {
                ForEach(Array(["L", "M", "M", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, label in
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                let days = WateringSchedule.monthDays(containing: visibleMonth)
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        dayButton(day, entries: entries[day] ?? [])
                    } else {
                        Color.clear.frame(height: 52).accessibilityHidden(true)
                    }
                }
            }
            // Seven date columns must stay distinct; the agenda below scales fully.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { legend }
                VStack(alignment: .leading, spacing: 8) { legend }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var legend: some View {
        Label("Prévu", systemImage: "circle")
        Label("Effectué", systemImage: "checkmark.circle.fill")
        Label("En retard", systemImage: "exclamationmark.circle")
    }

    private func dayButton(_ day: Date, entries: [Entry]) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let planned = entries.filter { $0.kind != .watered }.count
        let watered = entries.filter { $0.kind == .watered }.count
        let overdue = entries.contains { $0.kind == .overdue }
        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 5) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(selected || isToday ? .bold : .regular))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if planned > 0 {
                        Image(systemName: overdue ? "exclamationmark.circle.fill" : "circle")
                    }
                    if watered > 0 { Image(systemName: "checkmark.circle.fill") }
                }
                .font(.system(size: 9, weight: .semibold))
                .frame(height: 10)
            }
            .foregroundStyle(selected ? (colorScheme == .dark ? Color.black : Color.white)
                             : (isToday ? SproutStyle.green : .primary))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? SproutStyle.green : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isToday && !selected {
                    RoundedRectangle(cornerRadius: 12).stroke(SproutStyle.green, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "fr_FR"))))
        .accessibilityValue("\(isToday ? "Aujourd’hui. " : "")\(planned) arrosage(s) \(overdue ? "en retard" : "prévu(s)"), \(watered) effectué(s)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.\(calendar.component(.day, from: day))")
    }

    @ViewBuilder
    private func entryLabel(_ kind: Entry.Kind) -> some View {
        switch kind {
        case .planned:
            Label("Arrosage prévu", systemImage: "drop").foregroundStyle(.secondary)
        case .overdue:
            Label("Arrosage en retard", systemImage: "exclamationmark.circle").foregroundStyle(SproutStyle.warning)
        case .watered:
            Label("Arrosage effectué", systemImage: "checkmark.circle.fill").foregroundStyle(SproutStyle.green)
        }
    }

    private func changeMonth(by offset: Int) {
        guard let start = calendar.dateInterval(of: .month, for: visibleMonth)?.start,
              let next = calendar.date(byAdding: .month, value: offset, to: start) else { return }
        visibleMonth = next
        selectedDate = calendar.isDate(next, equalTo: today, toGranularity: .month) ? today : next
    }
}
