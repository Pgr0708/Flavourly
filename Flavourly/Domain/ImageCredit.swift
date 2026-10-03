import Foundation

/// Licence credit the server puts in a photo URL's fragment: "…jpg#credit=Photo%20by%20Asha%20on%20Pexels&credit_url=…".
/// Fragments are never sent when loading, so the image URL works as is.
struct ImageCredit: Equatable {
    let text: String
    let link: URL?

    init?(_ imageURL: String?) {
        guard let fragment = imageURL.flatMap({ URLComponents(string: $0)?.percentEncodedFragment }), !fragment.isEmpty else { return nil }
        var parts = URLComponents()
        parts.percentEncodedQuery = fragment
        let value = { (name: String) in parts.queryItems?.first { $0.name == name }?.value }
        guard let text = value("credit"), !text.isEmpty else { return nil }
        self.text = text
        link = value("credit_url").flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil }
    }
}
