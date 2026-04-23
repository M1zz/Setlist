import SwiftUI

struct ContentImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String = ""
    @State private var isParsing = false
    @State private var bundle: TravelBundle?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Paste link") {
                    TextField(
                        "https://instagram.com/reel/...",
                        text: $urlString
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
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
                                Text("Turn into trip")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(URL(string: urlString) == nil)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section("How it works") {
                    Label("We read the post or video.", systemImage: "eye")
                    Label("Detect the location and route.", systemImage: "mappin.and.ellipse")
                    Label("Build a bookable trip.", systemImage: "bag")
                }
                .font(.subheadline)
            }
            .navigationTitle("Reel to trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(item: $bundle) { b in
                BundleDetailView(bundle: b)
            }
        }
    }

    private func parse() async {
        guard let url = URL(string: urlString) else { return }
        isParsing = true
        errorMessage = nil
        defer { isParsing = false }
        do {
            let parser = AppEnvironment.aiParser
            let content = try await parser.parseContentLink(url)
            let builder = BundleBuilder(mrt: AppEnvironment.mrtClient)
            bundle = try await builder.buildFromContent(content)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentImportView()
}
