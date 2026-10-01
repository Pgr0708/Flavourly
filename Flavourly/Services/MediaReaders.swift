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

    private static func extractAudio(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty, let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.noAudio
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try await export.export(to: output, as: .m4a)
        return output
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
