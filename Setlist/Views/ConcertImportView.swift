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
                    }
                }
            }
            .navigationDestination(item: $bundle) { bundle in
                BundleDetailView(bundle: bundle)
            }
        }
    }

    private var isDisabled: Bool {
        pickedImage == nil && manualText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func parse() async {
        isParsing = true
        errorMessage = nil
        defer { isParsing = false }
        do {
            let parser = AppEnvironment.aiParser
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
