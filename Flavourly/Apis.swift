//
//  Apis.swift
//  Flavourly
//
//  Backend endpoints. The OpenAI key lives ONLY on the server (backend/.env on Hostinger);
//  the app never sees it, so it can't be pulled out of the app and misused.
//

import Foundation

enum Apis {
    #if DEBUG
    /// The simulator reaches the Node server running on your Mac (`npm run dev` in /backend).
    static let baseURL = URL(string: "http://localhost:8080")!
    #else
    /// Production API on Hostinger behind Nginx + PM2 (see backend/README.md).
    static let baseURL = URL(string: "https://flavourly.dakshyaminfotech.store")!
    #endif

    static let registerDevice = "v1/devices"
    static let importLink = "v1/imports"
    static let extract = "v1/ai/extract"
    static let transcribe = "v1/ai/transcribe"
    static let plan = "v1/ai/plan"
    static let substitutes = "v1/ai/substitutes"
    static let cookNow = "v1/ai/cook-now"
    static let recipeImage = "v1/images/recipe"
    static let discover = "v1/discover"
    static let nutrition = "v1/nutrition"
    static let usage = "v1/usage"
    static let eraseDevice = "v1/devices/erase"
    
    static let SpoonacularApiKey = "092db8b96bf843e4b7667c71789eb071"
    static let USDAFoodDataApiKey  = "ouPsij2RjPb663CsGIQVIpxKPp5PnsCFNd9TIUcf"
}
