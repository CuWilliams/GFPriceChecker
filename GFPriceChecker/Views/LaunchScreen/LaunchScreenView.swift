//
//  LaunchScreenView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-31.
//

import SwiftUI

/// Launch screen displayed when app first opens
///
/// Provides a professional branded introduction with:
/// - GFPC logo centered
/// - "Compare, Save, Claim" tagline
/// - Blue-to-green gradient background matching onboarding aesthetic
/// - Smooth fade transition to main app
struct LaunchScreenView: View {

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient - matches OnboardingView exactly
            LinearGradient(
                gradient: Gradient(colors: [.blue.opacity(0.1), .green.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // App logo
                Image("GFPC_Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .accessibilityHidden(true)

                // Tagline
                Text("Compare, Save, Claim")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("GF Price Checker: Compare, Save, Claim")

                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview("Launch Screen") {
    LaunchScreenView()
}
