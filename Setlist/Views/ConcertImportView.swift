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
                Section("티켓 사진 올리기") {
                    PhotosPicker(
                        "티켓 사진 선택",
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

                Section("또는 티켓 정보 붙여넣기") {
                    TextEditor(text: $manualText)
                        .frame(minHeight: 100)
                    Text("예: \"BTS ARIRANG, 도쿄돔, 2026-06-15 19:00\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let preview = previewConcert {
                    Section("이렇게 인식했어요") {
                        detectedRow("music.mic", "아티스트", preview.artist)
                        detectedRow("mappin.and.ellipse", "공연장", preview.venueName)
                        detectedRow("location", "도시", "\(preview.city), \(preview.country)")
                        detectedRow(
                            "calendar",
                            "공연일",
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
                                Text("여행 만들기")
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
            .navigationTitle("콘서트 여행")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
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
                BundleDetailView(
                    bundle: bundle,
                    ticketImageData: pickedImage?.jpegData(compressionQuality: 0.7)
                )
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
