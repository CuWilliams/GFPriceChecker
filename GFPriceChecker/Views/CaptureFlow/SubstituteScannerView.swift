//
//  SubstituteScannerView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-09-13.
//

import PhotosUI
import SwiftUI

/// Stands in for the document camera wherever it is unavailable.
///
/// `VNDocumentCameraViewController.isSupported` is `false` in the Simulator, and
/// presenting it there gets a blank sheet. Every capture flow in the app starts
/// with a scan, so without this the flows cannot be run at all off-device — not
/// for a demo recording, and not during ordinary development either.
///
/// It offers the same contract as the real scanner: one `UIImage`, or `nil` for
/// cancelled.
///
/// Two sources, plus a third in DEBUG:
/// - the photo library, which is how a real shelf-tag photo gets in (drag one
///   onto the Simulator window first);
/// - in DEBUG, `SampleScanImages`, drawn on the spot, so the flow can be walked
///   with nothing set up at all;
/// - in DEBUG, `ScannerImageProvider`, which supplies an image with no UI shown.
struct SubstituteScannerView: View {

    // MARK: - Properties

    /// Matches `DocumentScannerView`: the scanned image, or `nil` if cancelled.
    let completion: (UIImage?) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var photoSelection: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var photoLoadFailed = false

    /// True when `ScannerImageProvider` has an image waiting, in which case no
    /// picker is drawn — showing one for a frame would land in a recording.
    @State private var isSupplyingProgrammatically: Bool

    /// The queued image, shown while the sheet is up. A recording otherwise
    /// shows a blank white sheet rising and falling for every scan, where on a
    /// device the viewer would see the camera on the tag.
    @State private var suppliedImage: UIImage?

    /// How long the queued image holds once the sheet is up, so a viewer sees
    /// what was scanned before the sheet goes.
    private static let suppliedImageSeconds: Double = 1.0

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        #if DEBUG
        _isSupplyingProgrammatically = State(initialValue: ScannerImageProvider.hasPendingImages)
        #else
        _isSupplyingProgrammatically = State(initialValue: false)
        #endif
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isSupplyingProgrammatically {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let suppliedImage {
                        Image(uiImage: suppliedImage)
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                picker
            }
        }
        .task {
            #if DEBUG
            if let supplied = ScannerImageProvider.takeNext() {
                suppliedImage = supplied
                try? await Task.sleep(for: .seconds(Self.suppliedImageSeconds))
                finish(with: supplied)
            }
            #endif
        }
    }

    private var picker: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Camera Unavailable")
                                .font(.headline)
                            Text("The document scanner needs a physical device. Use a photo or a sample instead.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "camera.metering.unknown")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                }

                Section("From Your Photos") {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label("Choose a Photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityHint("Opens the photo library to pick an image in place of a scan")

                    if isLoadingPhoto {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading photo…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if photoLoadFailed {
                        Label("That photo could not be read. Try another.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                #if DEBUG
                Section {
                    ForEach(SampleScanImages.catalog) { sample in
                        Button {
                            finish(with: sample.image())
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.title)
                                Text(sample.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Uses this sample image in place of a scan")
                    }
                } header: {
                    Text("Sample Scans")
                } footer: {
                    Text("Drawn by the app, and readable by OCR. Debug builds only.")
                }
                #endif
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        finish(with: nil)
                    }
                }
            }
        }
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            loadPhoto(selection)
        }
    }

    // MARK: - Actions

    /// Dismisses first, then reports, matching how the real scanner's coordinator
    /// orders the two.
    private func finish(with image: UIImage?) {
        dismiss()
        completion(image)
    }

    private func loadPhoto(_ selection: PhotosPickerItem) {
        isLoadingPhoto = true
        photoLoadFailed = false

        Task {
            let data = try? await selection.loadTransferable(type: Data.self)
            isLoadingPhoto = false

            guard let data, let image = UIImage(data: data) else {
                photoLoadFailed = true
                photoSelection = nil
                return
            }

            finish(with: image)
        }
    }
}

#if DEBUG
// MARK: - Preview

#Preview {
    SubstituteScannerView { _ in }
}
#endif
