//
//  Apis.swift
//  Flavourly
//
//  Backend endpoints. The OpenAI key lives ONLY on the server (backend/.env on Hostinger);
//  the app never sees it, so it can't be pulled out of the app and misused.
//

import Foundation

enum Apis {
    /// Production API on Hostinger behind Nginx + PM2 (see backend/README.md) — Debug builds too, so the
    /// simulator shows real data. To use the Node server on your Mac (`npm run dev` in /backend), add the
    /// launch argument `-localAPI` (Xcode › Edit Scheme › Run › Arguments).
    static let baseURL: URL = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-localAPI") { return URL(string: "http://localhost:8080")! }
        #endif
        return URL(string: "https://flavourly.dakshyaminfotech.store")!
    }()

    static let registerDevice = "v1/devices"
    static let importLink = "v1/imports"
    static let extract = "v1/ai/extract"
    static let transcribe = "v1/ai/transcribe"
    static let plan = "v1/ai/plan"
    static let substitutes = "v1/ai/substitutes"
    static let cookNow = "v1/ai/cook-now"
    static let recipeImage = "v1/images/recipe"
    static let discover = "v1/discover"
    static let regions = "v1/discover/regions"
    static let dishSuggest = "v1/dishes/suggest"
    static let dishFind = "v1/dishes/find"
    static let videos = "v1/videos"
    static let variations = "v1/variations"
    static let variationsNearby = "v1/variations/list"
    static let variationTried = "v1/variations/tried"
    static let nutrition = "v1/nutrition"
    static let usage = "v1/usage"
    static let eraseDevice = "v1/devices/erase"

}
