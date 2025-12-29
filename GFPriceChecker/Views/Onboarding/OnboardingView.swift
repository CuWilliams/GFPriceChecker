//
//  OnboardingView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI
import AVFoundation

/// First-run onboarding experience
///
/// Guides users through:
/// - App introduction and purpose
/// - How the app works (3-step process)
/// - Camera permission request with explanation
/// - Ready to start message
struct OnboardingView: View {

    // MARK: - Properties

    /// Controls whether the onboarding view is presented
    @Binding var isPresented: Bool

    /// Current page in the onboarding flow
    @State private var currentPage = 0

    /// Camera permission status
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined

    /// Shows alert if camera permission is denied
    @State private var showingPermissionAlert = false

    // MARK: - Constants

    private let totalPages = 4

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [.blue.opacity(0.1), .green.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button (only on first 3 pages)
                if currentPage < totalPages - 1 {
                    HStack {
                        Spacer()
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .font(.subheadline)
                        .padding()
                        .accessibilityLabel("Skip onboarding")
                        .accessibilityHint("Complete onboarding without viewing all pages")
                    }
                }

                // Page content
                TabView(selection: $currentPage) {
                    welcomePage
                        .tag(0)

                    howItWorksPage
                        .tag(1)

                    permissionsPage
                        .tag(2)

                    readyPage
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Navigation buttons
                HStack {
                    // Back button
                    if currentPage > 0 {
                        Button {
                            withAnimation {
                                currentPage -= 1
                            }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .font(.headline)
                                .padding()
                        }
                        .accessibilityLabel("Go back")
                        .accessibilityHint("Return to previous page")
                    }

                    Spacer()

                    // Next/Get Started button
                    Button {
                        if currentPage < totalPages - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentPage == totalPages - 1 ? "Get Started" : "Next")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel(currentPage == totalPages - 1 ? "Get started" : "Next page")
                    .accessibilityHint(currentPage == totalPages - 1 ? "Complete onboarding and start using the app" : "Continue to next page")
                }
                .padding()
            }
        }
        .alert("Camera Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("GFPriceChecker needs camera access to scan product labels and receipts. Please enable camera access in Settings.")
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    // MARK: - Pages

    /// Page 1: Welcome
    private var welcomePage: some View {
        VStack(spacing: 30) {
            Spacer()

            // App logo
            Image("GFPC_Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)

            // App name
            Text("GF Price Checker")
                .font(.system(size: 36, weight: .bold))

            // Tagline
            Text("Track the cost of eating gluten-free")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Description
            Text("Compare gluten-free and regular product prices to document your additional food costs for Canadian tax deductions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to GF Price Checker")
        .accessibilityValue("Track the cost of eating gluten-free. Compare gluten-free and regular product prices to document your additional food costs for Canadian tax deductions.")
    }

    /// Page 2: How It Works
    private var howItWorksPage: some View {
        VStack(spacing: 40) {
            Text("How It Works")
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 40)

            VStack(alignment: .leading, spacing: 35) {
                // Step 1
                HStack(alignment: .top, spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 60, height: 60)
                        Text("1")
                            .font(.title.bold())
                            .foregroundStyle(.blue)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(.blue)
                            Text("Capture")
                                .font(.title3.bold())
                        }
                        Text("Scan product labels or enter prices manually")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Step 2
                HStack(alignment: .top, spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 60, height: 60)
                        Text("2")
                            .font(.title.bold())
                            .foregroundStyle(.green)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.viewfinder")
                                .foregroundStyle(.green)
                            Text("Verify")
                                .font(.title3.bold())
                        }
                        Text("Link products to receipts for proof of purchase")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Step 3
                HStack(alignment: .top, spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 60, height: 60)
                        Text("3")
                            .font(.title.bold())
                            .foregroundStyle(.orange)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.orange)
                            Text("Export")
                                .font(.title3.bold())
                        }
                        Text("Generate professional reports for CRA tax filing")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 30)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How it works")
        .accessibilityValue("Step 1: Capture. Scan product labels or enter prices manually. Step 2: Verify. Link products to receipts for proof of purchase. Step 3: Export. Generate professional reports for CRA tax filing.")
    }

    /// Page 3: Permissions
    private var permissionsPage: some View {
        VStack(spacing: 30) {
            Spacer()

            // Camera icon
            Image(systemName: "camera.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            // Title
            Text("Camera Access")
                .font(.system(size: 32, weight: .bold))

            // Description
            Text("GFPriceChecker uses your camera to:")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 15) {
                PermissionBulletPoint(
                    icon: "doc.text.viewfinder",
                    text: "Scan product labels to extract prices automatically"
                )

                PermissionBulletPoint(
                    icon: "receipt",
                    text: "Capture receipts to verify your purchases"
                )

                PermissionBulletPoint(
                    icon: "lock.fill",
                    text: "All images stay private on your device"
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)

            // Permission button
            if cameraPermissionStatus == .notDetermined {
                Button {
                    requestCameraPermission()
                } label: {
                    Text("Enable Camera Access")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .padding(.top, 20)
                .accessibilityLabel("Enable camera access")
                .accessibilityHint("Request permission to use the camera for scanning products and receipts")
            } else if cameraPermissionStatus == .authorized {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Camera Access Granted")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .padding(.top, 20)
                .accessibilityLabel("Camera access granted")
            } else {
                VStack(spacing: 10) {
                    Text("Camera access is required")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        showingPermissionAlert = true
                    } label: {
                        Text("Open Settings")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("Open settings to enable camera")
                    .accessibilityHint("Opens Settings app where you can grant camera permission")
                }
                .padding(.top, 20)
            }

            Spacer()
        }
    }

    /// Page 4: Ready to Start
    private var readyPage: some View {
        VStack(spacing: 30) {
            Spacer()

            // Celebration icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            // Title
            Text("You're All Set!")
                .font(.system(size: 36, weight: .bold))

            // Description
            Text("Start tracking your gluten-free price differences today")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Tips
            VStack(alignment: .leading, spacing: 20) {
                TipRow(
                    icon: "lightbulb.fill",
                    title: "Pro Tip",
                    description: "Compare the same size products for the most accurate price differential"
                )

                TipRow(
                    icon: "star.fill",
                    title: "Quick Start",
                    description: "Head to the Capture tab to add your first product pair"
                )

                TipRow(
                    icon: "book.fill",
                    title: "Need Help?",
                    description: "Tap the settings icon to access 'How to Use' anytime"
                )
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all set")
        .accessibilityValue("Start tracking your gluten-free price differences today. Pro tip: Compare the same size products for the most accurate price differential. Quick start: Head to the Capture tab to add your first product pair. Need help? Tap the settings icon to access how to use anytime.")
    }

    // MARK: - Helper Methods

    /// Checks current camera permission status
    private func checkCameraPermission() {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests camera permission from the user
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraPermissionStatus = granted ? .authorized : .denied
                if !granted {
                    showingPermissionAlert = true
                }
            }
        }
    }

    /// Completes onboarding and dismisses the view
    private func completeOnboarding() {
        AppSettings.shared.hasCompletedOnboarding = true
        isPresented = false
    }
}

// MARK: - Supporting Views

/// Bullet point for permission reasons
struct PermissionBulletPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

/// Tip row for ready page
struct TipRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(isPresented: .constant(true))
}
