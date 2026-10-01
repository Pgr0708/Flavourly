import CryptoKit
import SwiftUI
import UIKit

/// JSON cache for server answers: memory first, then disk (Caches/), each entry with its own expiry.
/// The same swap or Cook Now question comes back instantly, works offline and doesn't use a free credit.
@MainActor
final class ResponseCache {
    static let shared = ResponseCache()

    private struct Entry: Codable {
        let expires: Date
        let payload: Data
    }

    private let memory = NSCache<NSString, NSData>()
    private let folder: URL

    init(folder: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ResponseCache", isDirectory: true)) {
        self.folder = folder
        memory.countLimit = 300
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        prune()
    }

    /// Same path + same body (keys sorted) → same key.
    static func key<Body: Encodable>(_ path: String, _ body: Body) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(body)) ?? Data()
        return SHA256.hash(data: Data(path.utf8) + data).map { String(format: "%02x", $0) }.joined()
    }

    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        let data = (memory.object(forKey: key as NSString) as Data?) ?? (try? Data(contentsOf: file(key)))
        guard let data, let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        guard entry.expires > .now else {
            remove(key)
            return nil
        }
        memory.setObject(data as NSData, forKey: key as NSString)
        return try? JSONDecoder().decode(T.self, from: entry.payload)
    }

    func store<T: Encodable>(_ value: T, for key: String, ttl: TimeInterval) {
        guard let payload = try? JSONEncoder().encode(value),
              let data = try? JSONEncoder().encode(Entry(expires: .now.addingTimeInterval(ttl), payload: payload)) else { return }
        memory.setObject(data as NSData, forKey: key as NSString)
        try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ key: String) {
        memory.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: file(key))
    }

    func removeAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Drops files untouched for 30 days so the folder can't grow forever.
    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in files where ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(key + ".json") }
}

/// Recipe photos from the web: one download per URL (concurrent requests share it), kept in memory
/// for smooth scrolling and on disk via URLCache for offline use.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    init() { memory.totalCostLimit = 80 << 20 }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if let running = inflight[url] { return await running.value }
        let task = Task<UIImage?, Never> {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                  data.count < 15_000_000, let image = UIImage(data: data) else { return nil }
            // Large photos are shrunk once so lists don't hold 12-megapixel bitmaps.
            let longest = max(image.size.width, image.size.height)
            guard longest > 1400 else { return image }
            let scale = 1400 / longest
            return await image.byPreparingThumbnail(ofSize: CGSize(width: image.size.width * scale, height: image.size.height * scale)) ?? image
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }

    func removeAll() { memory.removeAllObjects() }
}

/// AsyncImage replacement backed by `ImageLoader`.
struct RemoteImage<Placeholder: View, Failure: View>: View {
    let url: URL
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image ?? ImageLoader.shared.cached(url) {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else if failed {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard ImageLoader.shared.cached(url) == nil else { return }
            let loaded = await ImageLoader.shared.image(for: url)
            withAnimation(Theme.gentle) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}
