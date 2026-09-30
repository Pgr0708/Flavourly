//
//  FullWidthButton.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import SwiftUI

struct FullWidthButton: View {
    @EnvironmentObject private var settings: SettingsManager
    let completion: () -> Void
    let title: LocalizedStringKey
    var backgroundColor: Color? = nil

    var body: some View {
        Button {
            completion()
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(Color.white)
                .background(backgroundColor ?? settings.selectedAppAccentColor)
                .cornerRadius(16)
                .padding(.horizontal)
        }
    }
}
