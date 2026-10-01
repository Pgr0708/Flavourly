import Charts
import CoreData
import SwiftUI

/// Meal tracking for "me": today against targets, the week at a glance, and Apple Health.
struct NutritionView: View {
    @EnvironmentObject private var settings: SettingsManager
    @FetchRequest private var logs: FetchedResults<MealLog>
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var showLog = false

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _logs = FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)],
                             predicate: NSPredicate(format: "date >= %@ AND memberID == %@", start as NSDate, Person.meID))
    }

    private var week: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: .now)) }
    }

    private func entries(on date: Date) -> [MealLog] {
        logs.filter { Calendar.current.isDate($0.date ?? .distantPast, inSameDayAs: date) }
    }

    var body: some View {
        let me = People.me()
        let today = entries(on: day)
        let calories = today.reduce(0) { $0 + $1.calories }
        let protein = today.reduce(0) { $0 + $1.protein }
        let carbs = today.reduce(0) { $0 + $1.carbs }
        let fat = today.reduce(0) { $0 + $1.fat }
        let goals = settings.customizationPreferences.notes

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dayPicker
                HStack(spacing: 18) {
                    MacroRing(protein: protein, carbs: carbs, fat: fat) {
                        VStack(spacing: 0) {
                            Text("\(Int(calories))").font(Theme.rounded(28)).contentTransition(.numericText())
                            Text(me.calorieTarget > 0 ? "of \(me.calorieTarget) kcal" : "kcal").font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 132, height: 132)
                    VStack(alignment: .leading, spacing: 12) {
                        macro("Protein", protein, Double(me.proteinTarget), Theme.green)
                        macro("Carbs", carbs, Double(goals["carbs"].flatMap(Int.init) ?? 0), Theme.premium)
                        macro("Fat", fat, Double(goals["fat"].flatMap(Int.init) ?? 0), Color(hex: "#E45AC6"))
                    }
                }
                .card()
                .animation(Theme.spring, value: calories)

                weekChart(target: me.calorieTarget)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(Calendar.current.isDateInToday(day) ? "Today's meals" : day.formatted(.dateTime.weekday(.wide))).font(Theme.section)
                        Spacer()
                        Button {
                            Haptics.primary()
                            showLog = true
                        } label: {
                            Label("Log", systemImage: "plus").font(.system(size: 14, weight: .semibold))
                        }
                        .tint(Theme.green)
                    }
                    if today.isEmpty {
                        Text("Nothing logged. Finish a cook, or tap Log to add a meal.").font(Theme.caption).foregroundStyle(Theme.muted)
                            .padding(.vertical, 8)
                    }
                    ForEach(today) { entry in logRow(entry) }
                }
                .card()

                NavigationLink(value: Route.healthConnect) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "heart.fill", tint: Theme.allergen, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                            Text(HealthService.shared.isConnected ? "Logged meals are sent to Health" : "Send logged meals to Health")
                                .font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
                NavigationLink("Change daily targets", value: Route.preferences).font(.system(size: 14, weight: .semibold)).tint(Theme.green)
                Text("Estimates from recipe ingredients — a guide, not medical advice.").font(Theme.micro).foregroundStyle(Theme.muted)
            }
            .padding(20)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLog) { LogMealSheet(day: day) }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(week, id: \.self) { date in
                let isOn = Calendar.current.isDate(date, inSameDayAs: day)
                Button {
                    Haptics.select()
                    withAnimation(Theme.snappy) { day = date }
                } label: {
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 11, weight: .semibold))
                        Text(date.formatted(.dateTime.day())).font(.system(size: 16, weight: .bold))
                        Circle().fill(entries(on: date).isEmpty ? .clear : (isOn ? .white : Theme.capture)).frame(width: 5, height: 5)
                    }
                    .foregroundStyle(isOn ? .white : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(isOn ? AnyShapeStyle(Theme.greenGradient) : AnyShapeStyle(Color.white),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.94))
            }
        }
    }

    private func macro(_ title: String, _ value: Double, _ goal: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(goal > 0 ? "\(Int(value)) / \(Int(goal)) g" : "\(Int(value)) g").font(.system(size: 13, weight: .semibold))
            }
            if goal > 0 { ProgressView(value: min(value / goal, 1)).tint(tint) }
        }
    }

    private func weekChart(target: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week").font(Theme.section)
            Chart {
                ForEach(week, id: \.self) { date in
                    BarMark(x: .value("Day", date, unit: .day),
                            y: .value("Calories", entries(on: date).reduce(0) { $0 + $1.calories }))
                        .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: day) ? Theme.green : Theme.leaf.opacity(0.55))
                        .cornerRadius(6)
                }
                if target > 0 {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Theme.capture)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Target").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.capture)
                        }
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 150)
        }
        .card()
    }

    private func logRow(_ entry: MealLog) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: (MealSlot(rawValue: entry.slot ?? "") ?? .dinner).symbol, tint: Theme.capture, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? "Meal").font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text("\(Int(entry.calories)) kcal · \(Int(entry.protein)) g protein\(entry.syncedToHealth ? " · in Health" : "")")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                Kitchen.context.delete(entry)
                Kitchen.save()
                Haptics.destructive()
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

private struct LogMealSheet: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var calories = ""
    @State private var slot = MealSlot.at(hour: Calendar.current.component(.hour, from: .now))

    private var titleCheck: FieldCheck { Validate.required(title, field: "Meal", max: 80) }
    private var calorieCheck: (value: Int?, message: String?) { Validate.integer(calories, field: "Calories", range: 0...5000) }

    var body: some View {
        NavigationStack {
            Form {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("What did you eat?", text: $title)
                    if !title.isEmpty { FieldError(message: titleCheck.message) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Calories (kcal)", text: $calories).keyboardType(.numberPad)
                    FieldError(message: calorieCheck.message)
                }
                Picker("Meal", selection: $slot) {
                    ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
                }
            }
            .tint(Theme.green)
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let date = Calendar.current.isDateInToday(day) ? Date.now : day.addingTimeInterval(12 * 3600)
                        Kitchen.log(recipe: nil, title: titleCheck.value, slot: slot, date: date, calories: Double(calorieCheck.value ?? 0))
                        Haptics.success()
                        DropsManager.showSuccess(title: "Logged", subtitle: titleCheck.value)
                        dismiss()
                    }
                    .bold()
                    .disabled(!titleCheck.isValid || calorieCheck.message != nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Apple Health

struct HealthConnectView: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.openURL) private var openURL
    @State private var working = false
    @State private var refresh = 0

    private var health: HealthService { HealthService.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(LinearGradient(colors: [Color(hex: "#FF6B8B"), Color(hex: "#E0245E")], startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .symbolEffect(.bounce, value: refresh)
                    Text("Apple Health").font(Theme.display(30))
                    Text("Send the meals you log to Health, so your nutrition sits next to your activity.")
                        .font(Theme.caption).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Dietary energy, protein, carbohydrates and fat", systemImage: "arrow.up.heart.fill")
                    Label("Only for meals you log or finish cooking", systemImage: "checkmark.circle.fill")
                    Label("We never read your Health data", systemImage: "lock.fill")
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .card(padding: 16)

                let _ = refresh
                if !health.isAvailable {
                    Text("Health isn't available on this device.").font(Theme.caption).foregroundStyle(Theme.muted)
                } else if health.isDenied {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Access is turned off").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.check)
                        Text("Open the Health app › Profile › Apps › Flavourly and allow the four nutrition types.")
                            .font(Theme.caption).foregroundStyle(Theme.ink2)
                        PrimaryButton(title: "Open Settings", systemImage: "gear", tone: .outline, height: 46) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    .padding(14)
                    .background(Theme.checkSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if health.isConnected || settings.healthSyncEnabled {
                    ToggleRow(title: "Send logged meals to Health", subtitle: "You can turn this off any time",
                              systemImage: "heart.fill", tint: Theme.allergen, isOn: $settings.healthSyncEnabled)
                        .card(padding: 8)
                } else {
                    PrimaryButton(title: "Connect Apple Health", systemImage: "heart.fill", tone: .dark, isLoading: working) {
                        working = true
                        Task {
                            let granted = await health.requestAccess()
                            working = false
                            refresh += 1
                            granted ? DropsManager.showSuccess(title: "Connected to Apple Health")
                                    : DropsManager.showWarning(title: "Not connected", subtitle: "You can allow it later in the Health app")
                        }
                    }
                }
            }
            .padding(20)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}
