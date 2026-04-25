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
        .navigationTitle("여행 일정")
        .navigationBarTitleDisplayMode(.inline)
        .alert("찜에 저장됐어요", isPresented: $savedConfirmation) {
            Button("확인", role: .cancel) { }
        }
        .alert(
            "예약 페이지를 열 수 없어요",
            isPresented: Binding(
                get: { bookingError != nil },
                set: { if !$0 { bookingError = nil } }
            ),
            presenting: bookingError
        ) { _ in
            Button("확인", role: .cancel) { bookingError = nil }
        } message: { msg in
            Text(msg)
        }
    }

    private var stickyBookingBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("예상 총액").font(.caption).foregroundStyle(.secondary)
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
                        Text(isOpeningBooking ? "여는 중..." : "예약하기")
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

    @State private var headerImage: OpenverseImage?

    private var headerCard: some View {
        ZStack(alignment: .bottomLeading) {
            RichImageView(topic: heroTopic, fallbackTint: heroTint) { headerImage = $0 }
                .frame(height: 200)
                .frame(maxWidth: .infinity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            VStack(alignment: .leading, spacing: 6) {
                if case .concert(let c) = bundle.source {
                    Label("공연: \(c.showDate.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "music.mic")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(headline)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(
                    "\(bundle.suggestedDepartureDate.formatted(date: .abbreviated, time: .omitted)) – \(bundle.suggestedReturnDate.formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)

            if let headerImage {
                ImageAttributionLabel(image: headerImage)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .frame(height: 200, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var heroTopic: String {
        switch bundle.source {
        case .concert(let c):
            return "\(c.city) skyline night"
        case .content(let c):
            if let place = c.detectedPlaceName, !place.isEmpty { return place }
            return "\(c.detectedCity) travel"
        case .manual:
            return "travel"
        }
    }

    private var heroTint: Color {
        switch bundle.source {
        case .concert: return .purple
        case .content: return .pink
        case .manual:  return .blue
        }
    }

    private var flightsSection: some View {
        sectionCard(title: "항공편") {
            if bundle.flights.isEmpty {
                Text("이 날짜의 항공 운임을 가져오지 못했어요.")
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
                                Text("운임 보기").foregroundStyle(.secondary)
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
        sectionCard(title: "근처 숙소") {
            if bundle.hotels.isEmpty {
                Text("이 날짜에 가져올 수 있는 숙소가 없어요.")
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
                            Text("₩\(h.pricePerNightKRW.formatted())/박")
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                        Text(hotelCaption(h))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if h.freeCancellation {
                            Label("무료 취소", systemImage: "checkmark.seal")
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
            parts.append("\(h.distanceMetersFromAnchor)m 거리")
        }
        if h.starRating > 0 {
            parts.append(String(format: "%.1f★", h.starRating))
        }
        if h.userRating > 0 {
            parts.append(String(format: "투숙객 %.1f", h.userRating))
        }
        return parts.joined(separator: " · ")
    }

    private var activitiesSection: some View {
        sectionCard(title: "추천 액티비티") {
            if bundle.activities.isEmpty {
                Text("이 도시의 액티비티가 없어요.")
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
        if a.durationHours > 0 { parts.append(String(format: "%.1f시간", a.durationHours)) }
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
        case .manual: return "여행"
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
