import PhotosUI
import SwiftUI
internal import Combine

/// The cook's own photo, kept only on this iPhone (Application Support/avatar.jpg).
@MainActor
final class ProfilePhoto: ObservableObject {
    static let shared = ProfilePhoto()
    @Published private(set) var image: UIImage?

    private let url = URL.applicationSupportDirectory.appending(path: "avatar.jpg")

    private init() {
        image = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
    }

    func set(_ data: Data?) {
        guard let data, let picked = UIImage(data: data) else {
            try? FileManager.default.removeItem(at: url)
            image = nil
            return
        }
        // A square 400 px crop is plenty for any avatar and keeps the file tiny.
        let side = min(picked.size.width, picked.size.height)
        let crop = CGRect(x: (picked.size.width - side) / 2, y: (picked.size.height - side) / 2, width: side, height: side)
        let small = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { _ in
            picked.draw(in: CGRect(x: -crop.minX * 400 / side, y: -crop.minY * 400 / side,
                                   width: picked.size.width * 400 / side, height: picked.size.height * 400 / side))
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? small.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
        image = small
    }
}

/// The cook's photo, or their initial when there's none.
struct ProfileAvatar: View {
    var size: CGFloat = 44
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var photo = ProfilePhoto.shared

    var body: some View {
        if let image = photo.image {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.line))
        } else {
            Avatar(initial: String(settings.displayName.prefix(1)).uppercased(), color: Theme.green, size: size)
        }
    }
}

/// You screen header: tap the photo to change it, tap the name to rename.
struct ProfileHeaderEditor: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var photo = ProfilePhoto.shared
    @State private var pick: PhotosPickerItem?
    @State private var showPicker = false
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                Button { showPicker = true } label: { Label("Choose photo", systemImage: "photo") }
                if photo.image != nil {
                    Button(role: .destructive) { photo.set(nil) } label: { Label("Remove photo", systemImage: "trash") }
                }
            } label: {
                ProfileAvatar(size: 72)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Theme.ink, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
            }
            .accessibilityLabel("Change profile photo")
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    draftName = settings.userName
                    renaming = true
                } label: {
                    HStack(spacing: 6) {
                        Text(settings.displayName).font(Theme.display(30)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                        Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit name, \(settings.displayName)")
                if settings.isPremium {
                    Badge(text: "Premium", systemImage: "crown.fill", tone: .gold)
                } else {
                    Text("Free plan").font(Theme.micro).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
        .photosPicker(isPresented: $showPicker, selection: $pick, matching: .images)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photo.set(data)
                    Haptics.select()
                }
                pick = nil
            }
        }
        .alert("Your name", isPresented: $renaming) {
            TextField("Name", text: $draftName).textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { settings.userName = String(draftName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }
        }
    }
}
