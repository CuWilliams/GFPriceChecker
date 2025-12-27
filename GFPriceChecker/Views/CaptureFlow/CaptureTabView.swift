//
//  CaptureTabView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI

/// Capture tab container that presents the product capture flow as a sheet
struct CaptureTabView: View {

    // MARK: - State

    /// Controls whether the capture flow sheet is shown
    @State private var showingCaptureFlow = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "camera.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Ready to Capture")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Compare gluten-free and regular products to track price differentials")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    showingCaptureFlow = true
                } label: {
                    Label("Start New Capture", systemImage: "camera")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)

                Spacer()
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingCaptureFlow) {
                ProductCaptureFlowView()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CaptureTabView()
}
