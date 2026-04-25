import SwiftUI
import SwiftData

struct BundleDetailView: View {
    let bundle: TravelBundle
    let ticketImageData: Data?
    @Environment(\.modelContext) private var context
    @State private var savedConfirmation = false
    @State private var isOpeningBooking = false
    @State private var bookingError: String?

    init(bundle: TravelBundle, ticketImageData: Data? = nil) {
        self.bundle = bundle
        self.ticketImageData = ticketImageData
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                flightsSection
                hotelsSection
                activitiesSection
            }
            .padding()
            .padding(.bottom, 140)
        }
        .safeAreaInset(edge: .bottom) {
            stickyBookingBar
        }
        .navigationTitle("Your trip")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Saved to wishlist", isPresented: $savedConfirmation) {
            Button("OK", role: .cancel) { }
        }
        .alert(
            "Couldn't open booking",
            isPresented: Binding(
                get: { bookingError != nil },
                set: { if !$0 { bookingError = nil } }
            ),
            presenting: bookingError
        ) { _ in
            Button("OK", role: .cancel) { bookingError = nil }
        } message: { msg in
            Text(msg)
        }
    }

    private var stickyBookingBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated total").font(.caption).foregroundStyle(.secondary)
                    Text("₩\(bundle.estimatedTotalKRW.formatted())")
                        .font(.title3.bold())
                }
                Spacer()
                Button {
                    saveToWishlist()
                } label: {
                    Image(systemName: "heart")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task { await openBooking() }
                } label: {
                    HStack {
                        if isOpeningBooking { ProgressView().tint(.white) }
                        Text(isOpeningBooking ? "Opening…" : "Book all")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isOpeningBooking)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline).font(.title2.bold())
            Text(
                "\(bundle.suggestedDepartureDate.formatted(date: .abbreviated, time: .omitted)) – \(bundle.suggestedReturnDate.formatted(date: .abbreviated, time: .omitted))"
            )
            .foregroundStyle(.secondary)
            if case .concert(let c) = bundle.source {
                Label("Show: \(c.showDate.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "music.mic")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.purple.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var flightsSection: some View {
        sectionCard(title: "Flights") {
            if bundle.flights.isEmpty {
                Text("No flight prices available for these dates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(bundle.flights.enumerated()), id: \.element.id) { index, f in
                Button {
                    Task { await openItem(
                        url: f.bookingURL,
                        title: "\(f.airline) \(f.fromAirport)→\(f.toAirport)",
                        category: "FLIGHT",
                        gid: f.mrtProductID
                    ) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(f.airline) \(f.flightNumber)").bold()
                            Spacer()
                            if f.priceKRW > 0 {
                                Text("₩\(f.priceKRW.formatted())")
                            } else {
                                Text("See fare").foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                        Text(
                            "\(f.fromAirport) → \(f.toAirport) · \(f.departureTime.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                if index < bundle.flights.count - 1 { Divider() }
            }
        }
    }

    private var hotelsSection: some View {
        sectionCard(title: "Hotels near your anchor") {
            if bundle.hotels.isEmpty {
                Text("No hotels returned for these dates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(bundle.hotels.enumerated()), id: \.element.id) { index, h in
                Button {
                    Task { await openItem(
                        url: h.bookingURL,
                        title: h.name,
                        category: "HOTEL",
                        gid: h.mrtProductID
                    ) }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(h.name).bold().lineLimit(2)
                            Spacer()
                            Text("₩\(h.pricePerNightKRW.formatted())/night")
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                        Text(hotelCaption(h))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if h.freeCancellation {
                            Label("Free cancellation", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                if index < bundle.hotels.count - 1 { Divider() }
            }
        }
    }

    private func hotelCaption(_ h: HotelOption) -> String {
        var parts: [String] = []
        if h.distanceMetersFromAnchor > 0 {
            parts.append("\(h.distanceMetersFromAnchor)m away")
        }
        if h.starRating > 0 {
            parts.append(String(format: "%.1f★", h.starRating))
        }
        if h.userRating > 0 {
            parts.append(String(format: "guests %.1f", h.userRating))
        }
        return parts.joined(separator: " · ")
    }

    private var activitiesSection: some View {
        sectionCard(title: "Add-on activities") {
            if bundle.activities.isEmpty {
                Text("No activities found for this city.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(bundle.activities.enumerated()), id: \.element.id) { index, a in
                NavigationLink {
                    TNADetailView(activity: a)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if let url = a.thumbnailURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                default:
                                    Color.gray.opacity(0.1)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).bold().lineLimit(2)
                                .foregroundStyle(.primary)
                            Text(activityCaption(a))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("₩\(a.priceKRW.formatted())")
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                if index < bundle.activities.count - 1 { Divider() }
            }
        }
    }

    private func activityCaption(_ a: ActivityOption) -> String {
        var parts: [String] = []
        if a.durationHours > 0 { parts.append(String(format: "%.1f hrs", a.durationHours)) }
        if a.rating > 0 { parts.append(String(format: "★ %.1f", a.rating)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private var headline: String {
        switch bundle.source {
        case .concert(let c): return "\(c.artist) · \(c.city)"
        case .content(let c): return c.detectedPlaceName ?? c.detectedCity
        case .manual: return "Trip"
        }
    }

    private func saveToWishlist() {
        do {
            let data = try JSONEncoder.setlist.encode(bundle)
            let trip = SavedTrip(
                bundleData: data,
                title: headline,
                ticketImageData: ticketImageData
            )
            context.insert(trip)
            try context.save()
            savedConfirmation = true
        } catch {
            print("Save failed: \(error)")
        }
    }

    @MainActor
    private func openBooking() async {
        guard let target = primaryBookingURL else { return }
        isOpeningBooking = true
        defer { isOpeningBooking = false }

        // "Book all" picks the most-trackable item: hotel > activity > flight,
        // because MRT's flight reservation API doesn't surface utm_content.
        let intent: BookingIntent? = {
            if let h = bundle.hotels.first {
                return BookingIntent(
                    title: h.name,
                    productCategory: "HOTEL",
                    productGid: h.mrtProductID,
                    targetURLString: h.bookingURL.absoluteString,
                    ticketImageData: ticketImageData
                )
            }
            if let a = bundle.activities.first {
                return BookingIntent(
                    title: a.title,
                    productCategory: "TNA",
                    productGid: a.mrtProductID,
                    targetURLString: a.bookingURL.absoluteString,
                    ticketImageData: ticketImageData
                )
            }
            return nil
        }()

        let urlToOpen: URL
        if let intent {
            context.insert(intent)
            try? context.save()
            urlToOpen = URL(string: intent.targetURLString) ?? target
        } else {
            urlToOpen = target  // flight-only — no utm tracking possible
        }

        do {
            let trackedURL = try await AppEnvironment.mrtClient.generateMyLink(
                targetURL: urlToOpen,
                utmContent: intent?.id.uuidString
            )
            _ = await UIApplication.shared.open(trackedURL)
            recordBooking(url: trackedURL)
        } catch {
            _ = await UIApplication.shared.open(urlToOpen)
            bookingError = error.localizedDescription
        }
    }

    @MainActor
    private func openItem(url: URL, title: String, category: String, gid: String) async {
        let intent = BookingIntent(
            title: title,
            productCategory: category,
            productGid: gid,
            targetURLString: url.absoluteString,
            ticketImageData: ticketImageData
        )
        context.insert(intent)
        try? context.save()

        do {
            let tracked = try await AppEnvironment.mrtClient.generateMyLink(
                targetURL: url,
                utmContent: intent.id.uuidString
            )
            _ = await UIApplication.shared.open(tracked)
        } catch {
            _ = await UIApplication.shared.open(url)
        }
    }

    private var primaryBookingURL: URL? {
        // Prefer the flight landing URL because it encodes the whole trip
        // parameters; hotels/activities are per-item fallbacks.
        bundle.flights.first?.bookingURL
            ?? bundle.hotels.first?.bookingURL
            ?? bundle.activities.first?.bookingURL
    }

    private func recordBooking(url: URL) {
        do {
            let data = try JSONEncoder.setlist.encode(bundle)
            let ref = url.lastPathComponent.isEmpty ? UUID().uuidString.prefix(8).uppercased() : url.lastPathComponent
            let booked = BookedTrip(
                bundleData: data,
                title: headline,
                bookingReference: String(ref),
                ticketImageData: ticketImageData
            )
            context.insert(booked)
            try context.save()
        } catch {
            // Logging only — booking already opened in browser.
            print("Record booking failed: \(error)")
        }
    }
}
