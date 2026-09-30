//
//  LanguageScreenView.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import SwiftUI

struct LanguageScreenView: View {
    @EnvironmentObject private var settings: SettingsManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color.blue,
                    Color.indigo
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading) {
                    Image(systemName: "globe")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.2))
                        .cornerRadius(16)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.clear)
                                .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                        }

                    Text("Choose Language")
                        .foregroundStyle(.white)

                    Text("Change it any time from settings")
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 16)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Languages.allCases, id: \.self) { language in
                            HStack(alignment: .center, spacing: 13) {
                                Text(language.flag)
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(
                                        settings.languageCode == language.shortCode.lowercased()
                                        ? .white
                                        : .secondary
                                    )
                                    .background(
                                        settings.languageCode == language.shortCode.lowercased()
                                        ? Color.blue
                                        : Color(.gray.opacity(0.6))
                                    )
                                    .cornerRadius(8)

                                VStack(alignment: .leading) {
                                    Text(language.rawValue)
                                        .foregroundStyle(.primary)

                                    Text(language.localizedName)
                                        .foregroundStyle(
                                            settings.languageCode == language.shortCode.lowercased()
                                            ? .blue
                                            : .secondary
                                        )
                                }

                                Spacer()

                                ZStack(alignment: .center) {
                                    Circle()
                                        .fill(
                                            settings.languageCode == language.shortCode.lowercased()
                                            ? Color.blue
                                            : Color.clear
                                        )
                                        .strokeBorder(
                                            settings.languageCode == language.shortCode.lowercased()
                                            ? Color.clear
                                            : Color.secondary.opacity(0.4)
                                        )
                                        .frame(width: 24, height: 24)

                                    if settings.languageCode == language.shortCode.lowercased() {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .padding()
                            .background(
                                settings.languageCode == language.shortCode.lowercased()
                                ? Color.blue.opacity(0.12)
                                : Color(.systemBackground)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    settings.languageCode = language.shortCode.lowercased()
                                }
                            }

                            Divider()
                        }
                    }
                    .cornerRadius(16)
                }
                .padding()
                .padding(.bottom, 50)
                .background(Color(.systemBackground))
            }

            VStack {
                Spacer()

                FullWidthButton(
                    completion: {
                        settings.hasSeenLanguage = true
                    },
                    title: L10n.Continue
                )
            }
        }
    }
}
