import SwiftUI
import Vision
import VisionKit

/// Pantry › Scan: camera (VisionKit) or typed barcode → Open Food Facts → allergy check → add to pantry.
struct BarcodeScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var codeError: String?
    @State private var product: FoodProduct?
    @State private var problem: String?
    @State private var loading = false
    @State private var lastScanned: String?

    private var cameraWorks: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if cameraWorks, product == nil {
                        BarcodeCamera { scanned in
                            guard scanned != lastScanned else { return }
                            lastScanned = scanned
                            code = scanned
                            lookUp()
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 2).padding(40))
                        .accessibilityLabel("Camera. Point it at a barcode.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(cameraWorks ? "OR TYPE THE NUMBER" : "BARCODE NUMBER").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                        HStack(spacing: 10) {
                            Image(systemName: "barcode").foregroundStyle(Theme.pantry)
                            TextField("e.g. 8901063010321", text: $code)
                                .keyboardType(.numberPad)
                                .onChange(of: code) { _, _ in codeError = nil }
                            Button("Look up", action: lookUp).font(.system(size: 14, weight: .semibold)).tint(Theme.pantry).disabled(code.isEmpty || loading)
                        }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(codeError != nil ? Theme.allergen : Theme.line))
                        FieldError(message: codeError)
                    }

                    if loading {
                        HStack(spacing: 10) { ProgressView(); Text("Looking it up…").font(Theme.caption).foregroundStyle(Theme.ink2) }
                    }
                    if let problem {
                        Label(problem, systemImage: "questionmark.circle").font(Theme.caption).foregroundStyle(Theme.ink2).card(padding: 14)
                    }
                    if let product { result(product) }

                    Text("Product data from Open Food Facts (openfoodfacts.org), shared under the Open Database License. Always check the pack for allergens.")
                        .font(Theme.micro).foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Scan a product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func result(_ product: FoodProduct) -> some View {
        let check = FoodRules.check(ingredients: product.checkLines, profile: People.profile())
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let link = product.imageURL, let url = URL(string: link) {
                        RemoteImage(url: url) { Theme.chip.shimmering() } failure: { Image(systemName: "shippingbox").font(.largeTitle).foregroundStyle(Theme.muted) }
                    } else {
                        Image(systemName: "shippingbox").font(.largeTitle).foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 84, height: 84)
                .background(Theme.chip)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName).font(Theme.heading(17, .demiBold)).foregroundStyle(Theme.ink)
                    if let quantity = product.quantity, !quantity.isEmpty { Text(quantity).font(Theme.caption).foregroundStyle(Theme.muted) }
                    if let grade = product.nutriScore { Badge(text: "Nutri-Score \(grade)", tone: ["A", "B"].contains(grade) ? .teal : grade == "C" ? .amber : .red) }
                }
            }
            if check.allergenIssues.isEmpty {
                Label(product.allergens.isEmpty ? "No allergens listed — fits everyone's rules" : "Contains \(product.allergens.joined(separator: ", ")) — fine for your household",
                      systemImage: "checkmark.shield.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(check.allergenIssues) { issue in
                        Label(issue.reason, systemImage: issue.severity == .blocked ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#8E2219"))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.allergenSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            PrimaryButton(title: "Add to pantry", systemImage: "plus", tone: .flame) {
                let item = Kitchen.addPantry(name: product.displayName)
                DropsManager.showSuccess(title: "Added to your pantry", subtitle: item.displayName)
                dismiss()
            }
            Button("Scan another") {
                withAnimation(Theme.snappy) { self.product = nil; code = ""; lastScanned = nil }
            }
            .font(.system(size: 14, weight: .semibold)).tint(Theme.pantry).frame(maxWidth: .infinity)
        }
        .card()
    }

    private func lookUp() {
        let check = Validate.barcode(code)
        guard check.value != nil else {
            withAnimation(Theme.snappy) { codeError = check.message }
            Haptics.error()
            return
        }
        loading = true
        problem = nil
        Task {
            defer { loading = false }
            do {
                let found = try await OpenFoodFacts.product(barcode: code)
                withAnimation(Theme.spring) { product = found }
                Haptics.success()
            } catch {
                withAnimation(Theme.snappy) { problem = error.localizedDescription }
                Haptics.warning()
            }
        }
    }
}

/// VisionKit's live barcode scanner; reports each new code once.
private struct BarcodeCamera: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .itf14])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    Haptics.tick()
                    onCode(value)
                    return
                }
            }
        }
    }
}
