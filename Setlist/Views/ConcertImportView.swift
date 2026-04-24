import SwiftUI
import PhotosUI

struct ConcertImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var manualText: String
    @State private var isParsing = false
    @State private var bundle: TravelBundle?
    @State private var errorMessage: String?

    @State private var previewConcert: ConcertSource?
    @State private var previewTask: Task<Void, Never>?

    init(prefilledText: String = "") {
        _manualText = State(initialValue: prefilledText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Upload your ticket") {
                    PhotosPicker(
                        "Choose ticket image",
                        selection: $pickedItem,
                        matching: .images
                    )
                    if let pickedImage {
                        Image(uiImage: pickedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Section("Or paste ticket details") {
                    TextEditor(text: $manualText)
                        .frame(minHeight: 100)
                    Text("Example: \"BTS ARIRANG, Tokyo Dome, 2026-06-15 19:00\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let preview = previewConcert {
                    Section("We detected") {
                        detectedRow("music.mic", "Artist", preview.artist)
                        detectedRow("mappin.and.ellipse", "Venue", preview.venueName)
                        detectedRow("location", "City", "\(preview.city), \(preview.country)")
                        detectedRow(
                            "calendar",
                            "Show date",
                            preview.showDate.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                Section {
                    Button {
                        Task { await parse() }
                    } label: {
                        HStack {
                            Spacer()
                            if isParsing {
                                ProgressView()
                            } else {
                                Text("Build trip")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDisabled)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Concert trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: pickedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        pickedImage = ui
                        await refreshPreview(fromImage: ui)
                    }
                }
            }
            .onChange(of: manualText) { _, newText in
                schedulePreviewUpdate(text: newText)
            }
            .task {
                // If the view is opened with prefilled text, kick off a preview.
                if !manualText.isEmpty {
                    schedulePreviewUpdate(text: manualText)
                }
            }
            .navigationDestination(item: $bundle) { bundle in
                BundleDetailView(bundle: bundle)
            }
        }
    }

    private func detectedRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
                .font(.caption)
                .labelStyle(.titleAndIcon)
            Spacer()
            Text(value)
                .font(.callout.bold())
                .multilineTextAlignment(.trailing)
        }
    }

    private var isDisabled: Bool {
        pickedImage == nil && manualText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func schedulePreviewUpdate(text: String) {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 5 else {
                await MainActor.run { previewConcert = nil }
                return
            }
            let parsed = try? await AppEnvironment.tripParser.parseConcertTicket(rawText: trimmed)
            if Task.isCancelled { return }
            await MainActor.run { previewConcert = parsed }
        }
    }

    private func refreshPreview(fromImage image: UIImage) async {
        let parsed = try? await AppEnvironment.tripParser.parseConcertTicket(image: image)
        await MainActor.run { previewConcert = parsed }
    }

    private func parse() async {
        isParsing = true
        errorMessage = nil
        defer { isParsing = false }
        do {
            let parser = AppEnvironment.tripParser
            let concert: ConcertSource
            if let pickedImage {
                concert = try await parser.parseConcertTicket(image: pickedImage)
            } else {
                concert = try await parser.parseConcertTicket(rawText: manualText)
            }
            let builder = BundleBuilder(mrt: AppEnvironment.mrtClient)
            bundle = try await builder.buildFromConcert(concert)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ConcertImportView()
}
