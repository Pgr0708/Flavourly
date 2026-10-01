import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

enum ImportStart: String, CaseIterable, Identifiable {
    case link, photo, text, video

    var id: String { rawValue }
    var title: String {
        switch self {
        case .link: "Link"
        case .photo: "Photo"
        case .text: "Text"
        case .video: "Video"
        }
    }
    var symbol: String {
        switch self {
        case .link: "link"
        case .photo: "camera.viewfinder"
        case .text: "text.alignleft"
        case .video: "play.rectangle"
        }
    }
}

/// Add a recipe from a link, a photo, pasted text or the user's own video.
/// Only public captions/descriptions and linked recipe pages are read — never videos or comments.
struct ImportView: View {
    @State var start: ImportStart

    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var importer = ImportService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var phase = Phase.input
    @State private var link = ""
    @State private var text = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var showPaywall = false
    @State private var showEditor = false
    /// Ingredients found without steps; the next import fills in the method.
    @State private var partial: RecipeDraft?
    @State private var review: ReviewItem?
    @FocusState private var typing: Bool

    enum Phase: Equatable {
        case input, importing
        case failed(ImportService.Failure)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.input, .input), (.importing, .importing): true
            case let (.failed(a), .failed(b)): a.id == b.id
            default: false
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHeader(title: "Add a recipe", subtitle: "From anywhere — you check it before it's saved") {
                        if phase == .importing { keepBrowsing() } else { dismiss() }
                    }
                    switch phase {
                    case .input:
                        tabs
                        if let partial { partialBanner(partial) }
                        content.transition(.opacity)
                    case .importing:
                        ImportingPanel(importer: importer) { keepBrowsing() }
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    case .failed(let failure):
                        failureCard(failure).transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(20)
                .animation(Theme.spring, value: phase)
                .animation(Theme.snappy, value: start)
            }
            .scrollDismissesKeyboard(.interactively)
            .canvasBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(phase == .importing)
        .sheet(isPresented: $showPaywall) { PaywallScreenView().environmentObject(settings) }
        .sheet(isPresented: $showEditor) { NavigationStack { RecipeEditorView(recipe: nil) }.environmentObject(settings) }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { scanned in
                images = Array((images + scanned).prefix(8))
                if !scanned.isEmpty { Haptics.success() }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $review) { item in
            ImportReviewView(draft: item.draft, imageData: item.imageData) { saved in
                review = nil
                if saved != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                }
            }
            .environmentObject(settings)
        }
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .onChange(of: videoItem) { _, item in loadVideo(item) }
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(ImportStart.allCases) { item in
                Button {
                    Haptics.select()
                    typing = false
                    start = item
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold))
                        Text(item.title).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(start == item ? .white : Theme.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(start == item ? AnyShapeStyle(Theme.greenGradient) : AnyShapeStyle(Color.white),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(start == item ? .clear : Theme.line))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityAddTraits(start == item ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch start {
        case .link: linkTab
        case .photo: photoTab
        case .text: textTab
        case .video: videoTab
        }
    }

    private var linkTab: some View {
        let checked = Validate.link(link)
        let url = checked.url
        let remaining = Usage.remaining(.importRecipe)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(Theme.muted)
                TextField("Paste a recipe or video link", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.go)
                    .onSubmit { if url != nil { importLink() } }
                if link.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        link = strings.first ?? ""
                        Haptics.tick()
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.green)
                } else {
                    Button { link = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                        .accessibilityLabel("Clear link")
                }
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(!link.isEmpty && url == nil ? Theme.allergen : (typing ? Theme.green : Theme.line), lineWidth: typing || (!link.isEmpty && url == nil) ? 1.5 : 1))

            if let url {
                Label("\(ImportService.platformName(url)) link", systemImage: "checkmark.circle.fill")
                    .font(Theme.micro.weight(.semibold)).foregroundStyle(Theme.green)
            } else if !link.isEmpty {
                FieldError(message: checked.message)
            }

            FlowLayout(spacing: 6) {
                ForEach(["Instagram", "TikTok", "YouTube", "Pinterest", "Facebook", "Recipe websites"], id: \.self) {
                    Badge(text: $0, tone: .neutral)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                howRow(1, "Reads the public caption or video description")
                howRow(2, "Follows the creator's recipe link when there is one")
                howRow(3, "You check amounts and allergens before saving")
                Text("We never download videos or read comments. Private posts can't be imported.")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
            }
            .card(padding: 14)

            Label("Faster: tap Share in Instagram, TikTok or Safari and choose Flavourly.", systemImage: "square.and.arrow.up")
                .font(Theme.micro).foregroundStyle(Theme.ink2)

            if !settings.isPremium {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(remaining) of \(Feature.importRecipe.weeklyFree) free link imports left this week").font(Theme.micro.weight(.semibold))
                        Spacer()
                        Button("Unlimited") { showPaywall = true }.font(Theme.micro.weight(.bold)).tint(Theme.premiumDeep)
                    }
                    ProgressView(value: Double(remaining), total: Double(Feature.importRecipe.weeklyFree)).tint(Theme.premium)
                    Text("Photo, text and video imports are always free.").font(Theme.micro).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .background(Theme.premiumSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            PrimaryButton(title: "Import recipe", systemImage: "arrow.down.circle.fill", isEnabled: url != nil) { importLink() }
            writeItButton
        }
    }

    private var photoTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if VNDocumentCameraViewController.isSupported {
                sourceCard(symbol: "camera.viewfinder", title: "Scan a cookbook page", subtitle: "Auto-crops and straightens each page", tint: Theme.capture) {
                    showScanner = true
                }
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                sourceCardLabel(symbol: "photo.on.rectangle.angled", title: "Choose photos or screenshots",
                                subtitle: "Up to 8 — e.g. the ingredients and the method", tint: Theme.pantry)
            }
            .buttonStyle(PressableStyle(scale: 0.98))

            if !images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(images.indices, id: \.self) { index in
                            Image(uiImage: images[index])
                                .resizable().scaledToFill()
                                .frame(width: 84, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        Haptics.destructive()
                                        withAnimation(Theme.snappy) { _ = images.remove(at: index) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, Color.black.opacity(0.6))
                                    }
                                    .padding(4)
                                    .accessibilityLabel("Remove page \(index + 1)")
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Label("Photos stay on your iPhone — only the text we read is used.", systemImage: "lock.fill")
                .font(Theme.micro).foregroundStyle(Theme.muted)
            PrimaryButton(title: images.isEmpty ? "Read photos" : "Read \(images.count) photo\(images.count == 1 ? "" : "s")",
                          systemImage: "text.viewfinder", isEnabled: !images.isEmpty) {
                let pages = images
                run { try await importer.importImages(pages) }
            }
            writeItButton
        }
    }

    private var textTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($typing)
                    .font(Theme.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(10)
                if text.isEmpty {
                    Text("Paste or type a recipe — the name, ingredients and steps. Notes, captions and emails work too.")
                        .font(Theme.body).foregroundStyle(Theme.muted).padding(16).allowsHitTesting(false)
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(typing ? Theme.green : Theme.line, lineWidth: typing ? 1.5 : 1))
            let pasted = Validate.pastedRecipe(text)
            HStack {
                PasteButton(payloadType: String.self) { strings in
                    text = strings.joined(separator: "\n")
                    Haptics.tick()
                }
                .tint(Theme.green)
                Spacer()
                CharacterCount(count: pasted.value.count, limit: Validate.Limit.pasted)
                if !text.isEmpty { Button("Clear") { text = "" }.font(.system(size: 14, weight: .semibold)).tint(Theme.muted) }
            }
            if !text.isEmpty { FieldError(message: pasted.message) }
            PrimaryButton(title: "Import text", systemImage: "arrow.down.circle.fill", isEnabled: pasted.isValid) {
                let body = pasted.value
                run { try await importer.importText(body) }
            }
            writeItButton
        }
    }

    private var videoTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $videoItem, matching: .videos) {
                sourceCardLabel(symbol: "video.badge.waveform", title: "Choose a video from your library",
                                subtitle: "A cooking video you recorded or saved", tint: Theme.plan)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            VStack(alignment: .leading, spacing: 10) {
                howRow(1, "We listen to the audio on your iPhone")
                howRow(2, "The spoken steps become a written recipe")
                howRow(3, "You check it before it's saved")
                Text("Use videos you own or have saved yourself. For Instagram or TikTok, share the link instead.")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
            }
            .card(padding: 14)
            writeItButton
        }
    }

    private var writeItButton: some View {
        Button {
            Haptics.tick()
            showEditor = true
        } label: {
            Label("Or write it yourself", systemImage: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .tint(Theme.green)
        .padding(.top, 2)
    }

    // MARK: Pieces

    private func howRow(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.green)
                .frame(width: 24, height: 24)
                .background(Theme.greenSoft, in: Circle())
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.ink)
        }
    }

    private func sourceCard(symbol: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.primary()
            action()
        } label: {
            sourceCardLabel(symbol: symbol, title: title, subtitle: subtitle, tint: tint)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private func sourceCardLabel(symbol: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            IconTile(systemImage: symbol, tint: tint, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.rowTitle).foregroundStyle(Theme.ink)
                Text(subtitle).font(Theme.micro).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .card(padding: 14)
    }

    private func partialBanner(_ draft: RecipeDraft) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(Theme.pantry)
            VStack(alignment: .leading, spacing: 2) {
                Text("Adding the method to \u{201C}\(draft.title)\u{201D}").font(.system(size: 14, weight: .semibold))
                Text("We kept its \(draft.ingredients.count) ingredients. Import the steps any way below.")
                    .font(Theme.micro).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(Theme.snappy) { partial = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .accessibilityLabel("Stop adding to this recipe")
        }
        .padding(12)
        .background(Theme.pantrySoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func failureCard(_ failure: ImportService.Failure) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(systemImage: failure.isLimit ? "crown.fill" : (failure.partial != nil ? "list.bullet.clipboard" : "exclamationmark.triangle.fill"),
                         tint: failure.isLimit ? Theme.premiumDeep : (failure.partial != nil ? Theme.pantry : Theme.check), size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(failure.title).font(Theme.rowTitle)
                    Text(failure.message).font(Theme.caption).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            if failure.isLimit {
                Text("Resets \(Usage.resetDate.formatted(.dateTime.weekday(.wide))). Scanning, pasting and videos stay free.")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
                PrimaryButton(title: "Get unlimited imports", systemImage: "crown.fill", tone: .premium) { showPaywall = true }
                PrimaryButton(title: "Scan or paste instead", systemImage: "camera.viewfinder", tone: .outline) { restart(.photo) }
            } else if let found = failure.partial {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(found.ingredients.prefix(4)) { Text("• " + $0.displayLine).font(Theme.micro).foregroundStyle(Theme.ink2) }
                    if found.ingredients.count > 4 { Text("+ \(found.ingredients.count - 4) more").font(Theme.micro).foregroundStyle(Theme.muted) }
                }
                .card(padding: 12)
                PrimaryButton(title: "Add a screenshot of the steps", systemImage: "camera.viewfinder") {
                    partial = found
                    restart(.photo)
                }
                PrimaryButton(title: "Paste the steps", systemImage: "doc.on.clipboard", tone: .outline) {
                    partial = found
                    restart(.text)
                }
                PrimaryButton(title: "Use a video I saved", systemImage: "video.badge.waveform", tone: .outline) {
                    partial = found
                    restart(.video)
                }
                Button("Review what we found") { review = ReviewItem(draft: found, imageData: nil) }
                    .font(.system(size: 14, weight: .semibold)).tint(Theme.green).frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: "Try again", systemImage: "arrow.clockwise") { restart(start) }
                PrimaryButton(title: "Paste the text instead", systemImage: "doc.on.clipboard", tone: .outline) { restart(.text) }
            }
        }
        .card(padding: 16)
    }

    // MARK: Actions

    private func importLink() {
        guard Usage.canUse(.importRecipe) else {
            Haptics.warning()
            phase = .failed(.init(title: "Free imports used",
                                  message: "You've used this week's \(Feature.importRecipe.weeklyFree) free link imports.", partial: nil, isLimit: true))
            return
        }
        let raw = link
        run { try await importer.importLink(raw) }
    }

    private func run(_ work: @escaping () async throws -> RecipeDraft) {
        typing = false
        importer.continueInBackground = false
        phase = .importing
        Task {
            do {
                var draft = try await work()
                if var base = partial, base.steps.isEmpty, !draft.steps.isEmpty {
                    base.steps = draft.steps
                    base.flags = base.flags.filter { !$0.field.hasPrefix("step") } + draft.flags.filter { $0.field.hasPrefix("step") }
                    draft = base
                }
                if importer.continueInBackground {
                    importer.deliver(draft, imageData: nil)
                    return
                }
                partial = nil
                Haptics.success()
                phase = .input
                review = ReviewItem(draft: draft, imageData: nil)
            } catch let failure as ImportService.Failure {
                if importer.continueInBackground {
                    importer.continueInBackground = false
                    if let found = failure.partial {
                        importer.deliver(found, imageData: nil)
                    } else {
                        DropsManager.endProgress(id: "import")
                        DropsManager.showError(title: failure.title, subtitle: failure.message)
                    }
                    return
                }
                failure.isLimit ? Haptics.warning() : Haptics.error()
                phase = .failed(failure)
            } catch {
                if importer.continueInBackground {
                    importer.continueInBackground = false
                    DropsManager.endProgress(id: "import")
                    DropsManager.showError(title: "Import failed", subtitle: error.localizedDescription)
                    return
                }
                Haptics.error()
                phase = .failed(.init(title: "Import failed", message: error.localizedDescription, partial: nil))
            }
        }
    }

    private func keepBrowsing() {
        importer.continueInBackground = true
        DropsManager.showProgress(id: "import", title: "Importing recipe",
                                  fraction: Double(importer.stage.rawValue) / Double(ImportService.Stage.done.rawValue),
                                  subtitle: "We'll tell you when it's ready")
        dismiss()
    }

    private func restart(_ tab: ImportStart) {
        Haptics.tick()
        start = tab
        phase = .input
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { loaded.append(image) }
            }
            photoItems = []
            withAnimation(Theme.snappy) { images = Array((images + loaded).prefix(8)) }
            if loaded.count < items.count { DropsManager.showWarning(title: "Some photos couldn't be opened") }
        }
    }

    private func loadVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        videoItem = nil
        run {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                throw ImportService.Failure(title: "Couldn't open that video", message: "Try another video from your library.", partial: nil)
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            return try await ImportService.shared.importVideo(movie.url)
        }
    }
}

// MARK: - Importing

private struct ImportingPanel: View {
    @ObservedObject var importer: ImportService
    let onKeepBrowsing: () -> Void
    @State private var spin = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(AngularGradient(colors: [Theme.leaf, Theme.green, Theme.ai, Theme.leaf], center: .center), lineWidth: 5)
                    .frame(width: 86, height: 86)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.6).repeatForever(autoreverses: false), value: spin)
                Image(systemName: "fork.knife")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .padding(.top, 10)
            VStack(spacing: 4) {
                Text("Importing your recipe").font(Theme.display(27))
                Text(importer.detail.isEmpty ? " " : importer.detail).font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    .contentTransition(.opacity)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ImportService.Stage.allCases.filter { $0 != .done }, id: \.self) { stage in
                    HStack(spacing: 12) {
                        Group {
                            if importer.stage > stage {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).transition(.scale)
                            } else if importer.stage == stage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "circle").foregroundStyle(Theme.line)
                            }
                        }
                        .frame(width: 22)
                        Text(stage.label)
                            .font(.system(size: 15, weight: importer.stage == stage ? .semibold : .regular))
                            .foregroundStyle(importer.stage >= stage ? Theme.ink : Theme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
            .animation(Theme.spring, value: importer.stage)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12).fill(Theme.hairline).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.hairline).frame(height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.hairline).frame(width: 140, height: 10)
                }
            }
            .shimmering()
            .card(padding: 12)
            .accessibilityHidden(true)

            Button(action: onKeepBrowsing) {
                Label("Keep browsing — we'll tell you when it's ready", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .tint(Theme.green)
        }
        .onAppear { spin = true }
    }
}

// MARK: - Media helpers

/// A video picked from Photos, copied to a temporary file we own.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// VisionKit's page scanner: auto-crops and straightens cookbook pages.
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            DropsManager.showError(title: "The scanner stopped", subtitle: error.localizedDescription)
            parent.dismiss()
        }
    }
}
