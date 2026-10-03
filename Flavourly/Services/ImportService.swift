import Foundation
import UIKit
internal import Combine

/// Runs every import (link, text, photo, video) through the same legitimate pipeline:
/// public caption/description → recipe website → the user's own media → Review Import.
@MainActor
final class ImportService: ObservableObject {
    static let shared = ImportService()
    static let appGroup = "group.com.bhavik.Flavourly"

    enum Stage: Int, CaseIterable, Comparable {
        case opening, reading, matching, checking, done

        var label: String {
            switch self {
            case .opening: "Opening the source"
            case .reading: "Finding the recipe"
            case .matching: "Matching ingredients"
            case .checking: "Checking your household's allergies"
            case .done: "Ready to review"
            }
        }

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Failure: LocalizedError, Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let partial: RecipeDraft?
        var isLimit = false
        var errorDescription: String? { message }
    }

    @Published private(set) var stage: Stage = .opening
    @Published private(set) var detail = ""
    @Published private(set) var isRunning = false
    /// An import that finished after the user left the Importing screen.
    @Published var readyDraft: RecipeDraft?
    var readyImageData: Data?
    /// Set when the user taps "Keep browsing": progress moves to a Drop and the result to `readyDraft`.
    var continueInBackground = false

    // MARK: - Entry points

    func importLink(_ raw: String) async throws -> RecipeDraft {
        let checked = Validate.link(raw)
        guard let url = checked.url else {
            throw Failure(title: "That isn't a link we can import", message: checked.message ?? "Paste a full link, like https://instagram.com/reel/…", partial: nil)
        }
        // Recipe websites are read here on the iPhone (free); only AI reads count, and the server checks those.
        begin(detail: url.host() ?? "")
        defer { isRunning = false }

        var draft: RecipeDraft?
        var reason: String?
        if Self.isSocial(url) {
            advance(.reading, "Reading the public caption")
            do {
                let reply = try await AIService.importLink(url)
                draft = reply.recipe
                detail = reply.via.map { "Found in the \($0)" } ?? detail
            } catch {
                reason = try Self.explain(error)
            }
        } else if let html = await fetchHTML(url) {
            advance(.reading, "Looking for the recipe card")
            if let parsed = RecipeWebParser.parse(html: html, url: url), parsed.hasContent, !parsed.steps.isEmpty {
                draft = parsed
                detail = "\(parsed.ingredients.count) ingredients, \(parsed.steps.count) steps"
            } else {
                do {
                    draft = try await AIService.importLink(url, pageText: String(Self.visibleText(html).prefix(15_000))).recipe
                } catch {
                    reason = try Self.explain(error)
                    draft = RecipeWebParser.parse(html: html, url: url)
                }
            }
        } else {
            do { draft = try await AIService.importLink(url).recipe } catch { reason = try Self.explain(error) }
        }

        guard var result = draft, !result.title.isEmpty || !result.ingredients.isEmpty else {
            throw Failure(title: "We couldn't read that recipe",
                          message: reason ?? "The page didn't include a recipe we could read. Try pasting the text or adding a screenshot.",
                          partial: nil)
        }
        result.sourceURL = result.sourceURL ?? url.absoluteString
        result.sourceName = result.sourceName ?? Self.platformName(url)
        result.method = "link"
        if result.steps.isEmpty {
            await finalize(&result)
            throw Failure(title: "We found the ingredients, but not the steps",
                          message: "The method may be spoken in the video or hidden in comments. Your ingredients are kept — choose how to add the steps.",
                          partial: result)
        }
        await finalize(&result)
        if Self.isSocial(url) { Usage.record(.importRecipe) }
        return result
    }

    func importText(_ text: String, kind: String = "text", sourceURL: String? = nil) async throws -> RecipeDraft {
        let checked = Validate.pastedRecipe(String(text.prefix(Validate.Limit.pasted * 2)))
        guard checked.isValid || (kind != "text" && checked.value.count > Validate.Limit.pasted) else {
            throw Failure(title: "Not enough to go on", message: checked.message ?? "Paste the full recipe — ingredients and steps.", partial: nil)
        }
        let trimmed = String(checked.value.prefix(Validate.Limit.pasted))
        begin(detail: "\(trimmed.components(separatedBy: .newlines).count) lines")
        defer { isRunning = false }
        advance(.reading, "Reading your text")
        var draft = RecipeTextParser.parse(trimmed)
        let good = !draft.title.isEmpty && draft.ingredients.count >= 2 && !draft.steps.isEmpty
        if !good || kind != "text" {
            if let improved = try? await AIService.extract(text: trimmed, kind: kind, sourceURL: sourceURL), improved.hasContent {
                draft = improved
            }
        }
        guard draft.hasContent || !draft.ingredients.isEmpty else {
            throw Failure(title: "We couldn't find a recipe", message: "Try adding headings like \u{201C}Ingredients\u{201D} and \u{201C}Method\u{201D}.", partial: nil)
        }
        if draft.title.isEmpty { draft.title = "My recipe" }
        draft.sourceURL = draft.sourceURL ?? sourceURL
        draft.method = kind == "ocr" ? "scan" : kind
        await finalize(&draft)
        return draft
    }

    func importImages(_ images: [UIImage]) async throws -> RecipeDraft {
        guard !images.isEmpty else { throw Failure(title: "No photo", message: "Take or choose a photo of the recipe.", partial: nil) }
        begin(detail: "\(images.count) page\(images.count == 1 ? "" : "s")")
        advance(.reading, "Reading the text in your photo")
        let lines: [String]
        do {
            lines = try await TextRecognizer.lines(in: images)
        } catch {
            isRunning = false
            throw Failure(title: "We couldn't read that photo", message: "Try better light and hold the page flat.", partial: nil)
        }
        guard lines.filter({ !$0.isEmpty }).count >= 3 else {
            isRunning = false
            throw Failure(title: "No recipe text found", message: "Make sure the whole page is in the frame and in focus.", partial: nil)
        }
        return try await importText(lines.joined(separator: "\n"), kind: "ocr")
    }

    /// A video the user picked: what's said (Premium: the whole video on our server; otherwise on device)
    /// plus any recipe text shown on screen. Only the audio track is uploaded, never the video.
    func importVideo(_ url: URL) async throws -> RecipeDraft {
        let premium = SettingsManager.shared.isPremium
        begin(detail: premium ? "Listening to the whole video" : "Listening on your iPhone")
        advance(.reading, "Listening and reading on-screen text")
        async let onScreen = VideoText.lines(in: url)
        var spoken = "", trimmed = false
        var spokenError: Error?
        do {
            (spoken, trimmed) = try await listen(to: url, premium: premium)
        } catch {
            spokenError = error
        }
        let screen = await onScreen

        var parts: [String] = []
        if !spoken.isEmpty { parts.append("[What the cook says in the video]\n" + spoken) }
        if screen.count >= 3 { parts.append("[Text shown on screen in the video]\n" + screen.joined(separator: "\n")) }
        guard !parts.isEmpty else {
            isRunning = false
            throw Failure(title: "We couldn't hear a recipe",
                          message: spokenError?.localizedDescription ?? "We couldn't hear a recipe in that video.", partial: nil)
        }
        var draft = try await importText(parts.joined(separator: "\n\n"), kind: "transcript")
        if trimmed { draft.flags.append(ReviewFlag(field: "steps", message: "Long video: we listened to the first 20 minutes")) }
        return draft
    }

    private func listen(to url: URL, premium: Bool) async throws -> (String, Bool) {
        if premium {
            struct Reply: Decodable { let text: String }
            do {
                let audio = try await SpeechTranscriber.audioForUpload(of: url)
                let reply: Reply = try await APIClient.shared.upload(Apis.transcribe, data: audio.data, contentType: "audio/m4a")
                return (reply.text, audio.trimmed)
            } catch is APIError {
                // Offline, daily cap or server trouble: fall back to listening on the iPhone.
            }
        }
        return (try await SpeechTranscriber.transcript(of: url), false)
    }

    // MARK: - Share extension inbox

    /// Links/text shared into Flavourly from other apps, waiting for review.
    static func takePendingShares() -> [String] {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return [] }
        let items = defaults.stringArray(forKey: AppStorageKeys.pendingShares) ?? []
        defaults.removeObject(forKey: AppStorageKeys.pendingShares)
        return items
    }

    // MARK: - Checks shown on Review Import

    func finalize(_ draft: inout RecipeDraft) async {
        advance(.matching, "\(draft.ingredients.count) ingredients")
        var flags = draft.flags.filter { !$0.field.hasPrefix("allergen") }
        if draft.servings <= 0 {
            draft.servings = SettingsManager.shared.defaultServings
            flags.append(ReviewFlag(field: "servings", message: "Servings weren't listed — we guessed \(draft.servings)"))
        }
        if draft.minutes == 0 { flags.append(ReviewFlag(field: "time", message: "No cooking time given")) }
        for (index, item) in draft.ingredients.enumerated() where item.confidence < 1 {
            flags.append(ReviewFlag(field: "ingredient:\(index)", message: item.quantity == nil ? "Amount unclear" : "Please check this line"))
        }
        for (index, step) in draft.steps.enumerated() where step.confidence < 1 {
            flags.append(ReviewFlag(field: "step:\(index)", message: "Please check this step"))
        }

        advance(.checking, "")
        let profile = People.profile()
        for (index, item) in draft.ingredients.enumerated() {
            let result = FoodRules.check(ingredients: [item.text.isEmpty ? item.name : item.text], profile: profile)
            for issue in result.issues where issue.kind == .allergen || issue.kind == .diet {
                flags.append(ReviewFlag(field: "allergen:\(index)", message: issue.reason))
            }
        }
        if let duplicate = Kitchen.findDuplicate(of: draft) {
            let when = duplicate.createdAt?.formatted(.dateTime.month(.wide)) ?? "earlier"
            flags.append(ReviewFlag(field: "duplicate", message: "Similar to \u{201C}\(duplicate.displayTitle)\u{201D}, saved in \(when)"))
        }
        draft.flags = Array(NSOrderedSet(array: flags)) as? [ReviewFlag] ?? flags
        advance(.done, "")
    }

    // MARK: - Helpers

    private func begin(detail: String) {
        isRunning = true
        stage = .opening
        self.detail = detail
    }

    private func advance(_ stage: Stage, _ detail: String) {
        self.stage = stage
        if !detail.isEmpty { self.detail = detail }
        if continueInBackground {
            DropsManager.showProgress(id: "import", title: "Importing recipe", fraction: Double(stage.rawValue) / Double(Stage.done.rawValue),
                                      subtitle: stage.label)
        } else {
            Haptics.step()
        }
    }

    /// Hands a finished import to the root screen when the user left the Importing screen.
    func deliver(_ draft: RecipeDraft, imageData: Data?) {
        readyImageData = imageData
        readyDraft = draft
        continueInBackground = false
        DropsManager.showProgress(id: "import", title: "Recipe ready to review", fraction: 1, subtitle: draft.title)
        NotificationService.shared.notifyImportReady(title: draft.title)
    }

    /// Turns API failures into a sentence, rethrowing the free-limit case so the paywall sheet shows.
    private static func explain(_ error: Error) throws -> String {
        if case APIError.limit(let message) = error {
            Usage.exhaust(.importRecipe)
            throw Failure(title: "This week's AI imports are used", message: message, partial: nil, isLimit: true)
        }
        if case APIError.premiumRequired = error {
            throw Failure(title: "AI import is part of Premium",
                          message: "Instagram, TikTok and YouTube captions are read by AI. Recipe websites, typed recipes and clear scans still import free.",
                          partial: nil, isLimit: true)
        }
        return error.localizedDescription
    }

    private func fetchHTML(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 6_000_000 else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    static func visibleText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<(script|style|noscript|svg)[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<(br|p|li|h\d|div)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        return RecipeWebParser.clean(text.replacingOccurrences(of: "\n", with: " ⏎ "))?
            .replacingOccurrences(of: " ⏎ ", with: "\n") ?? ""
    }

    static func normalizedURL(_ raw: String) -> URL? { Validate.link(raw).url }

    enum Platform: String { case instagram = "Instagram", tiktok = "TikTok", youtube = "YouTube", pinterest = "Pinterest", facebook = "Facebook", web = "Website" }

    static func platform(of url: URL) -> Platform {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("instagram.com") { return .instagram }
        if host.contains("tiktok.com") { return .tiktok }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .youtube }
        if host.contains("pinterest.") || host.contains("pin.it") { return .pinterest }
        if host.contains("facebook.com") || host.contains("fb.watch") { return .facebook }
        return .web
    }

    static func isSocial(_ url: URL) -> Bool { platform(of: url) != .web }

    static func platformName(_ url: URL) -> String {
        let platform = platform(of: url)
        return platform == .web ? (url.host()?.replacingOccurrences(of: "www.", with: "") ?? "Website") : platform.rawValue
    }
}
