//
//  ShareViewController.swift
//  FlavourlyShare
//
//  Receives a link or text from Instagram, TikTok, YouTube, Safari… and hands it to the app
//  through the shared App Group. Nothing is downloaded here; the app imports only public
//  captions/descriptions and linked recipe pages, and the user reviews before saving.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let appGroup = "group.com.bhavik.Flavourly"
    private static let inboxKey = "pendingShares"
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model) { [weak self] in self?.finish() })
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        Task { await collect() }
    }

    private func collect() async {
        guard let shared = await Self.sharedText(from: extensionContext?.inputItems as? [NSExtensionItem] ?? []) else {
            model.state = .failed("Nothing to import here — share a recipe link or text.")
            return
        }
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else {
            model.state = .failed("Flavourly couldn't open its inbox. Open the app and try again.")
            return
        }
        var inbox = defaults.stringArray(forKey: Self.inboxKey) ?? []
        if !inbox.contains(shared) { inbox.append(shared) }
        defaults.set(Array(inbox.suffix(10)), forKey: Self.inboxKey)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.state = .saved(Self.preview(of: shared))
        try? await Task.sleep(for: .seconds(2.2))
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Prefers a web link; falls back to shared text (captions often arrive as text with a link inside).
    private static func sharedText(from items: [NSExtensionItem]) async -> String? {
        var text: String?
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   url.scheme?.hasPrefix("http") == true {
                    return url.absoluteString
                }
                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    text = value
                }
            }
            if text == nil, let caption = item.attributedContentText?.string, !caption.isEmpty { text = caption }
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(20_000))
    }

    private static func preview(of shared: String) -> String {
        if let url = URL(string: shared), let host = url.host() { return host.replacingOccurrences(of: "www.", with: "") }
        return String(shared.prefix(60))
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State: Equatable { case saving, saved(String), failed(String) }
    @Published var state = State.saving
}

private struct ShareCard: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void

    private let green = Color(red: 0.08, green: 0.34, blue: 0.20)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(green.opacity(0.12)).frame(width: 64, height: 64)
                    switch model.state {
                    case .saving: ProgressView().tint(green)
                    case .saved: Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(green)
                    case .failed: Image(systemName: "exclamationmark").font(.system(size: 28, weight: .bold)).foregroundStyle(.orange)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.state)
                switch model.state {
                case .saving:
                    Text("Sending to Flavourly…").font(.system(size: 18, weight: .semibold, design: .serif))
                case .saved(let source):
                    Text("Sent to Flavourly").font(.system(size: 20, weight: .bold, design: .serif))
                    Text("Open Flavourly to review the recipe from \(source) before it's saved. Only the public caption and recipe link are used.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .failed(let message):
                    Text("Couldn't send").font(.system(size: 20, weight: .bold, design: .serif))
                    Text(message).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button(action: onClose) {
                    Text("Done").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(green, in: Capsule())
                }
            }
            .padding(24)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(12)
        }
    }
}
