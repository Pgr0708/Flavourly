import CoreData
import SwiftUI

/// Lets Home ask the Shop tab to open "Cook from pantry" even before the tab was first shown.
@MainActor
enum ShopIntent {
    static var openCookFromPantry = false
}

struct ShopView: View {
    @Binding var sheet: RootSheet?

    enum Segment: String, CaseIterable, Identifiable {
        case grocery = "Grocery list", pantry = "Pantry"
        var id: String { rawValue }
    }

    @State private var segment = Segment.grocery
    @State private var showCookFromPantry = false
    @Namespace private var pill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Shop").font(Theme.pageTitle).foregroundStyle(Theme.ink)
                    Spacer()
                    IconButton(systemImage: "plus", label: segment == .grocery ? "Add grocery items" : "Add to pantry", style: .bordered) {
                        if segment == .grocery { sheet = .groceryAdd } else { NotificationCenter.default.post(name: .addPantryItem, object: nil) }
                    }
                }
                segmentPicker
                switch segment {
                case .grocery: GroceryListContent()
                case .pantry: PantryContent { showCookFromPantry = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .dockSpacing()
        .canvasBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showCookFromPantry) { CookFromPantryView() }
        .onAppear(perform: consumeIntent)
        .onReceive(NotificationCenter.default.publisher(for: .openCookFromPantry)) { _ in consumeIntent() }
    }

    private var segmentPicker: some View {
        HStack(spacing: 4) {
            ForEach(Segment.allCases) { item in
                Button {
                    Haptics.select()
                    withAnimation(Theme.snappy) { segment = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(segment == item ? .white : Theme.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if segment == item {
                                Capsule().fill(Theme.greenGradient).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(segment == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.chip, in: Capsule())
    }

    private func consumeIntent() {
        guard ShopIntent.openCookFromPantry else { return }
        ShopIntent.openCookFromPantry = false
        segment = .pantry
        showCookFromPantry = true
    }
}

extension Notification.Name {
    static let addPantryItem = Notification.Name("flavourly.addPantryItem")
}

// MARK: - Grocery list

private struct GroceryListContent: View {
    @EnvironmentObject private var settings: SettingsManager
    // Observed so the list rebuilds whenever the plan, pantry or ticks change.
    @FetchRequest(sortDescriptors: []) private var meals: FetchedResults<PlannedMeal>
    @FetchRequest(sortDescriptors: []) private var pantry: FetchedResults<PantryItem>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)]) private var rows: FetchedResults<GroceryItem>

    @State private var nextWeek = false
    @State private var byRecipe = false
    @State private var newItem = ""
    @State private var why: GroceryLine?
    @State private var showHave = false
    @State private var celebrate = false
    @State private var addError: String?
    @FocusState private var typing: Bool

    private var weekStart: Date {
        let start = Kitchen.weekStart()
        return nextWeek ? Kitchen.calendar.date(byAdding: .day, value: 7, to: start) ?? start : start
    }

    private var lines: [GroceryLine] {
        _ = meals.count + pantry.count
        return Kitchen.groceryLines(weekStart: weekStart, system: settings.unitSystem)
    }

    private var state: [String: GroceryItem] {
        Dictionary(rows.filter { !$0.isManual && $0.weekStart == weekStart }.map { ($0.key ?? "", $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var manual: [GroceryItem] { rows.filter(\.isManual) }

    var body: some View {
        let all = lines
        let rowState = state
        let active = all.filter { !$0.coveredByPantry && !$0.isStaple && !(rowState[$0.key]?.isHidden ?? false) }
        let have = all.filter { $0.coveredByPantry || $0.isStaple }
        let hidden = all.filter { rowState[$0.key]?.isHidden ?? false }
        let total = active.count + manual.count
        let done = active.filter { rowState[$0.key]?.isChecked ?? false }.count + manual.filter(\.isChecked).count

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Week", selection: $nextWeek) {
                    Text("This week").tag(false)
                    Text("Next week").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
                Menu {
                    Picker("Group by", selection: $byRecipe) {
                        Label("Aisle", systemImage: "cart").tag(false)
                        Label("Recipe", systemImage: "book").tag(true)
                    }
                    ShareLink(item: shareText(active: active, state: rowState)) { Label("Share list", systemImage: "square.and.arrow.up") }
                    if manual.contains(where: \.isChecked) {
                        Button(role: .destructive) {
                            Kitchen.clearCheckedManualItems()
                            Haptics.destructive()
                        } label: { Label("Clear ticked extras", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 22)).foregroundStyle(Theme.ink2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("List options")
            }

            progressCard(done: done, total: total)

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.green).font(.system(size: 20))
                TextField("Add an item, e.g. 2 lemons", text: $newItem)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                    .onChange(of: newItem) { _, _ in addError = nil }
                if !newItem.isEmpty { Button("Add", action: addItem).font(.system(size: 14, weight: .semibold)).tint(Theme.green) }
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(addError != nil ? Theme.allergen : (typing ? Theme.green : Theme.line)))
            FieldError(message: addError)

            if total == 0 && have.isEmpty {
                EmptyStateView(imageName: nil, systemImage: "basket", title: "Your list is empty",
                               message: "Plan a few meals and their ingredients appear here, merged and sorted by aisle.")
            }

            if byRecipe {
                recipeSections(active, state: rowState)
            } else {
                aisleSections(active, state: rowState)
            }

            if !have.isEmpty {
                DisclosureGroup(isExpanded: $showHave) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(have) { line in
                            HStack {
                                Text(line.name).font(.system(size: 14))
                                Spacer()
                                Text(line.isStaple ? "Staple" : "In pantry").font(Theme.micro).foregroundStyle(Theme.pantry)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Already have · \(have.count)", systemImage: "checkmark.seal.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.pantry)
                }
                .tint(Theme.pantry)
                .card(padding: 14)
            }

            if !hidden.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REMOVED FROM LIST").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                    ForEach(hidden) { line in
                        HStack {
                            Text(line.name).font(.system(size: 14)).foregroundStyle(Theme.muted).strikethrough()
                            Spacer()
                            Button("Restore") {
                                if let row = rowState[line.key] { row.isHidden = false }
                                Kitchen.save()
                                Haptics.tick()
                            }
                            .font(.system(size: 13, weight: .semibold)).tint(Theme.green)
                        }
                    }
                }
                .card(padding: 14)
            }

            if done > 0 {
                PrimaryButton(title: "Move \(done) bought item\(done == 1 ? "" : "s") to pantry", systemImage: "cabinet.fill", tone: .soft, height: 48) {
                    moveToPantry(active, state: rowState)
                }
            }
        }
        .overlay { if celebrate { ConfettiView().allowsHitTesting(false) } }
        .sheet(item: $why) { line in WhyAmountSheet(line: line).environmentObject(settings) }
        .onChange(of: done) { old, new in
            guard new == total, total > 0, old < new else { return }
            Haptics.success()
            DropsManager.showSuccess(title: "List complete!", subtitle: "Move everything to your pantry when you're home")
            celebrate = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { celebrate = false }
        }
    }

    private func progressCard(done: Int, total: Int) -> some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(total == 0 ? "Nothing to buy" : "\(done) of \(total) in the basket").font(.system(size: 15, weight: .semibold))
                    .contentTransition(.numericText())
                Spacer()
                Text("\(Int(fraction * 100))%").font(Theme.rounded(17)).foregroundStyle(Theme.green)
                    .contentTransition(.numericText())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.greenGradient).frame(width: max(8, geometry.size.width * fraction))
                }
            }
            .frame(height: 8)
            .animation(Theme.spring, value: fraction)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func aisleSections(_ active: [GroceryLine], state: [String: GroceryItem]) -> some View {
        let groups = Dictionary(grouping: active, by: \.aisle)
        let manualGroups = Dictionary(grouping: manual) { Aisle(rawValue: $0.aisle ?? "") ?? .other }
        ForEach(Aisle.allCases.filter { groups[$0] != nil || manualGroups[$0] != nil }, id: \.self) { aisle in
            VStack(alignment: .leading, spacing: 0) {
                Label(aisle.rawValue, systemImage: aisle.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink2)
                    .padding(.bottom, 6)
                ForEach(groups[aisle] ?? []) { line in lineRow(line, state: state) }
                ForEach(manualGroups[aisle] ?? []) { item in manualRow(item) }
            }
            .card(padding: 14)
        }
    }

    @ViewBuilder
    private func recipeSections(_ active: [GroceryLine], state: [String: GroceryItem]) -> some View {
        let recipes = Array(NSOrderedSet(array: active.flatMap { $0.sources.map(\.recipe) })) as? [String] ?? []
        ForEach(recipes, id: \.self) { title in
            VStack(alignment: .leading, spacing: 0) {
                Label(title, systemImage: "book.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink2).padding(.bottom, 6)
                ForEach(active.filter { $0.sources.contains { $0.recipe == title } }) { line in
                    lineRow(line, state: state, amount: line.sources.first { $0.recipe == title }?.amount)
                }
            }
            .card(padding: 14)
        }
        if !manual.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Label("Added by you", systemImage: "hand.point.up.left.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink2).padding(.bottom, 6)
                ForEach(manual) { item in manualRow(item) }
            }
            .card(padding: 14)
        }
    }

    private func lineRow(_ line: GroceryLine, state: [String: GroceryItem], amount: String? = nil) -> some View {
        let checked = state[line.key]?.isChecked ?? false
        let buy = amount ?? Amount.text(quantity: line.toBuy, unit: line.unit, system: settings.unitSystem)
        return HStack(spacing: 12) {
            Button {
                toggle(line)
            } label: {
                HStack(spacing: 12) {
                    CheckCircle(isOn: checked)
                    IngredientIcon(name: line.name, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name).font(.system(size: 15, weight: .medium)).strikethrough(checked)
                            .foregroundStyle(checked ? Theme.muted : Theme.ink)
                        if line.inPantry, let pantryQuantity = line.pantryQuantity, pantryQuantity > 0 {
                            Text("You have \(Amount.text(quantity: pantryQuantity, unit: line.unit, system: settings.unitSystem))")
                                .font(Theme.micro).foregroundStyle(Theme.pantry)
                        } else if line.sources.count > 1 {
                            Text("For \(line.sources.count) meals").font(Theme.micro).foregroundStyle(Theme.muted)
                        } else if let source = line.sources.first {
                            Text(source.recipe).font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(buy).font(Theme.rounded(14, .semibold).monospacedDigit()).foregroundStyle(checked ? Theme.muted : Theme.ink2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tick()
                why = line
            } label: {
                Image(systemName: "info.circle").foregroundStyle(Theme.muted)
            }
            .accessibilityLabel("Why this amount of \(line.name)")
        }
        .padding(.vertical, 7)
        .contextMenu {
            Button {
                Kitchen.addPantry(name: line.name)
                DropsManager.showSuccess(title: "Marked as in your pantry", subtitle: line.name)
            } label: { Label("I already have it", systemImage: "cabinet") }
            Button(role: .destructive) {
                let row = Kitchen.stateRow(key: line.key, weekStart: weekStart)
                row.name = line.name
                row.isHidden = true
                Kitchen.save()
                Haptics.destructive()
            } label: { Label("Remove from list", systemImage: "minus.circle") }
        }
    }

    private func manualRow(_ item: GroceryItem) -> some View {
        Button {
            Haptics.tick()
            item.isChecked.toggle()
            Kitchen.save()
        } label: {
            HStack(spacing: 12) {
                CheckCircle(isOn: item.isChecked)
                IngredientIcon(name: item.name ?? "", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).font(.system(size: 15, weight: .medium)).strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? Theme.muted : Theme.ink)
                    Text("Added by you").font(Theme.micro).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if item.quantity > 0 {
                    Text(Amount.text(quantity: item.quantity, unit: item.unit ?? "", system: settings.unitSystem))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Haptics.destructive()
                Kitchen.context.delete(item)
                Kitchen.save()
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Actions

    private func toggle(_ line: GroceryLine) {
        let row = Kitchen.stateRow(key: line.key, weekStart: weekStart)
        row.name = line.name
        row.isChecked.toggle()
        row.isChecked ? Haptics.tick() : Haptics.step()
        Kitchen.save()
    }

    private func addItem() {
        let checked = Validate.items(newItem)
        if let message = checked.message {
            withAnimation(Theme.snappy) { addError = message }
            Haptics.error()
            return
        }
        let added = checked.items.compactMap { Kitchen.addManualItem($0) }
        newItem = ""
        guard !added.isEmpty else { return }
        Haptics.success()
        DropsManager.showSuccess(title: added.count == 1 ? "Added \(added[0].displayName)" : "Added \(added.count) items")
    }

    private func moveToPantry(_ active: [GroceryLine], state: [String: GroceryItem]) {
        var moved = 0
        for line in active where state[line.key]?.isChecked ?? false {
            Kitchen.addPantry(name: line.name, quantity: line.toBuy, unit: line.unit)
            if let row = state[line.key] { row.isChecked = false }
            moved += 1
        }
        for item in manual where item.isChecked {
            Kitchen.addPantry(name: item.displayName, quantity: item.quantity > 0 ? item.quantity : nil, unit: item.unit ?? "")
            moved += 1
        }
        Kitchen.clearCheckedManualItems()
        Haptics.success()
        DropsManager.showSuccess(title: "Moved \(moved) item\(moved == 1 ? "" : "s") to your pantry", subtitle: "Expiry dates were estimated — tap to change")
    }

    private func shareText(active: [GroceryLine], state: [String: GroceryItem]) -> String {
        var text = "Shopping list — Flavourly\n"
        let groups = Dictionary(grouping: active.filter { !(state[$0.key]?.isChecked ?? false) }, by: \.aisle)
        for aisle in Aisle.allCases {
            let items = (groups[aisle] ?? []).map { "☐ \($0.name) — \(Amount.text(quantity: $0.toBuy, unit: $0.unit, system: settings.unitSystem))" }
                + manual.filter { !$0.isChecked && ($0.aisle ?? "") == aisle.rawValue }.map { "☐ \($0.displayName)" }
            guard !items.isEmpty else { continue }
            text += "\n\(aisle.rawValue)\n" + items.joined(separator: "\n") + "\n"
        }
        return text
    }
}

// MARK: - Why this amount

private struct WhyAmountSheet: View {
    let line: GroceryLine
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: line.name, subtitle: "Why this amount") { dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(line.sources, id: \.self) { source in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.recipe).font(.system(size: 15, weight: .medium))
                            Text(source.when.capitalizedFirst).font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(source.amount.isEmpty ? "some" : source.amount).font(.system(size: 14, weight: .semibold))
                    }
                }
                Divider()
                row("Total needed", Amount.text(quantity: line.quantity, unit: line.unit, system: settings.unitSystem))
                if let have = line.pantryQuantity, have > 0 {
                    row("In your pantry", "− " + Amount.text(quantity: have, unit: line.unit, system: settings.unitSystem), tint: Theme.pantry)
                }
                row("To buy", Amount.text(quantity: line.toBuy, unit: line.unit, system: settings.unitSystem), bold: true)
            }
            .card(padding: 16)
            Text("Amounts are scaled to each meal's servings (plus any planned leftovers) and merged across recipes, converting units where it's safe to.")
                .font(Theme.micro).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(20)
        .canvasBackground()
        .presentationDetents([.medium])
    }

    private func row(_ title: String, _ value: String, tint: Color = Theme.ink, bold: Bool = false) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: bold ? .bold : .regular))
            Spacer()
            Text(value.isEmpty ? "—" : value).font(.system(size: 15, weight: bold ? .bold : .semibold)).foregroundStyle(tint)
        }
    }
}

// MARK: - Quick add

struct GroceryQuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var added: [String] = []
    @State private var error: String?
    @FocusState private var focused: Bool

    private let common = ["Milk", "Eggs", "Bread", "Bananas", "Onions", "Tomatoes", "Rice", "Yogurt", "Chicken", "Pasta", "Butter", "Lemons", "Spinach", "Paneer"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "Add to grocery list", subtitle: "One per line, or separate with commas") { dismiss() }
                TextField("e.g. 2 lemons, 500 g paneer", text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focused)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(error != nil ? Theme.allergen : (focused ? Theme.green : Theme.line)))
                    .onChange(of: text) { _, _ in error = nil }
                FieldError(message: error)
                Text("QUICK ADD").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                FlowLayout(spacing: 8) {
                    ForEach(common, id: \.self) { item in
                        Chip(title: item, systemImage: added.contains(item) ? "checkmark" : "plus", isOn: added.contains(item), style: .green, small: true) {
                            guard !added.contains(item) else { return }
                            Kitchen.addManualItem(item)
                            withAnimation(Theme.snappy) { added.append(item) }
                        }
                    }
                }
                Spacer()
                PrimaryButton(title: "Add to list", systemImage: "basket.fill",
                              isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { addAll() }
            }
            .padding(20)
            .canvasBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
        .onDisappear {
            if !added.isEmpty { DropsManager.showSuccess(title: "Added \(added.count) item\(added.count == 1 ? "" : "s") to your list") }
        }
    }

    private func addAll() {
        let checked = Validate.items(text)
        if let message = checked.message {
            withAnimation(Theme.snappy) { error = message }
            Haptics.error()
            return
        }
        let items = checked.items.compactMap { Kitchen.addManualItem($0)?.displayName }
        added += items
        text = ""
        Haptics.success()
        dismiss()
    }
}
