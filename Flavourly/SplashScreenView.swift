//
//  SplashScreenView.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import SwiftUI
import Lottie

struct SplashScreenView: View {
    @EnvironmentObject private var settings: SettingsManager
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    
    var body: some View {
        
        if isActive {
            RootView()
        } else {
                VStack {
                        Text(AppInfo.appName)
                    }
                    .padding()
                    .scaleEffect(size)
                    .opacity(opacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 1)) {
                            size = 1.0
                            opacity = 1.0
                        }
                    }
                    
                    VStack(spacing: 8) {
                        Spacer()
                        
                        LottieView(animation: .named("Loading"))
                            .playing(loopMode: .loop)
                            .frame(maxWidth: .infinity, maxHeight: 30)
                        
                        Text(String(localized: "Version \(AppInfo.version)"))

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation {
                            isActive = true
                        }
                    }
                }
            }
        }
    }


