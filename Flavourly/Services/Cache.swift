import CryptoKit
import Kingfisher
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

/// Recipe photos via Kingfisher: one download per URL, memory + disk cache (30 days), downsampled
/// so lists never hold 12-megapixel bitmaps, retried once on a flaky network.
enum ImageCaching {
    static func configure() {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 80 << 20
        cache.diskStorage.config.sizeLimit = 300 << 20
        cache.diskStorage.config.expiration = .days(30)
        KingfisherManager.shared.downloader.downloadTimeout = 20
    }

    static func removeAll() {
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
    }
}

/// Remote photo with a placeholder while loading and a fallback view when it can't load.
struct RemoteImage<Placeholder: View, Failure: View>: View {
    let url: URL
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @State private var failed = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if failed {
                failure()
            } else {
                KFImage(url)
                    .placeholder { placeholder() }
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 700, height: 700)))
                    .scaleFactor(displayScale)
                    .cacheOriginalImage(false)
                    .retry(maxCount: 1, interval: .seconds(1))
                    .onFailure { _ in failed = true }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
            }
        }
        .onChange(of: url) { _, _ in failed = false }
    }
}
