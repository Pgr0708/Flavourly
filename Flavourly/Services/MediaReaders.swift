import AVFoundation
import Speech
import UIKit
import Vision

/// On-device text recognition for cookbook pages, handwritten cards and screenshots.
enum TextRecognizer {
    static func lines(in images: [UIImage]) async throws -> [String] {
        var all: [String] = []
        for image in images {
            all += try await lines(in: image)
            all.append("")
        }
        return all
    }

    static func lines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                // Top-to-bottom reading order (Vision's origin is bottom-left).
                let sorted = observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                continuation.resume(returning: sorted.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// Transcribes a video or voice note the user chose from their own library — on device, nothing downloaded.
enum SpeechTranscriber {
    enum Failure: LocalizedError {
        case notAllowed, unavailable, noAudio, nothingHeard
        var errorDescription: String? {
            switch self {
            case .notAllowed: "Speech recognition is off for Flavourly. Turn it on in Settings › Privacy › Speech Recognition."
            case .unavailable: "Speech recognition isn't available for your language on this device."
            case .noAudio: "That video has no sound we can read."
            case .nothingHeard: "We couldn't hear a recipe in that video."
            }
        }
    }

    static func transcript(of mediaURL: URL) async throws -> String {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw Failure.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw Failure.unavailable }

        let audioURL = try await extractAudio(from: mediaURL)
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = true

        let text: String = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
        try? FileManager.default.removeItem(at: audioURL)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw Failure.nothingHeard }
        return text
    }

    /// The audio track only, as M4A, for Premium listening on the server (the video itself never leaves the phone).
    /// Longer than `maxMinutes` or bigger than `maxBytes` → only the start is sent, and `trimmed` says so.
    static func audioForUpload(of mediaURL: URL, maxMinutes: Double = 20, maxBytes: Int = 24_000_000) async throws -> (data: Data, trimmed: Bool) {
        let duration = try await AVURLAsset(url: mediaURL).load(.duration).seconds
        var seconds = min(duration, maxMinutes * 60)
        for _ in 0..<2 {
            let file = try await extractAudio(from: mediaURL, seconds: seconds)
            defer { try? FileManager.default.removeItem(at: file) }
            let data = try Data(contentsOf: file)
            if data.count <= maxBytes { return (data, seconds < duration - 1) }
            // ponytail: bitrate is the preset's; trim to fit instead of re-encoding at a lower bitrate.
            seconds *= Double(maxBytes) / Double(data.count) * 0.95
        }
        throw Failure.noAudio
    }

    private static func extractAudio(from url: URL, seconds: Double? = nil) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty, let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.noAudio
        }
        if let seconds { export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600)) }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try await export.export(to: output, as: .m4a)
        return output
    }
}

/// Text shown on screen in a video (ingredient overlays, captions burned into the picture) — on device, free.
enum VideoText {
    /// Samples up to `maxFrames` frames evenly (at least 2 s apart) and returns each distinct line once, in order.
    static func lines(in mediaURL: URL, maxFrames: Int = 40) async -> [String] {
        let asset = AVURLAsset(url: mediaURL)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }
        let step = max(2, duration / Double(maxFrames))
        let times = stride(from: min(1, duration / 2), to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var seen = Set<String>()
        var result: [String] = []
        for await frame in generator.images(for: times) {
            guard let image = try? frame.image,
                  let found = try? await TextRecognizer.lines(in: UIImage(cgImage: image)) else { continue }
            for line in found {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = clean.lowercased().filter { $0.isLetter || $0.isNumber }
                // Skip handles, tiny fragments and the same overlay seen on the next frame.
                guard key.count >= 3, !clean.hasPrefix("@"), seen.insert(key).inserted else { continue }
                result.append(clean)
            }
        }
        return result
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }

    /// JPEG sized for storage (keeps Core Data and iCloud light).
    func storageJPEG(maxSide: CGFloat = 1200) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
