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
    @State private var viewModel = OnboardingViewModel()

    /// Camera permission status
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined

    /// Shows alert if camera permission is denied
    @State private var showingPermissionAlert = false

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
                // Skip button (every page but the last)
                if !viewModel.isLastPage {
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
                TabView(selection: $viewModel.page) {
                    welcomePage
                        .tag(OnboardingViewModel.Page.welcome)

                    howItWorksPage
                        .tag(OnboardingViewModel.Page.howItWorks)

                    smartScanningPage
                        .tag(OnboardingViewModel.Page.smartScanning)

                    permissionsPage
                        .tag(OnboardingViewModel.Page.camera)

                    readyPage
                        .tag(OnboardingViewModel.Page.ready)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Navigation buttons
                HStack {
                    // Back button
                    if !viewModel.isFirstPage {
                        Button {
                            withAnimation {
                                viewModel.back()
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
                        if !viewModel.isLastPage {
                            withAnimation {
                                viewModel.next()
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(viewModel.isLastPage ? "Get Started" : "Next")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel(viewModel.isLastPage ? "Get started" : "Next page")
                    .accessibilityHint(viewModel.isLastPage ? "Complete onboarding and start using the app" : "Continue to next page")
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
        .demoRegistered(viewModel)
    }

    // MARK: - Pages

    /// Page 1: Welcome
    private var welcomePage: some View {
        VStack(spacing: 30) {
            Spacer()

            // App logo
            AppLogo(size: 240)
                .accessibilityHidden(true)

            // App name
            //Text("GF Price Checker")
              //  .font(.system(size: 36, weight: .bold))

            // Tagline
            Text("Track the cost of eating gluten-free")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Description
            Text("Compare gluten-free and regular product prices to document the true cost of your gluten-free diet.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to GF Price Checker")
        .accessibilityValue("Track the cost of eating gluten-free. Compare gluten-free and regular product prices to document the true cost of your gluten-free diet.")
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
                        Text("Photograph shelf price tags for smart OCR extraction")
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
                        Text("Generate professional price differential reports")
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
        .accessibilityValue("Step 1: Capture. Photograph shelf price tags for smart OCR extraction. Step 2: Verify. Link products to receipts for proof of purchase. Step 3: Export. Generate professional price differential reports.")
    }

    /// Page 3: Smart Scanning Tips
    private var smartScanningPage: some View {
        VStack(spacing: 25) {
            Text("Smart Scanning")
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 40)

            Text("Our OCR technology makes price capture easy")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 20) {
                // Feature 1: Rectangle Detection
                ScanningFeatureRow(
                    icon: "rectangle.dashed",
                    iconColor: .blue,
                    title: "Tap to Select Price Tags",
                    description: "The app detects shelf price tags automatically. Just tap the one you want to scan."
                )

                // Feature 2: Smart Price Detection
                ScanningFeatureRow(
                    icon: "wand.and.stars",
                    iconColor: .purple,
                    title: "Automatic Price Detection",
                    description: "Prices are identified by size, position, and formatting. High-confidence results are selected automatically."
                )

                // Feature 3: Decimal Inference
                ScanningFeatureRow(
                    icon: "dollarsign.circle",
                    iconColor: .green,
                    title: "Smart Decimal Handling",
                    description: "Prices like \"1299\" are recognized as \"$12.99\". You'll be asked to confirm when this happens."
                )

                // Feature 4: Confidence Indicators
                ScanningFeatureRow(
                    icon: "gauge.with.needle",
                    iconColor: .orange,
                    title: "Confidence Indicators",
                    description: "Green, yellow, and red dots show OCR accuracy. Low confidence values can be corrected manually."
                )
            }
            .padding(.horizontal, 25)
            .padding(.top, 10)

            // Tip box
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                Text("For best results, photograph shelf tags straight-on in good lighting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 25)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Smart Scanning Features")
        .accessibilityValue("Tap to select price tags. The app detects shelf price tags automatically. Automatic price detection identifies prices by size and position. Smart decimal handling recognizes prices like 1299 as $12.99. Confidence indicators show OCR accuracy with green, yellow, and red dots. For best results, photograph shelf tags straight-on in good lighting.")
    }

    /// Page 4: Permissions
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
                    icon: "viewfinder",
                    title: "Scan Smart",
                    description: "Photograph shelf price tags for the best OCR accuracy"
                )

                TipRow(
                    icon: "equal.circle.fill",
                    title: "Match Sizes",
                    description: "Compare the same size products for accurate price differentials"
                )

                TipRow(
                    icon: "star.fill",
                    title: "Quick Start",
                    description: "Head to the Capture tab to add your first product pair"
                )
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all set")
        .accessibilityValue("Start tracking your gluten-free price differences today. Scan smart: Photograph shelf price tags for the best OCR accuracy. Match sizes: Compare the same size products for accurate price differentials. Quick start: Head to the Capture tab to add your first product pair.")
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

/// Feature row for smart scanning page
struct ScanningFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(isPresented: .constant(true))
}
#endif
