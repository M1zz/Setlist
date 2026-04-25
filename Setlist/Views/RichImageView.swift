import SwiftUI

// Fetches a commercially-usable image from Openverse for the given topic
// and renders it. While loading or on failure, falls back to a tinted
// gradient placeholder so layouts never break.

struct RichImageView: View {
    let topic: String
    var fallbackTint: Color = .blue
    var preferThumbnail: Bool = true
    var onLoaded: ((OpenverseImage) -> Void)? = nil

    @State private var image: OpenverseImage?

    var body: some View {
        ZStack {
            gradient
            if let image = image {
                AsyncImage(
                    url: preferThumbnail ? image.thumbnailURL : image.url,
                    transaction: Transaction(animation: .easeIn(duration: 0.18))
                ) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color.clear
                    }
                }
                .clipped()
            }
        }
        .clipped()
        .task(id: topic) {
            guard image == nil, !topic.isEmpty else { return }
            if let fetched = await OpenverseClient.shared.image(forTopic: topic) {
                await MainActor.run {
                    image = fetched
                    onLoaded?(fetched)
                }
            }
        }
    }

    private var gradient: some View {
        LinearGradient(
            colors: [
                fallbackTint.opacity(0.45),
                fallbackTint.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// Tiny attribution label for hero areas. Per the CC license, derivative
// works built from BY / BY-SA images need credit. We render the photographer
// name + license tag in a small caption that overlays the image bottom-edge.

struct ImageAttributionLabel: View {
    let image: OpenverseImage

    var body: some View {
        if !image.creator.isEmptyOrNil || !image.licenseLabel.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "camera.fill").font(.system(size: 8))
                Text(captionText)
                    .lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.4), in: Capsule())
        }
    }

    private var captionText: String {
        var parts: [String] = []
        if let creator = image.creator, !creator.isEmpty {
            parts.append(creator)
        }
        if !image.licenseLabel.isEmpty {
            parts.append(image.licenseLabel)
        }
        return parts.joined(separator: " · ")
    }
}

private extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool { self?.isEmpty ?? true }
}
