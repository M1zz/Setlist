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
                Section("링크 붙여넣기") {
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
                                Text("여행으로 만들기")
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

                Section("이렇게 동작해요") {
                    Label("게시물/영상을 읽어요", systemImage: "eye")
                    Label("장소와 경로를 찾아내요", systemImage: "mappin.and.ellipse")
                    Label("바로 예약 가능한 여행을 구성해요", systemImage: "bag")
                }
                .font(.subheadline)
            }
            .navigationTitle("릴스/영상에서 여행 만들기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
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
            let parser = AppEnvironment.tripParser
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
