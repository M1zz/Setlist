import SwiftUI
import SwiftData

struct WishlistView: View {
    @Query(sort: \SavedTrip.createdAt, order: .reverse) private var trips: [SavedTrip]
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "No saved trips yet",
                        systemImage: "ticket",
                        description: Text("Trips you save will show up here as tickets.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(trips) { trip in
                                NavigationLink {
                                    destination(for: trip)
                                } label: {
                                    ticketRow(for: trip)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(trip)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .background(Color(red: 0.95, green: 0.94, blue: 0.91))
                }
            }
            .navigationTitle("Wishlist")
        }
    }

    @ViewBuilder
    private func destination(for trip: SavedTrip) -> some View {
        if let bundle = trip.bundle {
            BundleDetailView(bundle: bundle, ticketImageData: trip.ticketImageData)
        } else {
            Text("Could not load this trip")
        }
    }

    private func ticketRow(for trip: SavedTrip) -> some View {
        let bundle = trip.bundle
        let accent = accentColor(for: bundle?.source)
        return TicketCard(accent: accent) {
            TicketTopSection(
                title: trip.title,
                subtitle: subtitle(for: bundle),
                detail: dateRangeString(for: bundle),
                ticketImageData: trip.ticketImageData,
                accent: accent,
                fallbackTopic: topicHint(for: bundle)
            )
        } bottom: {
            TicketBottomSection(
                leading: "SAVED",
                leadingValue: trip.createdAt.formatted(date: .abbreviated, time: .omitted),
                trailing: "EST. TOTAL",
                trailingValue: bundle.map { "₩\($0.estimatedTotalKRW.formatted())" } ?? "—",
                seedForBarcode: trip.id.uuidString
            )
        }
        .frame(height: 190)
    }

    private func delete(_ trip: SavedTrip) {
        context.delete(trip)
        try? context.save()
    }

    private func subtitle(for bundle: TravelBundle?) -> String {
        guard let bundle else { return "" }
        switch bundle.source {
        case .concert(let c): return "\(c.venueName) · \(c.city)"
        case .content(let c): return c.detectedPlaceName ?? c.detectedCity
        case .manual:         return ""
        }
    }

    private func dateRangeString(for bundle: TravelBundle?) -> String {
        guard let bundle else { return "" }
        let start = bundle.suggestedDepartureDate.formatted(date: .abbreviated, time: .omitted)
        let end = bundle.suggestedReturnDate.formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }

    private func topicHint(for bundle: TravelBundle?) -> String? {
        guard let bundle else { return nil }
        switch bundle.source {
        case .concert(let c): return "\(c.city) skyline"
        case .content(let c): return c.detectedPlaceName ?? "\(c.detectedCity) cityscape"
        case .manual:         return nil
        }
    }

    private func accentColor(for source: TripSource?) -> Color {
        switch source {
        case .concert: return .purple
        case .content: return .pink
        case .manual, .none: return .blue
        }
    }
}

// MARK: - Ticket content building blocks (shared with BookingsView)

struct TicketTopSection: View {
    let title: String
    let subtitle: String
    let detail: String
    let ticketImageData: Data?
    let accent: Color
    var fallbackTopic: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail
                .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !detail.isEmpty {
                    Label(detail, systemImage: "calendar")
                        .font(.caption2.bold())
                        .foregroundStyle(accent)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = ticketImageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        } else if let topic = fallbackTopic, !topic.isEmpty {
            RichImageView(topic: topic, fallbackTint: accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(accent)
                }
        }
    }
}

struct TicketBottomSection: View {
    let leading: String
    let leadingValue: String
    let trailing: String
    let trailingValue: String
    let seedForBarcode: String

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leading)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Text(leadingValue)
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(trailing)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Text(trailingValue)
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    WishlistView()
        .modelContainer(for: [SavedTrip.self, BookedTrip.self], inMemory: true)
}
