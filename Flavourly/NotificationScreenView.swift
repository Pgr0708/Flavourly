//
//  NotificationScreenView.swift
//  Flavourly
//
//  Explains what we'll send before iOS asks, so the system prompt is an informed yes.
//

import SwiftUI

struct NotificationScreenView: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var ring = false

    private let reasons: [(String, String, String, Color)] = [
        ("timer", "Cooking timers", "Rings even when your phone is locked", Theme.capture),
        ("calendar.badge.clock", "Tomorrow's plan", "The evening before — with a defrost reminder", Theme.plan),
        ("clock.badge.exclamationmark", "Use it before it goes off", "Pantry items close to their date", Theme.pantry),
        ("basket.fill", "Grocery day", "Your list, ready for the weekend shop", Theme.green),
        ("book.fill", "Your cookbook", "A recipe you saved but haven't tried yet", Theme.aiDeep),
    ]

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.creamGradient).frame(width: 128, height: 128)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Theme.capture, Theme.green)
                    .rotationEffect(.degrees(ring ? 12 : -12), anchor: .top)
                    .animation(.easeInOut(duration: 0.18).repeatCount(5, autoreverses: true), value: ring)
            }
            .padding(.top, 34)
            .onAppear { ring = true }

            VStack(spacing: 8) {
                Text("Helpful nudges, never spam").font(Theme.display(30)).multilineTextAlignment(.center)
                Text("Flavourly only reminds you about your own plan, pantry and recipes. Turn any of these off in Settings.")
                    .font(Theme.caption).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(reasons, id: \.1) { symbol, title, detail, tint in
                    HStack(spacing: 14) {
                        IconTile(systemImage: symbol, tint: tint, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 15, weight: .semibold))
                            Text(detail).font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                PrimaryButton(title: "Turn on notifications", systemImage: "bell.fill", isLoading: working) { allow() }
                PrimaryButton(title: "Not now", tone: .plain, height: 44) {
                    settings.hasSeenNotificationPrompt = true
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .canvasBackground()
        .presentationDetents([.large])
        .interactiveDismissDisabled(working)
    }

    private func allow() {
        working = true
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            working = false
            settings.hasSeenNotificationPrompt = true
            if granted {
                DropsManager.showSuccess(title: "Notifications on", subtitle: "Change what you get in Settings")
            } else {
                DropsManager.showInfo(title: "No problem", subtitle: "You can turn them on later in Settings")
            }
            dismiss()
        }
    }
}

#Preview {
    NotificationScreenView().environmentObject(SettingsManager.shared)
}
