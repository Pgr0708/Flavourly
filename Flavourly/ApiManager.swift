//
//  ApiManager.swift
//  Flavourly
//
//  Talks to the Flavourly backend with an anonymous device token (no login).
//

import Foundation
import Security
import RevenueCat

enum APIError: LocalizedError, Equatable {
    case offline
    case unauthorized
    case limit(String)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline or the Flavourly server can't be reached."
        case .unauthorized: "Your device session expired. Please try again."
        case .limit(let message): message
        case .server(let message): message
        case .invalidResponse: "The server sent something unexpected."
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Survives reinstalls (Keychain) so free-plan limits can't be reset by deleting the app.
    var installID: String {
        if let id = Keychain.read("installID") { return id }
        let id = UUID().uuidString
        Keychain.write(id, for: "installID")
        return id
    }

    private var token: String? {
        get { Keychain.read("deviceToken") }
        set { if let newValue { Keychain.write(newValue, for: "deviceToken") } else { Keychain.delete("deviceToken") } }
    }

    func post<Body: Encodable, Reply: Decodable>(_ path: String, _ body: Body, as: Reply.Type = Reply.self) async throws -> Reply {
        try await ensureDevice()
        do {
            return try await send(path, body: body)
        } catch APIError.unauthorized {
            token = nil
            try await ensureDevice()
            return try await send(path, body: body)
        }
    }

    func eraseRemoteData() async {
        struct Empty: Codable {}
        _ = try? await post(Apis.eraseDevice, Empty(), as: Empty.self)
        token = nil
    }

    private func ensureDevice() async throws {
        guard token == nil else { return }
        struct Body: Encodable { let installID: String; let platform: String; let appVersion: String }
        struct Reply: Decodable { let token: String }
        let reply: Reply = try await send(
            Apis.registerDevice, body: Body(installID: installID, platform: "ios", appVersion: AppInfo.version), authorized: false
        )
        token = reply.token
    }

    private func send<Body: Encodable, Reply: Decodable>(_ path: String, body: Body, authorized: Bool = true) async throws -> Reply {
        var request = URLRequest(url: Apis.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.version, forHTTPHeaderField: "X-App-Version")
        if authorized, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if hasRevenueCatAPIKey, Purchases.isConfigured {
            // The server confirms Premium with RevenueCat itself; this only says which customer to check.
            request.setValue(Purchases.shared.appUserID, forHTTPHeaderField: "X-RC-App-User")
        }
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            do { return try decoder.decode(Reply.self, from: data) } catch { throw APIError.invalidResponse }
        case 401:
            throw APIError.unauthorized
        case 402, 429:
            throw APIError.limit(message(from: data) ?? "You've reached this week's free limit.")
        default:
            throw APIError.server(message(from: data) ?? "Something went wrong on our side (\(http.statusCode)).")
        }
    }

    private func message(from data: Data) -> String? {
        struct Failure: Decodable { let error: String? }
        return (try? decoder.decode(Failure.self, from: data))?.error
    }
}

/// Tiny Keychain wrapper for the device secret and install id.
enum Keychain {
    private static let service = "com.bhavik.Flavourly"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for key: String) {
        delete(key)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

/// Free-plan counters mirrored on the device (the server is the source of truth).
enum Feature: String, CaseIterable, Codable {
    case importRecipe, aiPlan, aiIdeas, aiSwap

    var weeklyFree: Int {
        switch self {
        case .importRecipe: 5
        case .aiPlan: 1
        case .aiIdeas: 5
        case .aiSwap: 10
        }
    }

    var label: String {
        switch self {
        case .importRecipe: "imports"
        case .aiPlan: "AI plans"
        case .aiIdeas: "AI recipe ideas"
        case .aiSwap: "AI swaps"
        }
    }
}

@MainActor
enum Usage {
    private static var weekKey: String { ISO8601DateFormatter().string(from: Kitchen.weekStart()) }

    private static var ledger: [String: [String: Int]] {
        get {
            guard let data = UserDefaults.standard.data(forKey: AppStorageKeys.usageLedger) else { return [:] }
            return (try? JSONDecoder().decode([String: [String: Int]].self, from: data)) ?? [:]
        }
        set {
            // Keep only this week so the ledger never grows.
            let trimmed = newValue.filter { $0.key == weekKey }
            UserDefaults.standard.set(try? JSONEncoder().encode(trimmed), forKey: AppStorageKeys.usageLedger)
        }
    }

    static func used(_ feature: Feature) -> Int { ledger[weekKey]?[feature.rawValue] ?? 0 }

    static func remaining(_ feature: Feature) -> Int {
        SettingsManager.shared.isPremium ? .max : max(0, feature.weeklyFree - used(feature))
    }

    static func canUse(_ feature: Feature) -> Bool { remaining(feature) > 0 }

    static func record(_ feature: Feature) {
        var all = ledger
        all[weekKey, default: [:]][feature.rawValue, default: 0] += 1
        ledger = all
    }

    /// The server said the limit is reached; stop offering it this week.
    static func exhaust(_ feature: Feature) {
        var all = ledger
        all[weekKey, default: [:]][feature.rawValue] = feature.weeklyFree
        ledger = all
    }

    static var resetDate: Date {
        Kitchen.calendar.date(byAdding: .day, value: 7, to: Kitchen.weekStart()) ?? .now
    }
}
