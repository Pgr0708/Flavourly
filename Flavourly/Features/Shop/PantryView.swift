import CoreData
import SwiftUI

/// Pushed from Home / Profile; the Shop tab shows the same content in its Pantry segment.
struct PantryView: View {
    @State private var showCook = false

    var body: some View {
        ScrollView {
            PantryContent { showCook = true }
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("Pantry")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showCook) { CookFromPantryView() }
    }
}

struct PantryContent: View {
    let onCook: () -> Void

    @EnvironmentObject private var settings: SettingsManager
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "expiresAt", ascending: true), NSSortDescriptor(key: "name", ascending: true)])
    private var items: FetchedResults<PantryItem>
    @State private var newItem = ""
    @State private var editing: PantryItem?
    @State private var adding = false
    @State private var scanning = false
    @State private var addError: String?
    @FocusState private var typing: Bool

    private var useSoon: [PantryItem] { items.filter { ($0.daysLeft ?? 99) <= 3 } }
    private var low: [PantryItem] { items.filter(\.isLow) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.pantry).font(.system(size: 20))
                TextField("Add what you have, e.g. 6 eggs", text: $newItem)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit(quickAdd)
                    .onChange(of: newItem) { _, _ in addError = nil }
                if !newItem.isEmpty {
                    Button("Add", action: quickAdd).font(.system(size: 14, weight: .semibold)).tint(Theme.pantry)
                } else {
                    Button {
                        Haptics.tick()
                        scanning = true
                    } label: {
                        Image(systemName: "barcode.viewfinder").font(.system(size: 20)).foregroundStyle(Theme.pantry)
                    }
                    .accessibilityLabel("Scan a product barcode")
                }
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(addError != nil ? Theme.allergen : (typing ? Theme.pantry : Theme.line)))
            FieldError(message: addError)

            if items.isEmpty {
                EmptyStateView(imageName: nil, systemImage: "cabinet", title: "Nothing in your pantry yet",
                               message: "Add what you have and we'll suggest recipes that use it up — and remind you before things go off.")
            } else {
                if !useSoon.isEmpty { useSoonCard }
                ForEach(PantryLocation.allCases) { location in
                    let group = items.filter { $0.locationKind == location }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Label("\(location.label) · \(group.count)", systemImage: location.symbol)
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink2).padding(.bottom, 6)
                            ForEach(group) { item in PantryRow(item: item) { editing = item } }
                        }
                        .card(padding: 14)
                    }
                }
                if !low.isEmpty {
                    PrimaryButton(title: "Add \(low.count) running-low item\(low.count == 1 ? "" : "s") to your list", systemImage: "basket", tone: .soft, height: 48) {
                        for item in low {
                            Kitchen.addManualItem(item.displayName)
                            item.isLow = false
                        }
                        Kitchen.save()
                        DropsManager.showSuccess(title: "Added to your grocery list")
                    }
                }
                PrimaryButton(title: "What can I cook with this?", systemImage: "flame.fill", tone: .flame, action: onCook)
            }
        }
        .sheet(item: $editing) { PantryItemSheet(item: $0).environmentObject(settings) }
        .sheet(isPresented: $adding) { PantryItemSheet(item: nil).environmentObject(settings) }
        .sheet(isPresented: $scanning) { BarcodeScanSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .addPantryItem)) { _ in adding = true }
    }

    private var useSoonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Use soon", systemImage: "clock.badge.exclamationmark.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.capture)
                Spacer()
                Button("Cook with these", action: onCook).font(.system(size: 13, weight: .semibold)).tint(Theme.capture)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(useSoon) { item in
                        HStack(spacing: 6) {
                            IngredientIcon(name: item.name ?? "", size: 24)
                            Text(item.displayName).font(.system(size: 13, weight: .semibold))
                            Text(item.expiryText ?? "").font(Theme.micro).foregroundStyle((item.daysLeft ?? 9) <= 0 ? Theme.allergen : Theme.capture)
                        }
                        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 5)
                        .background(.white, in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(Theme.captureSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func quickAdd() {
        let checked = Validate.itemName(newItem)
        guard checked.isValid else {
            withAnimation(Theme.snappy) { addError = checked.message }
            Haptics.error()
            return
        }
        let text = checked.value
        let parsed = IngredientParser.parse(text)
        let name = parsed.name.isEmpty ? text : parsed.name
        let item = Kitchen.addPantry(name: name.capitalizedFirst, quantity: parsed.quantity, unit: parsed.unit)
        newItem = ""
        Haptics.success()
        DropsManager.showSuccess(title: "Added \(item.displayName)",
                                 subtitle: [item.locationKind.label, item.expiryText.map { "use within \($0)" }].compactMap { $0 }.joined(separator: " · "))
    }
}

private struct PantryRow: View {
    @ObservedObject var item: PantryItem
    let onEdit: () -> Void
    @EnvironmentObject private var settings: SettingsManager

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                IngredientIcon(name: item.name ?? "", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    if item.quantity > 0 {
                        Text(Amount.text(quantity: item.quantity, unit: item.unit ?? "", system: settings.unitSystem))
                            .font(Theme.micro).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 4)
                if item.isLow { Badge(text: "Low", tone: .amber) }
                if let expiry = item.expiryText {
                    let days = item.daysLeft ?? 99
                    Badge(text: expiry, tone: days <= 0 ? .red : (days <= 3 ? .orange : .neutral))
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                item.isLow.toggle()
                Kitchen.save()
                Haptics.toggle()
            } label: { Label(item.isLow ? "Not running low" : "Running low", systemImage: "gauge.with.dots.needle.33percent") }
            Button {
                Kitchen.addManualItem(item.displayName)
                DropsManager.showSuccess(title: "Added to your grocery list", subtitle: item.displayName)
            } label: { Label("Add to grocery list", systemImage: "basket") }
            Button(role: .destructive) {
                let name = item.displayName
                Kitchen.context.delete(item)
                Kitchen.save()
                NotificationService.shared.reschedule()
                Haptics.destructive()
                DropsManager.showInfo(title: "\(name) used up")
            } label: { Label("Used up", systemImage: "checkmark.circle") }
        }
    }
}

/// Add or edit one pantry item.
struct PantryItemSheet: View {
    let item: PantryItem?

    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = ""
    @State private var unit = ""
    @State private var location = PantryLocation.cupboard
    @State private var hasExpiry = false
    @State private var expires = Date.now
    @State private var isLow = false
    @State private var didLoad = false
    @State private var showErrors = false

    private var nameCheck: FieldCheck { Validate.itemName(name) }
    private var amountCheck: (value: Double?, message: String?) { Validate.quantity(quantity) }

    private let units = ["", "g", "kg", "ml", "l", "tsp", "tbsp", "cup", "oz", "lb", "pack", "portion"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $name)
                            .onChange(of: name) { _, value in
                                guard item == nil else { return }
                                location = Kitchen.defaultLocation(for: value)
                                if let date = Kitchen.defaultExpiry(for: value) { hasExpiry = true; expires = date }
                            }
                        FieldError(message: showErrors || !name.isEmpty ? nameCheck.message : nil)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Amount", text: $quantity).keyboardType(.decimalPad)
                            Picker("Unit", selection: $unit) {
                                ForEach(units, id: \.self) { Text($0.isEmpty ? "items" : $0).tag($0) }
                            }
                            .labelsHidden()
                        }
                        FieldError(message: amountCheck.message)
                    }
                }
                Section("Kept in") {
                    Picker("Location", selection: $location) {
                        ForEach(PantryLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Has a use-by date", isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker("Use by", selection: $expires, in: Calendar.current.startOfDay(for: .now).addingTimeInterval(-86_400 * 30)...,
                                   displayedComponents: .date)
                    }
                    Toggle("Running low", isOn: $isLow)
                } footer: {
                    Text("We remind you the morning something needs using, and suggest recipes for it.")
                }
                if let item {
                    Section {
                        Button("Used up — remove", role: .destructive) {
                            Kitchen.context.delete(item)
                            Kitchen.save()
                            NotificationService.shared.reschedule()
                            Haptics.destructive()
                            dismiss()
                        }
                    }
                }
            }
            .tint(Theme.pantry)
            .navigationTitle(item == nil ? "Add to pantry" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).bold()
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad, let item else { didLoad = true; return }
        didLoad = true
        name = item.name ?? ""
        quantity = item.quantity > 0 ? Amount.format(item.quantity, unit: item.unit ?? "", system: settings.unitSystem) : ""
        unit = item.unit ?? ""
        location = item.locationKind
        hasExpiry = item.expiresAt != nil
        expires = item.expiresAt ?? .now
        isLow = item.isLow
    }

    private func save() {
        guard nameCheck.isValid, amountCheck.message == nil else {
            withAnimation(Theme.snappy) { showErrors = true }
            Haptics.error()
            DropsManager.showError(title: "Please fix this first", subtitle: nameCheck.message ?? amountCheck.message)
            return
        }
        let amount = amountCheck.value
        let trimmed = nameCheck.value
        if let item {
            item.name = trimmed
            item.quantity = amount ?? 0
            item.unit = unit
            item.location = location.rawValue
            item.expiresAt = hasExpiry ? expires : nil
            item.isLow = isLow
            item.updatedAt = .now
            Kitchen.save()
            NotificationService.shared.reschedule()
        } else {
            let saved = Kitchen.addPantry(name: trimmed, quantity: amount, unit: unit, location: location, expires: hasExpiry ? expires : nil)
            if !hasExpiry { saved.expiresAt = nil }
            saved.isLow = isLow
            Kitchen.save()
        }
        Haptics.success()
        DropsManager.showSuccess(title: item == nil ? "Added to pantry" : "Saved", subtitle: trimmed)
        dismiss()
    }
}
