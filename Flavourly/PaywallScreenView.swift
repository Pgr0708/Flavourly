import SwiftUI
import WebKit
import RevenueCat

private struct PremiumBenefit {
    let symbol: String
    let title: String
    let detail: String
    let color: Color
}

private enum LegalPage: String, Identifiable {
    case terms, privacy

    var id: String { rawValue }
    var title: String { self == .terms ? "Terms & Conditions" : "Privacy Policy" }
    var url: URL? {
        URL(string: self == .terms ? AppInfo.termsURLString : AppInfo.privacyURLString)
    }
}

struct PaywallScreenView: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProViewModel()
    @State private var legalPage: LegalPage?
    @State private var showingMessage = false

    private let gold = Color(hex: "#FFD674")
    private let benefits: [PremiumBenefit] = [
        .init(symbol: "doc.text.fill", title: "AI imports & Make it my way", detail: "Instagram, TikTok, YouTube — or remix any dish", color: Color(hex: "#F9C34E")),
        .init(symbol: "wand.and.stars", title: "AI meal plans", detail: "Personalized to your goals & preferences", color: Color(hex: "#A7DD65")),
        .init(symbol: "cart.fill", title: "Smart grocery lists", detail: "Organized, flexible and budget-friendly", color: Color(hex: "#F6A65A")),
        .init(symbol: "heart.text.square.fill", title: "Nutrition tracking", detail: "Make healthier choices with ease", color: Color(hex: "#F07480")),
        .init(symbol: "cabinet.fill", title: "Pantry & leftover tools", detail: "Reduce food waste and save money", color: Color(hex: "#C8A3E2")),
        .init(symbol: "person.2.fill", title: "Family sharing", detail: "Share plans, lists and recipes", color: Color(hex: "#82BCF7"))
    ]

    private var showsTrial: Bool {
        if !viewModel.isConfigured { return viewModel.selectedPlan == .yearly }
        return viewModel.package(for: viewModel.selectedPlan)?
            .storeProduct.introductoryDiscount?.paymentMode == .freeTrial
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("PaywallBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay(.black.opacity(0.34))
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            settings.hasSeenPaywall = true
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .accessibilityLabel("Close paywall")
                        Spacer()
                    }
                    .padding(.horizontal, 19)
                    .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 16) {
                            VStack(spacing: 6) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(gold)
                                    .shadow(color: gold.opacity(0.8), radius: 12)
                                Text("Unlock Premium")
                                    .font(.system(size: 38, weight: .bold, design: .serif))
                                    .foregroundStyle(Color(hex: "#FFE6A6"))
                                    .minimumScaleFactor(0.75)
                                    .lineLimit(1)
                                Text("Cook smarter, plan better, and save more\ntime every week.")
                                    .font(.system(size: 16, design: .serif))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 2)

                            VStack(spacing: 0) {
                                ForEach(benefits.indices, id: \.self) { index in
                                    let benefit = benefits[index]
                                    HStack(spacing: 13) {
                                        Image(systemName: benefit.symbol)
                                            .font(.system(size: 20))
                                            .foregroundStyle(benefit.color)
                                            .frame(width: 42, height: 42)
                                            .background(benefit.color.opacity(0.18), in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(benefit.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text(benefit.detail)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.white.opacity(0.77))
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11))
                                            .foregroundStyle(gold.opacity(0.8))
                                    }
                                    .frame(minHeight: 62)
                                    if index < benefits.count - 1 {
                                        Rectangle()
                                            .fill(.white.opacity(0.12))
                                            .frame(height: 1)
                                    }
                                }
                            }
                            .padding(.horizontal, 15)
                            .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 22))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22)
                                    .strokeBorder(gold.opacity(0.36), lineWidth: 1)
                            }

                            VStack(spacing: 12) {
                                HStack(spacing: 7) {
                                    ForEach(PaywallPlan.allCases) { plan in
                                        planCard(plan)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                if !viewModel.isConfigured {
                                    Text("Preview prices · Purchases are not available yet")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .padding(11)
                            .background(.black.opacity(0.57), in: RoundedRectangle(cornerRadius: 22))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22)
                                    .strokeBorder(gold.opacity(0.3), lineWidth: 1)
                            }

                            Button {
                                purchase()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(showsTrial ? (viewModel.isConfigured ? "Start Free Trial" : "Start 3-Day Free Trial") : "Continue with \(viewModel.selectedPlan.title) Plan")
                                        .font(.system(size: 18, weight: .bold, design: .serif))
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                .foregroundStyle(Color(hex: "#1E1B12"))
                                .padding(.horizontal, 20)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(colors: [Color(hex: "#FFE497"), Color(hex: "#FFB73E")], startPoint: .top, endPoint: .bottom),
                                    in: Capsule()
                                )
                            }
                            .disabled(viewModel.isLoading)

                            if showsTrial {
                                Button("Continue with \(viewModel.selectedPlan.title) Plan") {
                                    purchase()
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 43)
                                .background(.black.opacity(0.55), in: Capsule())
                                .overlay { Capsule().strokeBorder(gold.opacity(0.7), lineWidth: 1) }
                            }

                            Text(viewModel.isConfigured
                                 ? "Subscriptions renew automatically unless canceled. Manage or cancel anytime in Settings."
                                 : "This is a design preview. No payment will be taken.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.83))
                                .multilineTextAlignment(.center)

                            HStack(spacing: 10) {
                                Button("Restore Purchases") {
                                    viewModel.restorePurchases { completePurchase() }
                                }
                                Spacer(minLength: 0)
                                Button("Terms & Conditions") { legalPage = .terms }
                                Spacer(minLength: 0)
                                Button("Privacy Policy") { legalPage = .privacy }
                            }
                            .font(.system(size: 11))
                            .underline()
                            .foregroundStyle(.white)
                            .padding(.bottom, 18)
                        }
                        .padding(.horizontal, 17)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.dark)
        .task { viewModel.getOffering() }
        .onChange(of: viewModel.errorMessage) { _, message in
            showingMessage = message != nil
        }
        .alert("Flavourly Premium", isPresented: $showingMessage) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $legalPage) { page in
            NavigationStack {
                if let url = page.url {
                    LegalWebView(url: url)
                        .navigationTitle(page.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { legalPage = nil }
                            }
                        }
                } else {
                    Text("This page is unavailable.")
                }
            }
            .preferredColorScheme(.light)
        }
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let selected = viewModel.selectedPlan == plan
        return Button {
            viewModel.selectedPlan = plan
        } label: {
            VStack(spacing: 7) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(selected ? gold : .white.opacity(0.75))
                Text(plan.title)
                    .font(.system(size: 13, weight: .medium))
                Text(viewModel.price(for: plan))
                    .font(.system(size: 18, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(plan.period)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                if plan == .yearly && !viewModel.isConfigured {
                    Text("TRIAL PREVIEW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(hex: "#281E0A"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(gold, in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 115)
            .background(selected ? Color(hex: "#5B3915").opacity(0.85) : .black.opacity(0.43), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(selected ? gold : .white.opacity(0.35), lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func purchase() {
        viewModel.makePurchases { completePurchase() }
    }

    private func completePurchase() {
        settings.isPremium = true
        settings.hasSeenPaywall = true
        dismiss()
    }
}

private struct LegalWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
